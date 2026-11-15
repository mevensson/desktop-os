#!/usr/bin/env bash
set -euo pipefail

# Real registry/image transfers, with synthetic GitHub release fixtures. Nothing
# here publishes to GHCR or represents a remote production build.
source_image=${1:-localhost/desktop-os:dev}
mkdir -p .build
temporary=$(mktemp -d "$(pwd)/.build/publication-test.XXXXXX")
registry=
images=()
cleanup() {
    if [[ -n "$registry" ]]; then podman rm --force --volumes "$registry" > /dev/null; fi
    if ((${#images[@]})); then podman rmi "${images[@]}" > /dev/null; fi
    rm -rf "$temporary"
}
trap cleanup EXIT
printf '{"auths":{}}\n' > "$temporary/auth.json"
export REGISTRY_AUTH_FILE="$temporary/auth.json" REGISTRY_TLS_VERIFY=false
registry=$(podman run --detach --publish 127.0.0.1::5000 docker.io/library/registry:2)
repository="$(podman port "$registry" 5000/tcp)/desktop-os"
for _attempt in {1..30}; do
    if bash scripts/registry-image.sh "$repository:missing" > /dev/null 2>&1; then
        exit 1
    else
        status=$?
        if (( status == 3 )); then break; fi
    fi
    sleep 1
done
test "$status" = 3

export GITHUB_ACTIONS=true GITHUB_REPOSITORY=mevensson/desktop-os GITHUB_REF=refs/heads/main
export GITHUB_EVENT_NAME=push GITHUB_WORKFLOW_REF=mevensson/desktop-os/.github/workflows/build.yml@refs/heads/main
GITHUB_SHA=$(git rev-parse HEAD)
export GITHUB_SHA
podman run --rm --network=none --entrypoint cat "$source_image" \
    /usr/share/desktop-os/release.json > "$temporary/base.json"

fixture() {
    export GITHUB_RUN_ID=$1 GITHUB_RUN_NUMBER=$2 GITHUB_RUN_ATTEMPT=$3
    directory="$temporary/release-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
    mkdir -p "$directory"
    created=$(date --utc +%Y-%m-%dT%H:%M:%SZ)
    jq --arg sha "$GITHUB_SHA" --arg run "$GITHUB_RUN_ID" --arg number "$GITHUB_RUN_NUMBER" \
        --arg attempt "$GITHUB_RUN_ATTEMPT" --arg created "$created" --arg workflow "$GITHUB_WORKFLOW_REF" \
        '.release_id = ("release-" + $run + "-" + $attempt) |
         .source.revision = $sha | .source.dirty = false |
         .build = {kind: "github", created: $created,
             github: {repository: "mevensson/desktop-os", run_id: $run,
                      run_number: $number, attempt: $attempt, workflow_ref: $workflow}}' \
        "$temporary/base.json" > "$directory/release.json"
    # Containerfile expands this argument, not the fixture-generating shell.
    # shellcheck disable=SC2016
    printf '%s\n' 'ARG SOURCE_IMAGE' 'FROM ${SOURCE_IMAGE}' \
        'COPY release.json /usr/share/desktop-os/release.json' > "$directory/Containerfile"
    podman build --quiet --pull=never --build-arg "SOURCE_IMAGE=$source_image" \
        --iidfile "$directory/image-id" \
        --label "org.opencontainers.image.version=release-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}" \
        --label "org.opencontainers.image.revision=$GITHUB_SHA" \
        --label "org.opencontainers.image.created=$created" \
        --label io.github.mevensson.desktop-os.build-kind=github \
        --label "io.github.mevensson.desktop-os.run-id=$GITHUB_RUN_ID" \
        --label "io.github.mevensson.desktop-os.run-number=$GITHUB_RUN_NUMBER" \
        --label "io.github.mevensson.desktop-os.run-attempt=$GITHUB_RUN_ATTEMPT" \
        --label "io.github.mevensson.desktop-os.workflow-ref=$GITHUB_WORKFLOW_REF" \
        --file "$directory/Containerfile" "$directory" > /dev/null
    images+=("$(< "$directory/image-id")")
}
production_digest() { bash scripts/registry-image.sh "$repository:production" | jq -r .Digest; }

fixture 102 2 1
bash scripts/publish-image.sh "$directory" "$repository"
first=$(production_digest)
fixture 101 1 9
bash scripts/publish-image.sh "$directory" "$repository"
test "$(jq -r .production.decision "$directory/publication.json")" = skip-older
test "$(production_digest)" = "$first"
fixture 102 2 2
bash scripts/publish-image.sh "$directory" "$repository"
latest=$(production_digest)
test "$latest" != "$first"
if bash scripts/publish-image.sh "$directory" "$repository"; then exit 1; fi
if GITHUB_EVENT_NAME=pull_request bash scripts/publish-image.sh "$directory" "$repository"; then exit 1; fi
fixture 103 3 1
printf 'missing-image\n' > "$directory/image-id"
if bash scripts/publish-image.sh "$directory" "$repository"; then exit 1; fi
test "$(production_digest)" = "$latest"
if bash scripts/registry-image.sh 127.0.0.1:1/desktop-os:missing; then
    exit 1
else
    test "$?" = 1
fi
printf '%s\n' 'Publication protocol passed: anonymous pulls, immutable tags, older-run rejection,' \
    'newer-attempt promotion, PR rejection, failed-image retention, and fail-closed registry errors.'
