# Bash Administration Script Templates

A small reusable starter kit for writing safer Linux administration scripts. The examples focus on patterns that show up often in operations, SRE, cloud VM, and application-support work: argument parsing, reusable functions, systemd, network ports, process inspection, health checks, logging, cleanup, and failure handling.

## Project layout

```text
bash-admin-templates/
├── README.md
├── lib/
│   └── common.sh
├── templates/
│   ├── basic-template.sh
│   └── advanced-template.sh
├── examples/
│   ├── config-example.env
│   ├── network-check.sh
│   ├── process-inspector.sh
│   ├── service-health-check.sh
│   └── service-manager.sh
└── systemd/
    ├── demo-app.service
    └── install-demo-service.sh
```

## Best-practice design

Most scripts in this project follow this flow:

```text
START
  |
  v
Enable safer Bash options
  |
  v
Find script directory
  |
  v
Load reusable functions
  |
  v
Define constants/defaults
  |
  v
Define usage + helper functions
  |
  v
Install traps for errors/cleanup
  |
  v
Parse getopts options
  |
  v
Validate inputs and dependencies
  |
  v
Run main()
  |
  +--> perform checks/actions
  |
  v
Cleanup via trap
  |
  v
EXIT with meaningful status
```

The goal is to keep the top level predictable. A reader should be able to jump to `main()` and understand the script's business logic without first reading every helper function.

## 1. Safer Bash starting point

Use:

```bash
set -Eeuo pipefail
IFS=$'\n\t'
```

What these do:

- `-e`: stop when an unhandled command fails.
- `-E`: let the `ERR` trap work inside functions and subshell contexts more consistently.
- `-u`: treat an unset variable as an error.
- `-o pipefail`: make a pipeline fail if an earlier command fails.
- `IFS=$'\n\t'`: avoids accidental word splitting on ordinary spaces.

These options are helpful, but they do not replace explicit validation. Commands that are allowed to fail should be handled intentionally with `if`, `|| true`, or another controlled test.

## 2. Always quote variables

Prefer:

```bash
rm -f -- "$file"
systemctl status "$service"
```

The `--` tells many commands that option processing is finished. This protects against a filename such as `-rf` being interpreted as a command option.

## 3. Put the actual workflow in `main()`

Instead of running many commands directly at global scope:

```bash
main() {
  validate
  do_work
  report_result
}

main "$@"
```

This makes scripts easier to review, test, and reuse.

## 4. Use functions for repeated behavior

`lib/common.sh` contains examples:

```bash
info "Starting"
warn "Port not listening"
die "Missing configuration"
require_command systemctl
require_root
is_port_listening 8080
service_is_active nginx.service
```

Functions keep error handling and output consistent.

## 5. Parse short options with `getopts`

Example:

```bash
while getopts ':s:p:vh' opt; do
  case "$opt" in
    s) SERVICE="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    v) VERBOSE=1 ;;
    h) usage; exit 0 ;;
    :) die "Option -$OPTARG requires a value" ;;
    \?) die "Unknown option: -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))
```

The colon after an option means it requires a value. For example `s:` means `-s nginx.service`.

## 6. Traps and cleanup

The templates use traps such as:

```bash
trap cleanup EXIT
trap 'error "Failure near line $LINENO: $BASH_COMMAND"' ERR
trap 'warn "Interrupted"; exit 130' INT TERM
```

Use `EXIT` to delete temporary files or unlock resources. Use `INT` and `TERM` so Ctrl+C and service termination do not leave partial state behind.

## 7. Dry-run support

A reusable `run()` wrapper makes dangerous scripts easier to review:

```bash
run() {
  if (( DRY_RUN )); then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}
```

Then write:

```bash
run systemctl restart nginx.service
```

instead of calling the command directly.

Run the template with:

```bash
./templates/basic-template.sh -n -v
```

## 8. Single-instance locking with `flock`

The advanced template prevents two copies of the same maintenance job from running at once:

```bash
exec 9>/tmp/my-script.lock
flock -n 9 || exit 1
```

This is useful for cron jobs, patching scripts, backups, deployment helpers, and repair jobs.

## 9. Temporary directories with `mktemp`

Never invent predictable temp paths such as `/tmp/app.tmp` when the data matters.

Use:

```bash
TMP_DIR="$(mktemp -d)"
```

and delete it from an `EXIT` trap.

## 10. systemd basics

Common commands:

```bash
systemctl status nginx.service
systemctl is-active nginx.service
systemctl is-enabled nginx.service
sudo systemctl start nginx.service
sudo systemctl stop nginx.service
sudo systemctl restart nginx.service
sudo systemctl enable nginx.service
sudo systemctl disable nginx.service
journalctl -u nginx.service -n 50 --no-pager
journalctl -u nginx.service -f
```

Use the included helper:

```bash
./examples/service-manager.sh -s sshd.service
sudo ./examples/service-manager.sh -s nginx.service -a restart
./examples/service-manager.sh -s nginx.service -f
```

### systemd unit flow

```text
systemctl start demo-app
        |
        v
systemd reads demo-app.service
        |
        v
checks Unit dependencies
        |
        v
runs ExecStart as configured user
        |
        v
application writes stdout/stderr
        |
        v
journald stores logs
        |
        v
Restart=on-failure can restart failed process
```

Install the sample unit:

```bash
sudo ./systemd/install-demo-service.sh
```

