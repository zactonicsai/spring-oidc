#!/usr/bin/env bash
# podkit resource: configuration steps (Ansible playbook or shell script) for a build, executed inside
# the command pod by default. The low-level runner is scripts/configure.sh.
# shellcheck shell=bash

RESOURCE_DESC="Configuration steps: run a build's Ansible/shell step, or any script inside the pods"
RESOURCE_VERBS="run script info"

resource_usage() {
  cat <<'USAGE'
  podkit configure run BUILD_DIR [--via command-pod|local] [--scale-down] [-- extra args]
        runs the build's step (pod.env: CONFIGURE_METHOD/TARGET); extra args go to ansible-playbook or the script
        e.g. podkit configure run build/aws/java-server -- -e rotate=true
  podkit configure script BUILD_DIR SCRIPT [-- args]   copy SCRIPT into the build's running pods and execute it
  podkit configure info BUILD_DIR                      show method, phase and target
USAGE
}

# configure_run_build BUILD_DIR [--via X] [--scale-down] [extra...]
configure_run_build() {
  local dir=$1; shift
  build_load "$dir"
  if [[ "${CONFIGURE_METHOD:-none}" == "none" ]]; then
    log "no configuration step is defined for $NAME (spec.configure.method = none)"; return 0
  fi
  local opts=() extra=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --via) opts+=(--via "$2"); shift 2 ;;
      --scale-down) opts+=(--scale-down); shift ;;
      --) shift; extra+=("$@"); break ;;
      *) extra+=("$1"); shift ;;
    esac
  done
  if dry_run; then
    log "[dry-run] would run $CONFIGURE_METHOD step $CONFIGURE_TARGET (${CONFIGURE_PHASE}-deploy) for $NAME${extra[*]:+ with: ${extra[*]}}"
    return 0
  fi
  local runner="$PODKIT_ROOT/scripts/configure.sh"
  case "$CONFIGURE_METHOD" in
    ansible) "$runner" --method ansible --playbook "$CONFIGURE_TARGET" --vars "$BUILD_DIR/ansible/vars.yml" \
               --build-dir "$BUILD_DIR" ${opts[@]+"${opts[@]}"} ${extra[@]+"${extra[@]}"} ;;
    shell)   "$runner" --method shell --script "$CONFIGURE_TARGET" --env "$BUILD_DIR/configure.env" \
               --build-dir "$BUILD_DIR" ${opts[@]+"${opts[@]}"} ${extra[@]+"${extra[@]}"} ;;
    *) die "unknown configure method: $CONFIGURE_METHOD" ;;
  esac
}

# configure_script_build BUILD_DIR SCRIPT [--via X] [args...] -> run-script flow (copy + exec in every running pod)
configure_script_build() {
  local dir=$1 script=$2; shift 2
  build_load "$dir"
  [[ -f "$script" ]] || die "script not found: $script"
  local opts=() args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --via) opts+=(--via "$2"); shift 2 ;;
      --) shift; args+=("$@"); break ;;
      *) args+=("$1"); shift ;;
    esac
  done
  # the script and its env file live inside the build dir so the command-pod sync carries them
  mkdir -p "$BUILD_DIR/.scripts"
  cp "$script" "$BUILD_DIR/.scripts/$(basename "$script")"
  cat > "$BUILD_DIR/.scripts/run-script.env" <<ENV
NAMESPACE=$NAMESPACE
TARGET_SELECTOR=app.kubernetes.io/name=$NAME
CONTAINER=$NAME
SCRIPT=.scripts/$(basename "$script")
SCRIPT_ARGS=${args[*]:-}
ENV
  if dry_run; then log "[dry-run] would run $script in the pods of $NAME"; return 0; fi
  "$PODKIT_ROOT/scripts/configure.sh" --method shell --script configure/run-script.sh \
    --env "$BUILD_DIR/.scripts/run-script.env" --build-dir "$BUILD_DIR" ${opts[@]+"${opts[@]}"}
}

cmd_run()    { [[ -n "${1:-}" ]] || die "usage: podkit configure run BUILD_DIR [--via X] [-- extra]"; configure_run_build "$@"; }
cmd_script() { [[ $# -ge 2 ]] || die "usage: podkit configure script BUILD_DIR SCRIPT [--via X] [-- args]"; configure_script_build "$@"; }
cmd_info()   { build_load "${1:-}"; echo "method : ${CONFIGURE_METHOD:-none}"; echo "phase  : ${CONFIGURE_PHASE:-}"; echo "target : ${CONFIGURE_TARGET:-}"; }
