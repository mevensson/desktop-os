#!/usr/bin/env bash
set -euo pipefail

# Simulate GHCR read-after-write propagation at the registry client boundary.
# Actual pushes, copies, and final inspections still use the real local registry.
: "${REAL_SKOPEO:?}" "${REGISTRY_CONSISTENCY_STATE:?}"
last=${!#}
if [[ "${1:-}" == copy && "$last" == docker://*:production ]]; then
    "$REAL_SKOPEO" "$@"
    printf 'missing\n' > "$REGISTRY_CONSISTENCY_STATE"
elif [[ "${1:-}" == inspect && "$last" == docker://*:production &&
        -f "$REGISTRY_CONSISTENCY_STATE" ]]; then
    state=$(< "$REGISTRY_CONSISTENCY_STATE")
    if [[ "$state" == missing ]]; then
        printf 'stale\n' > "$REGISTRY_CONSISTENCY_STATE"
        printf '%s\n' 'reading manifest production: manifest unknown' >&2
        exit 1
    fi
    if [[ "$state" == stale || "${REGISTRY_STALE_FOREVER:-false}" == true ]]; then
        printf 'ready\n' > "$REGISTRY_CONSISTENCY_STATE"
        "$REAL_SKOPEO" "$@" | jq '.Digest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"'
    else
        exec "$REAL_SKOPEO" "$@"
    fi
else
    exec "$REAL_SKOPEO" "$@"
fi
