#!/usr/bin/env bash
set -euo pipefail

metadata_dir=${1:?build metadata directory required}
repository=${2:-ghcr.io/mevensson/desktop-os}
# The workflow grants write permission only to this trusted event/ref combination.
if [[ "${GITHUB_ACTIONS:-}" != true || "${GITHUB_REPOSITORY:-}" != mevensson/desktop-os ||
      "${GITHUB_REF:-}" != refs/heads/main ]]; then
    printf '%s\n' 'Production publication requires a trusted main-branch workflow.' >&2
    exit 1
fi
case "${GITHUB_EVENT_NAME:-}" in
    push|schedule|workflow_dispatch) ;;
    *) printf '%s\n' 'This event cannot publish production images.' >&2; exit 1 ;;
esac

release=$(jq -e -f scripts/validate-release.jq "$metadata_dir/release.json")
jq -e --arg sha "${GITHUB_SHA:?}" --arg run "${GITHUB_RUN_ID:?}" \
    --arg attempt "${GITHUB_RUN_ATTEMPT:?}" --arg number "${GITHUB_RUN_NUMBER:?}" \
    --arg workflow "${GITHUB_WORKFLOW_REF:?}" \
    '.build.kind == "github" and .source.dirty == false and
     .source.repository == "https://github.com/mevensson/desktop-os" and
     .source.revision == $sha and .build.github.run_id == $run and
     .build.github.attempt == $attempt and .build.github.run_number == $number and
     .build.github.workflow_ref == $workflow' <<< "$release" > /dev/null
release_id=$(jq -r .release_id <<< "$release")
image_id=$(< "$metadata_dir/image-id")
bash scripts/verify-release.sh "$image_id"
embedded=$(podman run --rm --network=none --entrypoint cat "$image_id" /usr/share/desktop-os/release.json)
test "$(jq -cS . <<< "$embedded")" = "$(jq -cS . <<< "$release")"

auth=()
if [[ -n "${REGISTRY_AUTH_FILE:-}" ]]; then auth=(--authfile "$REGISTRY_AUTH_FILE"); fi
tls=${REGISTRY_TLS_VERIFY:-true}
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
if bash scripts/registry-image.sh "${repository}:${release_id}" > "$temporary/existing.json"; then
    printf 'Refusing to overwrite immutable reference %s:%s\n' "$repository" "$release_id" >&2
    exit 1
else
    status=$?
    if (( status != 3 )); then exit "$status"; fi
fi

# This is the only immutable-tag write. Any failure leaves production untouched.
podman push --quiet --tls-verify="$tls" "${auth[@]}" --digestfile "$temporary/digest" \
    "$image_id" "docker://${repository}:${release_id}"
digest=$(< "$temporary/digest")
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]
bash scripts/registry-image.sh "${repository}@${digest}" > "$temporary/candidate.json"
jq -e --arg id "$release_id" '.Labels["org.opencontainers.image.version"] == $id' \
    "$temporary/candidate.json" > /dev/null

# Retrieve all layers in explicit anonymous mode before promotion, without any
# fallback to the user's Docker/Podman credential stores.
# GHCR packages must be public; a private first upload stops here with a useful
# registry error and can be made public in package settings before a new attempt.
if ! skopeo copy --quiet --src-tls-verify="$tls" --src-no-creds \
    --preserve-digests "docker://${repository}@${digest}" "oci:${temporary}/pull:verified"; then
    printf '%s\n' 'Anonymous retrieval failed; confirm the GHCR package is Public and reachable.' \
        'The immutable upload may exist, but production has not been changed.' >&2
    exit 1
fi
skopeo inspect "oci:${temporary}/pull:verified" | \
    jq -e --arg digest "$digest" '.Digest == $digest' > /dev/null
verified_at=$(date --utc +%Y-%m-%dT%H:%M:%SZ)

# The caller must hold the os-production concurrency slot through this section.
if bash scripts/registry-image.sh "${repository}:production" > "$temporary/current.json"; then
    :
else
    status=$?
    if (( status != 3 )); then exit "$status"; fi
    printf 'null\n' > "$temporary/current.json"
fi
decision=$(jq -ers -f scripts/promotion-decision.jq "$temporary/candidate.json" "$temporary/current.json")
if [[ "$decision" == promote ]]; then
    skopeo copy --quiet --src-tls-verify="$tls" --dest-tls-verify="$tls" "${auth[@]}" \
        --preserve-digests "docker://${repository}@${digest}" "docker://${repository}:production"
    bash scripts/registry-image.sh "${repository}:production" | \
        jq -e --arg digest "$digest" '.Digest == $digest' > /dev/null
fi
jq -n --argjson release "$release" --arg repository "$repository" --arg digest "$digest" \
    --arg verified_at "$verified_at" --arg decision "$decision" \
    '{schema_version: 1, release: $release,
      image: {repository: $repository, digest: $digest,
              immutable_reference: ($repository + ":" + $release.release_id)},
      anonymous_pull_verified_at: $verified_at,
      production: {reference: ($repository + ":production"), decision: $decision}}' \
    > "$metadata_dir/publication.json"
printf 'Published %s@%s; production decision: %s\n' "$repository" "$digest" "$decision"
