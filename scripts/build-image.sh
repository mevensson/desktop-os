#!/usr/bin/env bash
set -euo pipefail

image=${1:-localhost/desktop-os:dev}
if [[ "${2:-}" == --release ]]; then
    release=$(jq -e -f scripts/validate-release.jq "${3:?release metadata file required}")
else
    release=$(bash scripts/prepare-release.sh "${2:-quay.io/fedora-ostree-desktops/cosmic-atomic:rawhide}")
fi

# A prepared manifest must describe this checkout and its selected toolchain.
lock_hash=$(sha256sum flake.lock)
dirty=false
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then dirty=true; fi
if ! jq -e --arg revision "$(git rev-parse HEAD)" --arg lock_hash "${lock_hash%% *}" \
    --argjson dirty "$dirty" \
    '.source.revision == $revision and .source.dirty == $dirty and
     .inputs.flake_lock_sha256 == $lock_hash' <<< "$release" > /dev/null; then
    printf '%s\n' 'Prepared release does not match this checkout and flake.lock.' >&2
    exit 1
fi

release_id=$(jq -r .release_id <<< "$release")
resolved=$(jq -r .base.reference <<< "$release")
metadata_dir="$(pwd)/.build/${release_id}"
mkdir -p "$metadata_dir"
# Never silently reuse an identity, including a retried CI build attempt.
(set -o noclobber; printf '%s\n' "$release" > "$metadata_dir/release.json")
cp flake.lock "$metadata_dir/flake.lock"
printf 'Building %s as %s from %s\n' "$image" "$release_id" "$resolved"

podman build --platform linux/amd64 --pull=always --iidfile "$metadata_dir/image-id" \
    --build-context "release=${metadata_dir}" \
    --build-arg "BASE_IMAGE=${resolved}" \
    --build-arg "BASE_DIGEST=${resolved##*@}" \
    --build-arg "RELEASE_ID=${release_id}" \
    --build-arg "SOURCE_URL=$(jq -r .source.repository <<< "$release")" \
    --build-arg "SOURCE_REVISION=$(jq -r .source.revision <<< "$release")" \
    --build-arg "RELEASE_CREATED=$(jq -r .build.created <<< "$release")" \
    --build-arg "BUILD_KIND=$(jq -r .build.kind <<< "$release")" \
    --build-arg "RUN_ID=$(jq -r '.build.github.run_id // ""' <<< "$release")" \
    --build-arg "RUN_ATTEMPT=$(jq -r '.build.github.attempt // ""' <<< "$release")" \
    --build-arg "RUN_NUMBER=$(jq -r '.build.github.run_number // ""' <<< "$release")" \
    --build-arg "WORKFLOW_REF=$(jq -r '.build.github.workflow_ref // ""' <<< "$release")" \
    --file Containerfile --tag "$image" .

# Inspect the produced image ID, even if another build moves the local tag.
image_id=$(< "$metadata_dir/image-id")
bash scripts/verify-release.sh "$image_id"
jq -n --arg release_id "$release_id" --arg image "$image" --arg image_id "$image_id" \
    '{schema_version: 1, release_id: $release_id, image_reference: $image,
      local_image_id: $image_id}' > "$metadata_dir/build-result.json"
podman run --rm --network=none --entrypoint rpm "$image_id" \
    -qa --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' |
    sort > "$metadata_dir/packages.txt"
printf 'Release metadata and local build evidence: %s\n' "$metadata_dir"
