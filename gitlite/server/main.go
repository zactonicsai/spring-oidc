// gitlite: a tiny GitHub-style git server in Go.
//
// Speaks git's smart HTTP protocol, so the standard git client works:
//
//	git clone http://host:8080/myrepo.git
//	git push  http://host:8080/newrepo.git main     (repo is created on first push)
//	git pull
//	git checkout v3                                  (every push is tagged v1, v2, ...)
//
// On every push the server records a new version:
//
//	<dir>/<repo>.git/              bare git repository
//	<dir>/<repo>.git/files/<path>.v<N>   copy of each file changed in version N
//	<dir>/<repo>.git/meta.json     every push: version, date, commit, author, message, files, bytes
//
// Extra endpoints:
//
//	GET /                          list repos
//	GET /{repo}/versions           meta.json
//	GET /{repo}/pull?version=N     tar of the repo at version N (default latest)
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"net/http/cgi"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

type Add struct {
	Version int       `json:"version"`
	Date    time.Time `json:"date"`
	Commit  string    `json:"commit"`
	Author  string    `json:"author"`
	Message string    `json:"message"`
	Files   []string  `json:"files"`
	Bytes   int64     `json:"bytes"`
}

type Meta struct {
	Repo    string    `json:"repo"`
	Latest  int       `json:"latest"`
	Created time.Time `json:"created"`
	Adds    []Add     `json:"adds"`
}

var (
	root   string
	mu     sync.Mutex
	nameRe = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)
)

func main() {
	flag.StringVar(&root, "dir", "./repos", "directory where repositories are stored")
	port := flag.String("port", "8080", "port to listen on")
	flag.Parse()
	var err error
	if root, err = filepath.Abs(root); err != nil {
		log.Fatal(err)
	}
	if err := os.MkdirAll(root, 0o755); err != nil {
		log.Fatal(err)
	}
	backend, err := exec.Command("git", "--exec-path").Output()
	if err != nil {
		log.Fatal("git not found: ", err)
	}
	gitCGI := &cgi.Handler{
		Path:       filepath.Join(strings.TrimSpace(string(backend)), "git-http-backend"),
		Env:        []string{"GIT_PROJECT_ROOT=" + root, "GIT_HTTP_EXPORT_ALL=1"},
		InheritEnv: []string{"PATH", "HOME"},
	}

	log.Printf("gitlite serving %s on :%s", root, *port)
	log.Fatal(http.ListenAndServe(":"+*port, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s %s", r.Method, r.URL)
		route(w, r, gitCGI)
	})))
}

// route: "/" -> list; "/{repo}/versions" and "/{repo}/pull" -> ours; everything else -> git.
func route(w http.ResponseWriter, r *http.Request, gitCGI *cgi.Handler) {
	parts := strings.SplitN(strings.Trim(r.URL.Path, "/"), "/", 2)
	if parts[0] == "" {
		listRepos(w)
		return
	}
	repo := strings.TrimSuffix(parts[0], ".git")
	if !nameRe.MatchString(repo) {
		http.Error(w, "bad repo name", 400)
		return
	}
	rest := ""
	if len(parts) > 1 {
		rest = parts[1]
	}
	switch rest {
	case "versions":
		handleVersions(w, repo)
		return
	case "pull":
		handlePull(w, r, repo)
		return
	}

	// --- git smart HTTP ---
	push := r.URL.Query().Get("service") == "git-receive-pack" || rest == "git-receive-pack"
	if _, err := os.Stat(gitDir(repo)); err != nil {
		if !push {
			http.Error(w, "repo not found", 404)
			return
		}
		if err := initRepo(repo); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
	}
	r.URL.Path = "/" + repo + ".git/" + rest // normalise so PATH_INFO always has .git
	gitCGI.ServeHTTP(w, r)
	if push && r.Method == "POST" {
		mu.Lock()
		if err := snapshot(repo); err != nil {
			log.Printf("snapshot %s: %v", repo, err)
		}
		mu.Unlock()
	}
}

// ---------- handlers ----------

func listRepos(w http.ResponseWriter) {
	entries, _ := os.ReadDir(root)
	repos := []string{}
	for _, e := range entries {
		if e.IsDir() && strings.HasSuffix(e.Name(), ".git") {
			repos = append(repos, strings.TrimSuffix(e.Name(), ".git"))
		}
	}
	writeJSON(w, map[string]any{"repos": repos})
}

func handleVersions(w http.ResponseWriter, repo string) {
	meta, err := loadMeta(repo)
	if err != nil {
		http.Error(w, "repo not found", 404)
		return
	}
	writeJSON(w, meta)
}

