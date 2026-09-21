// gitlite server: a tiny git-like versioned file server.
//
// Storage layout (under -dir):
//
//	<repo>/files/<name>.v<N>   one copy per file per version it was added in
//	<repo>/meta.json           history of every add (version, date, files, bytes)
//
// Endpoints (no auth):
//
//	POST /{repo}/add              multipart upload; creates a new version
//	GET  /{repo}/clone            tar of latest snapshot (same as pull)
//	GET  /{repo}/pull[?version=N] tar of snapshot at version N (default latest)
//	GET  /{repo}/versions         meta.json (list of all versions)
//	GET  /{repo}/file/{name}[?version=N]  single file at version N
//
// A snapshot at version N = for each file name, the newest copy with version <= N.
package main

import (
	"archive/tar"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

type Add struct {
	Version int       `json:"version"`
	Date    time.Time `json:"date"`
	Files   []string  `json:"files"`
	Bytes   int64     `json:"bytes"`
	Message string    `json:"message,omitempty"`
}

type Meta struct {
	Repo    string    `json:"repo"`
	Latest  int       `json:"latest"`
	Created time.Time `json:"created"`
	Adds    []Add     `json:"adds"`
}

var (
	root     string
	mu       sync.Mutex // one writer at a time; simple and safe enough
	nameRe   = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)
	suffixRe = regexp.MustCompile(`^(.*)\.v(\d+)$`)
)

func main() {
	flag.StringVar(&root, "dir", "./repos", "directory where repositories are stored")
	port := flag.String("port", "8080", "port to listen on")
	flag.Parse()
	if err := os.MkdirAll(root, 0o755); err != nil {
		log.Fatal(err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /{repo}/add", handleAdd)
	mux.HandleFunc("GET /{repo}/clone", handlePull)
	mux.HandleFunc("GET /{repo}/pull", handlePull)
	mux.HandleFunc("GET /{repo}/versions", handleVersions)
	mux.HandleFunc("GET /{repo}/file/{name}", handleFile)
	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		entries, _ := os.ReadDir(root)
		var repos []string
		for _, e := range entries {
			if e.IsDir() {
				repos = append(repos, e.Name())
			}
		}
		writeJSON(w, map[string]any{"repos": repos})
	})

	log.Printf("gitlite serving %s on :%s", root, *port)
	log.Fatal(http.ListenAndServe(":"+*port, logRequests(mux)))
}

// ---------- handlers ----------

func handleAdd(w http.ResponseWriter, r *http.Request) {
	repo := r.PathValue("repo")
	if !nameRe.MatchString(repo) {
		http.Error(w, "bad repo name", 400)
		return
	}
	if err := r.ParseMultipartForm(64 << 20); err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	files := r.MultipartForm.File["file"]
	if len(files) == 0 {
		http.Error(w, "no files (use form field 'file')", 400)
		return
	}

	mu.Lock()
	defer mu.Unlock()

	meta, err := loadMeta(repo, true)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	ver := meta.Latest + 1
	add := Add{Version: ver, Date: time.Now().UTC(), Message: r.FormValue("message")}

	for _, fh := range files {
		name := filepath.Base(fh.Filename)
		if !nameRe.MatchString(name) || suffixRe.MatchString(name) {
			http.Error(w, "bad file name: "+fh.Filename, 400)
			return
		}
		src, err := fh.Open()
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		dst, err := os.Create(filepath.Join(filesDir(repo), fmt.Sprintf("%s.v%d", name, ver)))
		if err != nil {
			src.Close()
			http.Error(w, err.Error(), 500)
			return
		}
		n, err := io.Copy(dst, src)
		src.Close()
		dst.Close()
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		add.Files = append(add.Files, name)
		add.Bytes += n
	}
	sort.Strings(add.Files)

	meta.Latest = ver
	meta.Adds = append(meta.Adds, add)
	if err := saveMeta(repo, meta); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	writeJSON(w, add)
}

