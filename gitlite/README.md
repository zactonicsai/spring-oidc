# gitlite — a tiny GitHub-style git server in Go

Standard `git` is the client. No auth. Stdlib only (needs `git` installed on the server).

## Build & run
    go build -o gitlite-server ./server
    ./gitlite-server -dir ./repos -port 8080

## Use with plain git
    # push the current directory as a new repo (created automatically on first push)
    git init && git add . && git commit -m "first"
    git remote add origin http://localhost:8080/myrepo.git
    git push origin main

    git clone http://localhost:8080/myrepo.git      # clone
    git pull                                        # pull latest
    git tag                                         # v1, v2, v3 ...  (one tag per push)
    git checkout v2                                 # pull / check out a specific version

## Extra endpoints
    GET /                              list repos
    GET /{repo}/versions               meta.json: every push with date, commit, author, message, files, bytes
    GET /{repo}/pull?version=N         tar of the repo at version N (default latest)

    curl localhost:8080/myrepo/versions
    curl "localhost:8080/myrepo/pull?version=2" | tar x

## Storage layout
    repos/<repo>.git/                  bare git repo (the real history)
    repos/<repo>.git/files/<path>.v<N> copy of every file changed in version N
    repos/<repo>.git/meta.json         stats of all pushes

Each `git push` = one version. Changed files are stored with a `.v<N>` suffix,
the pushed commit is tagged `v<N>`, and an entry is appended to `meta.json`.
