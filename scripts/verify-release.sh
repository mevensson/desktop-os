#!/usr/bin/env bash
set -euo pipefail

image=${1:-localhost/desktop-os:dev}
metadata=$(mktemp)
trap 'rm -f "$metadata"' EXIT
podman run --rm --network=none --entrypoint cat "$image" \
    /usr/share/desktop-os/release.json > "$metadata"
jq -e -f scripts/validate-release.jq "$metadata" > /dev/null

podman image inspect "$image" | jq -e --slurpfile release "$metadata" '
    $release[0] as $r | .[0] as $image | $image.Config.Labels as $labels |
    $image.Os == "linux" and $image.Architecture == "amd64" and
    $labels["org.opencontainers.image.version"] == $r.release_id and
    $labels["org.opencontainers.image.revision"] == $r.source.revision and
    $labels["org.opencontainers.image.source"] == $r.source.repository and
    $labels["org.opencontainers.image.created"] == $r.build.created and
    $labels["org.opencontainers.image.base.name"] == $r.base.reference and
    $labels["org.opencontainers.image.base.digest"] == $r.base.digest and
    $labels["io.github.mevensson.desktop-os.build-kind"] == $r.build.kind and
    $labels["io.github.mevensson.desktop-os.run-id"] == ($r.build.github.run_id // "") and
    $labels["io.github.mevensson.desktop-os.run-attempt"] == ($r.build.github.attempt // "") and
    $labels["io.github.mevensson.desktop-os.run-number"] == ($r.build.github.run_number // "") and
    $labels["io.github.mevensson.desktop-os.workflow-ref"] == ($r.build.github.workflow_ref // "")
' > /dev/null
test "$(podman run --rm --network=none --entrypoint cat "$image" \
    /usr/share/desktop-os/base-image)" = "$(jq -r .base.reference "$metadata")"
printf 'Verified release metadata: %s\n' "$(jq -r .release_id "$metadata")"
