#!/usr/bin/env bash
set -euo pipefail

# Hosted Ubuntu's namespace restrictions need not be relaxed to build images.
# Only container operations use sudo; Git, Nix, metadata, and credentials stay
# in the runner's context. The container CLI still comes from the locked flake.
PODMAN_BINARY=$(type -P podman)
export PODMAN_BINARY
podman() {
    if [[ "${1:-}" == build ]]; then
        shift
        # Ubuntu's stub resolver is not reachable from the build bridge. Share
        # the disposable runner's network for RUN steps, not a hardcoded DNS.
        sudo -- "$PODMAN_BINARY" build --network=host "$@"
    else
        sudo -- "$PODMAN_BINARY" "$@"
    fi
}
export -f podman
"$@"
