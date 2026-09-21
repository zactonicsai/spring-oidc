// gitlite client
//
//	gitlite clone http://host:8080/myrepo [dir]     download latest snapshot into dir
//	gitlite add [-m "msg"] file1 file2 ...          upload files as a new version
//	gitlite pull [-v N]                             replace working files with version N (default latest)
//	gitlite versions                                list all versions
//
// The remote URL is remembered in a .gitlite file in the working directory.
package main

import (
	"archive/tar"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const cfgFile = ".gitlite"

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	var err error
	switch os.Args[1] {
	case "clone":
		err = clone(os.Args[2:])
	case "add":
		err = add(os.Args[2:])
	case "pull":
		err = pull(os.Args[2:])
	case "versions":
		err = versions()
	default:
		usage()
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `usage:
  gitlite clone <url> [dir]
  gitlite add [-m msg] <files...>
  gitlite pull [-v N]
  gitlite versions`)
	os.Exit(2)
}

func clone(args []string) error {
	if len(args) < 1 {
		usage()
	}
	remote := strings.TrimRight(args[0], "/")
	dir := filepath.Base(remote)
	if len(args) > 1 {
		dir = args[1]
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, cfgFile), []byte(remote+"\n"), 0o644); err != nil {
		return err
	}
	ver, n, err := download(remote+"/clone", dir)
	if err != nil {
		return err
	}
	fmt.Printf("cloned %s into %s (version %s, %d files)\n", remote, dir, ver, n)
	return nil
}

func add(args []string) error {
	fs := flag.NewFlagSet("add", flag.ExitOnError)
	msg := fs.String("m", "", "message")
	fs.Parse(args)
	if fs.NArg() == 0 {
		return fmt.Errorf("no files given")
	}
	remote, err := readRemote()
	if err != nil {
		return err
	}

	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	mw.WriteField("message", *msg)
	for _, path := range fs.Args() {
		part, err := mw.CreateFormFile("file", filepath.Base(path))
		if err != nil {
			return err
		}
		f, err := os.Open(path)
		if err != nil {
			return err
		}
		_, err = io.Copy(part, f)
		f.Close()
		if err != nil {
			return err
		}
	}
	mw.Close()

	resp, err := http.Post(remote+"/add", mw.FormDataContentType(), &body)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("server: %s", strings.TrimSpace(string(b)))
	}
	var res struct {
		Version int      `json:"version"`
		Files   []string `json:"files"`
		Bytes   int64    `json:"bytes"`
	}
	json.NewDecoder(resp.Body).Decode(&res)
	fmt.Printf("added %d file(s), %d bytes -> version %d\n", len(res.Files), res.Bytes, res.Version)
	return nil
}

func pull(args []string) error {
	fs := flag.NewFlagSet("pull", flag.ExitOnError)
	v := fs.String("v", "", "version to pull (default latest)")
	fs.Parse(args)
	remote, err := readRemote()
	if err != nil {
		return err
	}
	url := remote + "/pull"
	if *v != "" {
		url += "?version=" + *v
	}
	ver, n, err := download(url, ".")
	if err != nil {
		return err
	}
	fmt.Printf("pulled version %s (%d files)\n", ver, n)
	return nil
}

func versions() error {
	remote, err := readRemote()
	if err != nil {
		return err
	}
	resp, err := http.Get(remote + "/versions")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("server: %s", strings.TrimSpace(string(b)))
	}
	var meta struct {
		Repo   string `json:"repo"`
		Latest int    `json:"latest"`
		Adds   []struct {
			Version int       `json:"version"`
			Date    time.Time `json:"date"`
			Files   []string  `json:"files"`
			Bytes   int64     `json:"bytes"`
			Message string    `json:"message"`
		} `json:"adds"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&meta); err != nil {
		return err
	}
	fmt.Printf("%s: %d version(s)\n", meta.Repo, meta.Latest)
	for _, a := range meta.Adds {
		fmt.Printf("  v%-4d %s  %6d B  %s", a.Version, a.Date.Local().Format("2006-01-02 15:04:05"), a.Bytes, strings.Join(a.Files, ", "))
		if a.Message != "" {
			fmt.Printf("  # %s", a.Message)
		}
		fmt.Println()
	}
	return nil
}

// download fetches a tar from url and unpacks it into dir. Returns version and file count.
func download(url, dir string) (string, int, error) {
	resp, err := http.Get(url)
	if err != nil {
		return "", 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return "", 0, fmt.Errorf("server: %s", strings.TrimSpace(string(b)))
	}
	ver := resp.Header.Get("X-Gitlite-Version")
	tr := tar.NewReader(resp.Body)
	n := 0
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return ver, n, err
		}
		out, err := os.Create(filepath.Join(dir, filepath.Base(hdr.Name)))
		if err != nil {
			return ver, n, err
		}
		_, err = io.Copy(out, tr)
		out.Close()
		if err != nil {
			return ver, n, err
		}
		n++
	}
	return ver, n, nil
}

func readRemote() (string, error) {
	b, err := os.ReadFile(cfgFile)
	if err != nil {
		return "", fmt.Errorf("not a gitlite directory (no %s file); run clone first", cfgFile)
	}
	return strings.TrimSpace(string(b)), nil
}