func handlePull(w http.ResponseWriter, r *http.Request) {
	repo := r.PathValue("repo")
	meta, err := loadMeta(repo, false)
	if err != nil {
		http.Error(w, err.Error(), 404)
		return
	}
	ver, err := parseVersion(r.URL.Query().Get("version"), meta.Latest)
	if err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	snap, err := snapshot(repo, ver)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	w.Header().Set("Content-Type", "application/x-tar")
	w.Header().Set("X-Gitlite-Version", strconv.Itoa(ver))
	tw := tar.NewWriter(w)
	defer tw.Close()
	for _, name := range sortedKeys(snap) {
		path := snap[name]
		st, err := os.Stat(path)
		if err != nil {
			return
		}
		tw.WriteHeader(&tar.Header{Name: name, Mode: 0o644, Size: st.Size(), ModTime: st.ModTime()})
		f, err := os.Open(path)
		if err != nil {
			return
		}
		io.Copy(tw, f)
		f.Close()
	}
}

func handleVersions(w http.ResponseWriter, r *http.Request) {
	meta, err := loadMeta(r.PathValue("repo"), false)
	if err != nil {
		http.Error(w, err.Error(), 404)
		return
	}
	writeJSON(w, meta)
}

func handleFile(w http.ResponseWriter, r *http.Request) {
	repo, name := r.PathValue("repo"), r.PathValue("name")
	meta, err := loadMeta(repo, false)
	if err != nil {
		http.Error(w, err.Error(), 404)
		return
	}
	ver, err := parseVersion(r.URL.Query().Get("version"), meta.Latest)
	if err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	snap, err := snapshot(repo, ver)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	path, ok := snap[name]
	if !ok {
		http.Error(w, "file not in version "+strconv.Itoa(ver), 404)
		return
	}
	http.ServeFile(w, r, path)
}

// ---------- storage helpers ----------

func filesDir(repo string) string { return filepath.Join(root, repo, "files") }
func metaPath(repo string) string { return filepath.Join(root, repo, "meta.json") }

func loadMeta(repo string, create bool) (*Meta, error) {
	if !nameRe.MatchString(repo) {
		return nil, errors.New("bad repo name")
	}
	b, err := os.ReadFile(metaPath(repo))
	if errors.Is(err, os.ErrNotExist) {
		if !create {
			return nil, errors.New("repo not found")
		}
		if err := os.MkdirAll(filesDir(repo), 0o755); err != nil {
			return nil, err
		}
		return &Meta{Repo: repo, Created: time.Now().UTC(), Adds: []Add{}}, nil
	}
	if err != nil {
		return nil, err
	}
	var m Meta
	return &m, json.Unmarshal(b, &m)
}

func saveMeta(repo string, m *Meta) error {
	b, _ := json.MarshalIndent(m, "", "  ")
	tmp := metaPath(repo) + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, metaPath(repo))
}

// snapshot returns name -> path of the newest copy of each file with version <= ver.
func snapshot(repo string, ver int) (map[string]string, error) {
	entries, err := os.ReadDir(filesDir(repo))
	if err != nil {
		return nil, err
	}
	best := map[string]int{}
	out := map[string]string{}
	for _, e := range entries {
		m := suffixRe.FindStringSubmatch(e.Name())
		if m == nil {
			continue
		}
		v, _ := strconv.Atoi(m[2])
		if v <= ver && v > best[m[1]] {
			best[m[1]] = v
			out[m[1]] = filepath.Join(filesDir(repo), e.Name())
		}
	}
	return out, nil
}

func parseVersion(s string, latest int) (int, error) {
	if s == "" || s == "latest" {
		return latest, nil
	}
	v, err := strconv.Atoi(strings.TrimPrefix(s, "v"))
	if err != nil || v < 1 || v > latest {
		return 0, fmt.Errorf("invalid version %q (latest is %d)", s, latest)
	}
	return v, nil
}

func sortedKeys(m map[string]string) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	enc.Encode(v)
}

func logRequests(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s %s", r.Method, r.URL)
		h.ServeHTTP(w, r)
	})
}
