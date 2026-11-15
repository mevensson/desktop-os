#!/usr/bin/env bash
set -euo pipefail

# Hosted Ubuntu's namespace restrictions need not be relaxed to build images.
# Only container operations use sudo; Git, Nix, metadata, and credentials stay
# in the runner's context. The container CLI still comes from the locked flake.
PODMAN_BINARY=$(type -P podman)
export PODMAN_BINARY
podman() { sudo -- "$PODMAN_BINARY" "$@"; }
export -f podman
"$@"
