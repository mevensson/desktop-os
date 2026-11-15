#!/usr/bin/env bash
set -euo pipefail

image=${1:-quay.io/fedora-ostree-desktops/cosmic-atomic:rawhide}
manifest=$(mktemp)
trap 'rm -f "$manifest"' EXIT
skopeo inspect --raw "docker://${image}" > "$manifest"

if jq -e 'has("manifests")' "$manifest" > /dev/null; then
    digest=$(jq -er '
        [.manifests[] | select(.platform.os == "linux" and
            .platform.architecture == "amd64" and
            ((.platform.variant // "") == ""))]
        | if length == 1 then .[0].digest
          else error("expected exactly one linux/amd64 base manifest") end
    ' "$manifest")
else
    digest=$(skopeo manifest-digest "$manifest")
fi
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]

# Remove a digest and/or tag, preserving a possible registry port.
repository=${image%@*}
if [[ "${repository##*/}" == *:* ]]; then
    repository=${repository%:*}
fi
resolved="${repository}@${digest}"
skopeo inspect --config "docker://${resolved}" |
    jq -e '.os == "linux" and .architecture == "amd64"' > /dev/null
printf '%s\n' "$resolved"