Before using it, create the configured user and application path or edit the unit to fit your application.

After changing a unit file:

```bash
sudo systemctl daemon-reload
sudo systemctl restart demo-app.service
```

Check it:

```bash
systemctl status demo-app.service
journalctl -u demo-app.service -n 50 --no-pager
```

## 11. Network checking with `ss`

`ss` is the modern Linux socket-inspection tool and is usually preferred over older `netstat` workflows.

Useful commands:

```bash
ss -lnt
ss -lntp
ss -lnu
ss -lnup
ss -tan
```

Letters used above:

- `l`: listening sockets
- `n`: numeric addresses and ports
- `t`: TCP
- `u`: UDP
- `p`: process information when permissions allow it
- `a`: all sockets

Check port 8080:

```bash
./examples/network-check.sh -p 8080
```

Check port 8443 and look for Java:

```bash
./examples/network-check.sh -p 8443 -P java
```

A useful manual troubleshooting sequence is:

```bash
ss -lntp
curl -v http://127.0.0.1:8080/
systemctl status my-app.service
journalctl -u my-app.service -n 100 --no-pager
```

This answers three different questions: Is anything listening? Can the application answer? What does the service log say?

## 12. Process inspection

Common process tools:

```bash
ps aux
ps -ef
pgrep -a java
pgrep -a -f 'my-app.jar'
top
```

The included process inspector also reads selected Linux `/proc` information:

```bash
./examples/process-inspector.sh -p 1234
./examples/process-inspector.sh -n 'my-app.jar'
```

Its flow is:

```text
PID or name
   |
   v
validate PID is alive with kill -0
   |
   v
show ps summary
   |
   v
read selected /proc/PID/status fields
   |
   v
count file descriptors
   |
   v
look for sockets associated with the PID
```

`kill -0 PID` does not kill the process. It asks the kernel whether the process exists and whether you have permission to signal it.

## 13. Combined service health check

The health-check example combines three layers:

```text
systemd active?
      |
      v
port listening?
      |
      v
HTTP endpoint healthy?
      |
      v
PASS / FAIL
      |
      +---- optional controlled restart
```

Example:

```bash
./examples/service-health-check.sh \
  -s demo-app.service \
  -p 8080 \
  -u http://127.0.0.1:8080/health
```

Allow it to restart a failed service:

```bash
sudo ./examples/service-health-check.sh \
  -s demo-app.service \
  -p 8080 \
  -u http://127.0.0.1:8080/health \
  -r
```

For production automation, use restart behavior carefully. Repeated automatic restarts can hide a real problem. systemd's own restart policy, alerting, and rate limits may be better than an unlimited repair loop.

## 14. Configuration-file example

Run:

```bash
./templates/advanced-template.sh -c ./examples/config-example.env -v
```

The template accepts only known keys rather than blindly `source`-ing arbitrary configuration. This reduces the chance that a configuration file becomes an unexpected shell program.

## 15. Input validation

Validate before making changes:

```bash
[[ "$PORT" =~ ^[0-9]+$ ]] || die "Port must be numeric"
(( PORT >= 1 && PORT <= 65535 )) || die "Port out of range"
[[ -r "$CONFIG_FILE" ]] || die "Config is not readable"
```

Do not trust command-line input just because the script is an internal tool.

## 16. Exit codes

A good administration script should return:

- `0` for success.
- Nonzero for failure.

This lets cron, CI/CD, systemd, Ansible, Terraform external helpers, or another shell script determine whether the task worked.

Example:

```bash
if ./examples/service-health-check.sh -s nginx.service -p 80; then
  echo "healthy"
else
  echo "unhealthy"
fi
```

## 17. Recommended development checks

Install and run ShellCheck when possible:

```bash
shellcheck lib/*.sh templates/*.sh examples/*.sh systemd/*.sh
```

Syntax-check without executing:

```bash
bash -n templates/basic-template.sh
bash -n examples/service-manager.sh
```

For debugging a script locally:

```bash
bash -x ./examples/network-check.sh -p 8080
```

Do not leave `set -x` permanently enabled in scripts that may handle passwords, tokens, secrets, or private paths because tracing can expose them in logs.

## 18. Production checklist

Before using an administration script in production, check that it:

1. Uses `set -Eeuo pipefail` where appropriate.
2. Quotes variables.
3. Validates arguments before changes are made.
4. Checks required commands with `command -v`.
5. Uses absolute or script-relative paths intentionally.
6. Has a `usage()` function.
7. Returns meaningful exit codes.
8. Cleans temporary files with traps.
9. Has a dry-run mode for destructive operations when practical.
10. Requires root only for the operations that really need it.
11. Does not print passwords or tokens.
12. Uses `mktemp` for temporary files/directories.
13. Uses `flock` when duplicate execution could be dangerous.
14. Logs enough information to troubleshoot failures.
15. Passes `bash -n` and preferably ShellCheck.

## 19. A reusable script skeleton

Start new scripts from `templates/basic-template.sh` for normal utilities. Use `templates/advanced-template.sh` when you need configuration files, locking, temporary work areas, and stronger operational controls.

A good rule is to keep four areas separate:

```text
INPUT        getopts, config, environment
   |
VALIDATION   permissions, commands, values, files
   |
ACTION       functions that perform the work
   |
OUTPUT       logs, exit code, cleanup
```

That separation makes scripts easier to read and much safer to change later.
