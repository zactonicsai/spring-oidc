#!/usr/bin/env bash
# podkit resource: the command pod container image.
# shellcheck shell=bash

RESOURCE_DESC="Command pod image: build and push (docker)"
RESOURCE_VERBS="build push"

resource_usage() {
  cat <<'USAGE'
  podkit image build [-t IMAGE] [--push]     docker build -f command-pod/Dockerfile (default tag: $COMMAND_POD_IMAGE)
  podkit image push  [-t IMAGE]
USAGE
}

image_tag() {
  local tag="${COMMAND_POD_IMAGE:-ghcr.io/your-org/podkit-command-pod:latest}"
  while [[ $# -gt 0 ]]; do case "$1" in -t|--tag) tag=$2; shift 2 ;; *) shift ;; esac; done
  echo "$tag"
}

image_build() { require_cmd docker; local tag; tag="$(image_tag "$@")"; log "building $tag"; run docker build -t "$tag" -f "$PODKIT_ROOT/command-pod/Dockerfile" "$PODKIT_ROOT"; }
image_push()  { require_cmd docker; local tag; tag="$(image_tag "$@")"; log "pushing $tag"; run docker push "$tag"; }

cmd_build() { image_build "$@"; local a; for a in "$@"; do [[ "$a" == "--push" ]] && image_push "$@"; done; return 0; }
cmd_push()  { image_push "$@"; }