func handlePull(w http.ResponseWriter, r *http.Request, repo string) {
	meta, err := loadMeta(repo)
	if err != nil {
		http.Error(w, "repo not found", 404)
		return
	}
	v := r.URL.Query().Get("version")
	ver := meta.Latest
	if v != "" && v != "latest" {
		n, err := strconv.Atoi(strings.TrimPrefix(v, "v"))
		if err != nil || n < 1 || n > meta.Latest {
			http.Error(w, fmt.Sprintf("invalid version %q (latest is %d)", v, meta.Latest), 400)
			return
		}
		ver = n
	}
	if ver == 0 {
		http.Error(w, "repo is empty", 404)
		return
	}
	w.Header().Set("Content-Type", "application/x-tar")
	w.Header().Set("X-Gitlite-Version", strconv.Itoa(ver))
	cmd := exec.Command("git", "--git-dir="+gitDir(repo), "archive", "--format=tar", "v"+strconv.Itoa(ver))
	cmd.Stdout = w
	cmd.Run()
}

// ---------- git helpers ----------

func gitDir(repo string) string   { return filepath.Join(root, repo+".git") }
func metaPath(repo string) string { return filepath.Join(gitDir(repo), "meta.json") }
func filesDir(repo string) string { return filepath.Join(gitDir(repo), "files") }

func git(repo string, args ...string) (string, error) {
	cmd := exec.Command("git", append([]string{"--git-dir=" + gitDir(repo)}, args...)...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("git %s: %s", strings.Join(args, " "), strings.TrimSpace(stderr.String()))
	}
	return strings.TrimSpace(string(out)), nil
}

func initRepo(repo string) error {
	if err := exec.Command("git", "init", "--bare", "-b", "main", gitDir(repo)).Run(); err != nil {
		return err
	}
	if _, err := git(repo, "config", "http.receivepack", "true"); err != nil {
		return err
	}
	if err := os.MkdirAll(filesDir(repo), 0o755); err != nil {
		return err
	}
	return saveMeta(repo, &Meta{Repo: repo, Created: time.Now().UTC(), Adds: []Add{}})
}

// snapshot records the pushed HEAD as a new version: copies changed files to
// files/<path>.v<N>, tags the commit v<N>, appends an entry to meta.json.
func snapshot(repo string) error {
	head, err := git(repo, "rev-parse", "HEAD")
	if err != nil { // HEAD points at a branch that was never pushed (e.g. master); repoint it
		branches, berr := git(repo, "for-each-ref", "--format=%(refname)", "refs/heads")
		if berr != nil || branches == "" {
			return nil // nothing pushed yet
		}
		git(repo, "symbolic-ref", "HEAD", strings.Split(branches, "\n")[0])
		if head, err = git(repo, "rev-parse", "HEAD"); err != nil {
			return err
		}
	}
	meta, err := loadMeta(repo)
	if err != nil {
		return err
	}
	if n := len(meta.Adds); n > 0 && meta.Adds[n-1].Commit == head {
		return nil // nothing new
	}

	ver := meta.Latest + 1
	var files string
	if len(meta.Adds) > 0 {
		files, err = git(repo, "diff", "--name-only", "--diff-filter=ACMR", meta.Adds[len(meta.Adds)-1].Commit, head)
	}
	if err != nil || len(meta.Adds) == 0 { // first push or history rewritten: take everything
		if files, err = git(repo, "ls-tree", "-r", "--name-only", head); err != nil {
			return err
		}
	}
	add := Add{Version: ver, Date: time.Now().UTC(), Commit: head, Files: []string{}}
	add.Author, _ = git(repo, "log", "-1", "--format=%an <%ae>", head)
	add.Message, _ = git(repo, "log", "-1", "--format=%s", head)
	for _, f := range strings.Split(files, "\n") {
		if f == "" {
			continue
		}
		cmd := exec.Command("git", "--git-dir="+gitDir(repo), "show", head+":"+f)
		content, err := cmd.Output()
		if err != nil {
			continue
		}
		dst := filepath.Join(filesDir(repo), fmt.Sprintf("%s.v%d", f, ver))
		os.MkdirAll(filepath.Dir(dst), 0o755)
		if err := os.WriteFile(dst, content, 0o644); err != nil {
			return err
		}
		add.Files = append(add.Files, f)
		add.Bytes += int64(len(content))
	}
	if _, err := git(repo, "tag", "-f", "v"+strconv.Itoa(ver), head); err != nil {
		return err
	}
	meta.Latest = ver
	meta.Adds = append(meta.Adds, add)
	log.Printf("%s: version %d (%s) %d file(s)", repo, ver, head[:7], len(add.Files))
	return saveMeta(repo, meta)
}

// ---------- meta ----------

func loadMeta(repo string) (*Meta, error) {
	b, err := os.ReadFile(metaPath(repo))
	if err != nil {
		return nil, err
	}
	var m Meta
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, err
	}
	if m.Adds == nil {
		m.Adds = []Add{}
	}
	return &m, nil
}

func saveMeta(repo string, m *Meta) error {
	b, _ := json.MarshalIndent(m, "", "  ")
	tmp := metaPath(repo) + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, metaPath(repo))
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	enc.Encode(v)
}
