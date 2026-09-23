#!/usr/bin/env bash
# Run a configuration step for a generated pod build, inside the command pod by default.
#
#   configure.sh --method ansible --playbook playbooks/x.yml --vars BUILD/ansible/vars.yml --build-dir BUILD [opts] [-- extra ansible args]
#   configure.sh --method shell   --script  configure/x.sh    --env  BUILD/configure.env     --build-dir BUILD [opts] [-- extra script args]
#
#   --via command-pod|local   where to run (default: $CONFIGURE_VIA or command-pod)
#   --scale-down              scale the command pod to 0 afterwards (or COMMAND_POD_SCALE_DOWN=1)
#
# command-pod mode: makes sure the pod is running and allowed to touch the target namespace, syncs
# ./ansible, ./configure and the build directory into it, then runs the step there.
# local mode: runs the same step from this machine (needs ansible/kubectl/openssl/keytool locally).
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

method="" playbook="" script="" vars_file="" env_file="" build_dir=""
via="${CONFIGURE_VIA:-command-pod}"
scale_down="${COMMAND_POD_SCALE_DOWN:-0}"
extra=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --method)     method=$2; shift 2 ;;
    --playbook)   playbook=$2; shift 2 ;;
    --script)     script=$2; shift 2 ;;
    --vars)       vars_file=$2; shift 2 ;;
    --env)        env_file=$2; shift 2 ;;
    --build-dir)  build_dir=$2; shift 2 ;;
    --via)        via=$2; shift 2 ;;
    --scale-down) scale_down=1; shift ;;
    -h|--help)    sed -n '2,13p' "${BASH_SOURCE[0]}"; exit 0 ;;
    --)           shift; extra+=("$@"); break ;;
    *)            extra+=("$1"); shift ;;
  esac
done

[[ "$method" == "ansible" || "$method" == "shell" ]] || die "--method must be ansible or shell"
[[ -n "$build_dir" && -d "$build_dir" ]] || die "--build-dir must point to a generated build directory"
build_dir="$(cd "$build_dir" && pwd)"
if [[ "$method" == "ansible" ]]; then
  [[ -n "$playbook" ]] || die "--playbook is required for --method ansible"
  [[ -f "$PODKIT_ROOT/ansible/$playbook" ]] || die "playbook not found: ansible/$playbook"
  vars_file="${vars_file:-$build_dir/ansible/vars.yml}"
  [[ -f "$vars_file" ]] || die "vars file not found: $vars_file"
else
  [[ -n "$script" ]] || die "--script is required for --method shell"
  [[ -f "$PODKIT_ROOT/$script" ]] || die "script not found: $script"
  env_file="${env_file:-$build_dir/configure.env}"
  [[ -f "$env_file" ]] || die "env file not found: $env_file"
fi

# Remote layout inside the command pod:
#   /work/podkit/ansible, /work/podkit/configure   (synced from this checkout)
#   /work/build/<provider>/<name>                  (the generated build directory)
remote_build="/work/build/$(basename "$(dirname "$build_dir")")/$(basename "$build_dir")"

quote_args() { local q=""; local a; for a in "$@"; do q+=" $(printf '%q' "$a")"; done; printf '%s' "$q"; }

case "$via" in
  command-pod)
    require_cmd kubectl tar
    cp=("$PODKIT_ROOT/bin/podkit" command-pod)
    "${cp[@]}" ensure
    "${cp[@]}" sync "$PODKIT_ROOT/ansible" /work/podkit/ansible
    "${cp[@]}" sync "$PODKIT_ROOT/configure" /work/podkit/configure
    # vars/env files outside the build directory are copied into it so the sync carries them along
    if [[ "$method" == "ansible" ]]; then
      case "$vars_file" in "$build_dir"/*) ;; *) cp "$vars_file" "$build_dir/.podkit-vars.yml"; vars_file="$build_dir/.podkit-vars.yml" ;; esac
      remote_vars="$remote_build/${vars_file#"$build_dir"/}"
    else
      case "$env_file" in "$build_dir"/*) ;; *) cp "$env_file" "$build_dir/.podkit-configure.env"; env_file="$build_dir/.podkit-configure.env" ;; esac
      remote_env="$remote_build/${env_file#"$build_dir"/}"
    fi
    "${cp[@]}" sync "$build_dir" "$remote_build"
    if [[ "$method" == "ansible" ]]; then
      log "Running playbook $playbook in the command pod"
      "${cp[@]}" run -- bash -lc "cd /work/podkit/ansible && ansible-playbook '$playbook' \
        -e @'$remote_vars' -e build_dir='$remote_build'$(quote_args ${extra[@]+"${extra[@]}"})"
    else
      log "Running script $script in the command pod"
      "${cp[@]}" run -- bash -lc "export BUILD_DIR='$remote_build'; set -a; . '$remote_env'; set +a; \
        bash '/work/podkit/$script'$(quote_args ${extra[@]+"${extra[@]}"})"
    fi
    if [[ "$scale_down" == "1" ]]; then
      "${cp[@]}" scale 0
    fi ;;
  local)
    export BUILD_DIR="$build_dir"
    [[ -n "${KUBE_CONTEXT:-}" ]] && export K8S_AUTH_CONTEXT="$KUBE_CONTEXT"
    if [[ "$method" == "ansible" ]]; then
      require_cmd ansible-playbook kubectl
      log "Running playbook $playbook locally"
      (cd "$PODKIT_ROOT/ansible" && ansible-playbook "$playbook" -e "@$vars_file" -e "build_dir=$build_dir" ${extra[@]+"${extra[@]}"})
    else
      require_cmd kubectl
      log "Running script $script locally"
      set -a
      # shellcheck source=/dev/null
      source "$env_file"
      set +a
      bash "$PODKIT_ROOT/$script" ${extra[@]+"${extra[@]}"}
    fi ;;
  *) die "--via must be command-pod or local" ;;
esac
log "Configuration step finished"
