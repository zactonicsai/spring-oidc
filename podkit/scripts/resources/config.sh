#!/usr/bin/env bash
# podkit resource: PodConfig files (the generator). Wraps `python -m podgen`.
# shellcheck shell=bash

RESOURCE_DESC="PodConfig files: validate, generate build/<cloud>/<name>, print the schema"
RESOURCE_VERBS="generate validate schema"

resource_usage() {
  cat <<'USAGE'
  podkit generate CONFIG... [--provider aws|azure|gcp|all] [--out DIR] [--force]
  podkit validate CONFIG... [--provider P]
  podkit schema
  (podkit config <verb> is the same thing; PODKIT_PYTHON overrides the interpreter)
USAGE
}

config_podgen() {
  local py="${PODKIT_PYTHON:-python3}"
  require_cmd "$py"
  PYTHONPATH="$PODKIT_ROOT${PYTHONPATH:+:$PYTHONPATH}" "$py" -m podgen "$@"
}

cmd_generate() { config_podgen generate "$@"; }
cmd_validate() { config_podgen validate "$@"; }
cmd_schema()   { config_podgen schema "$@"; }
