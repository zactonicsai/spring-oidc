#!/usr/bin/env bash
# Resource plugin discovery for the podkit CLI. Source after common.sh.
# shellcheck shell=bash
#
# A resource plugin is one bash file, <name>.sh, that only DEFINES things when sourced:
#   RESOURCE_DESC="one line"                 required
#   RESOURCE_VERBS="deploy status destroy"   required: one cmd_<verb> function per verb
#   cmd_<verb>() { ...; }                    the CLI entry points (receive the remaining args)
#   cmd__default() { ...; }                  optional: called when the first arg is not a verb
#   resource_usage() { ...; }                optional: detailed help (podkit help <name>)
#   <name>_*() { ...; }                      library functions other scripts/plugins may reuse
# Search path (later files override earlier ones with the same name, so you can fork a built-in):
#   $PODKIT_ROOT/scripts/resources  $PODKIT_ROOT/plugins  $PODKIT_PLUGIN_PATH (colon list)  ~/.podkit/plugins
# Files starting with "_" are ignored (templates, shared snippets).

if [[ -n "${_PODKIT_PLUGIN_LOADED:-}" ]]; then return 0; fi
_PODKIT_PLUGIN_LOADED=1

plugin_dirs() {
  local d
  echo "$PODKIT_ROOT/scripts/resources"
  [[ -d "$PODKIT_ROOT/plugins" ]] && echo "$PODKIT_ROOT/plugins"
  if [[ -n "${PODKIT_PLUGIN_PATH:-}" ]]; then
    while IFS= read -r d; do [[ -d "$d" ]] && echo "$d"; done < <(tr ':' '\n' <<<"$PODKIT_PLUGIN_PATH")
  fi
  [[ -d "${HOME:-/nonexistent}/.podkit/plugins" ]] && echo "$HOME/.podkit/plugins"
  return 0
}

# plugin_file NAME -> path of the plugin file (last match wins) or failure
plugin_file() {
  local d found=""
  while IFS= read -r d; do [[ -f "$d/$1.sh" ]] && found="$d/$1.sh"; done < <(plugin_dirs)
  [[ -n "$found" ]] && echo "$found"
}

# plugin_names -> sorted unique resource names
plugin_names() {
  local d f n
  while IFS= read -r d; do
    for f in "$d"/*.sh; do
      [[ -f "$f" ]] || continue
      n="$(basename "$f" .sh)"
      [[ "$n" == _* ]] && continue
      echo "$n"
    done
  done < <(plugin_dirs) | sort -u
}

# plugin_load NAME -> source the plugin into the current shell (sets RESOURCE_NAME/DESC/VERBS)
plugin_load() {
  local f
  f="$(plugin_file "$1")" || return 1
  RESOURCE_NAME="$1"
  RESOURCE_DESC=""
  RESOURCE_VERBS=""
  unset -f cmd__default resource_usage 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$f"
  [[ -n "$RESOURCE_DESC" && -n "$RESOURCE_VERBS" ]] || die "plugin $f must set RESOURCE_DESC and RESOURCE_VERBS"
  local v
  for v in $RESOURCE_VERBS; do
    declare -F "cmd_$v" >/dev/null || die "plugin $f declares verb '$v' but defines no cmd_$v function"
  done
}

# plugin_source NAME... -> load plugins as libraries (their <name>_* functions), ignoring CLI metadata
plugin_source() {
  local n
  for n in "$@"; do plugin_load "$n" >/dev/null || die "unknown resource plugin: $n"; done
}

plugin_has_verb() {
  local v
  for v in $RESOURCE_VERBS; do [[ "$v" == "$1" ]] && return 0; done
  return 1
}

# plugin_list -> table of resources and verbs
plugin_list() {
  local n
  while IFS= read -r n; do
    ( plugin_load "$n" >/dev/null 2>&1 && printf '%-13s %s\n%-13s verbs: %s\n' "$n" "$RESOURCE_DESC" "" "$RESOURCE_VERBS" ) \
      || printf '%-13s (failed to load)\n' "$n"
  done < <(plugin_names)
}

# plugin_usage -> help for the loaded plugin
plugin_usage() {
  echo "podkit $RESOURCE_NAME — $RESOURCE_DESC"
  echo
  if declare -F resource_usage >/dev/null; then
    resource_usage
  else
    local v
    for v in $RESOURCE_VERBS; do echo "  podkit $RESOURCE_NAME $v"; done
  fi
}
