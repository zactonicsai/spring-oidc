# gitlite — a tiny git-like versioned file server in Go

No auth, no dependencies beyond the Go standard library.

## Build
    go build -o gitlite-server ./server
    go build -o gitlite ./client

## Run the server
    ./gitlite-server -dir ./repos -port 8080

## Client
    ./gitlite clone http://localhost:8080/myrepo [dir]   # download latest snapshot
    ./gitlite add [-m "message"] file1 file2 ...          # upload -> new version
    ./gitlite pull [-v N]                                 # get version N (default latest)
    ./gitlite versions                                    # list all versions

The remote URL is stored in a `.gitlite` file in the working directory.
Repos are created automatically on first `add`.

## HTTP API (usable with curl too)
    POST /{repo}/add                       multipart form, field "file" (repeatable), optional "message"
    GET  /{repo}/clone                     tar of latest snapshot
    GET  /{repo}/pull?version=N            tar of snapshot at version N
    GET  /{repo}/versions                  meta.json
    GET  /{repo}/file/{name}?version=N     one file
    GET  /                                 list repos

    curl -F file=@a.txt -F file=@b.txt -F message=first http://localhost:8080/demo/add
    curl http://localhost:8080/demo/versions
    curl "http://localhost:8080/demo/pull?version=1" | tar x

## Storage layout
    repos/<repo>/files/<name>.v<N>   copy of each file, suffixed with the version it was added in
    repos/<repo>/meta.json           every add: version, date, files, byte count, message

A snapshot at version N = for each file name, the newest copy with version <= N,
so versions are cumulative like git commits.
