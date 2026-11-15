#!/usr/bin/env bash
set -euo pipefail

# Exit 3 means a positively identified missing manifest/name. Authentication,
# transport, and other errors must never be interpreted as an empty channel.
reference=${1:?registry image reference required}
auth=()
if [[ -n "${REGISTRY_AUTH_FILE:-}" ]]; then auth=(--authfile "$REGISTRY_AUTH_FILE"); fi
error=$(mktemp)
trap 'rm -f "$error"' EXIT
if skopeo inspect --no-tags --tls-verify="${REGISTRY_TLS_VERIFY:-true}" \
    "${auth[@]}" "docker://${reference}" 2> "$error"; then
    exit 0
fi
if grep -Eq 'manifest unknown|name unknown|MANIFEST_UNKNOWN|NAME_UNKNOWN' "$error"; then
    exit 3
fi
cat "$error" >&2
exit 1
