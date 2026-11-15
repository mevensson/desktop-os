#!/usr/bin/env bash
set -euo pipefail

base=${1:-quay.io/fedora-ostree-desktops/cosmic-atomic:rawhide}
revision=$(git rev-parse HEAD)
dirty=false
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    dirty=true
fi
created=$(date --utc +%Y-%m-%dT%H:%M:%SZ)
lock_hash=$(sha256sum flake.lock)
lock_hash=${lock_hash%% *}
github=null
repository=https://github.com/mevensson/desktop-os

if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
    : "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_ID:?}"
    : "${GITHUB_RUN_ATTEMPT:?}" "${GITHUB_RUN_NUMBER:?}" "${GITHUB_WORKFLOW_REF:?}"
    if [[ "$revision" != "$GITHUB_SHA" || "$dirty" != false ]]; then
        printf '%s\n' 'GitHub release metadata requires a clean checkout of GITHUB_SHA.' >&2
        exit 1
    fi
    kind=github
    repository="https://github.com/${GITHUB_REPOSITORY}"
    release_id="release-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
    github=$(jq -n \
        --arg repository "$GITHUB_REPOSITORY" \
        --arg run_id "$GITHUB_RUN_ID" --arg attempt "$GITHUB_RUN_ATTEMPT" \
        --arg run_number "$GITHUB_RUN_NUMBER" --arg workflow_ref "$GITHUB_WORKFLOW_REF" \
        '{repository: $repository, run_id: $run_id, attempt: $attempt,
          run_number: $run_number, workflow_ref: $workflow_ref}')
else
    kind=local
    read -r uuid < /proc/sys/kernel/random/uuid
    release_id="local-${uuid}"
fi

resolved=$(bash scripts/resolve-base.sh "$base")
jq -n --arg id "$release_id" --arg created "$created" --arg kind "$kind" \
    --arg repository "$repository" --arg revision "$revision" --argjson dirty "$dirty" \
    --arg requested "$base" --arg resolved "$resolved" --arg digest "${resolved##*@}" \
    --arg lock_hash "$lock_hash" --argjson github "$github" \
    '{schema_version: 1, release_id: $id, platform: "linux/amd64",
      source: {repository: $repository, revision: $revision, dirty: $dirty},
      build: {kind: $kind, created: $created, github: $github},
      base: {requested: $requested, reference: $resolved, digest: $digest},
      inputs: {flake_lock_sha256: $lock_hash}}' |
    jq -e -f scripts/validate-release.jq
