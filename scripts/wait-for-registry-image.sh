#!/usr/bin/env bash
set -euo pipefail

reference=${1:?registry reference required}
expected=${2:?expected manifest digest required}
attempts=${REGISTRY_VERIFY_ATTEMPTS:-12}
delay=${REGISTRY_VERIFY_DELAY:-10}
if [[ ! "$expected" =~ ^sha256:[0-9a-f]{64}$ ||
      ! "$attempts" =~ ^[1-9][0-9]*$ || ! "$delay" =~ ^[0-9]+$ ]]; then
    printf '%s\n' 'Invalid registry verification digest or retry settings.' >&2
    exit 2
fi

# A successful tag write may briefly read as missing or as the previous digest.
# Retry only these consistency cases; authentication/transport errors still fail.
for ((attempt = 1; attempt <= attempts; attempt++)); do
    if inspection=$(bash scripts/registry-image.sh "$reference"); then
        if jq -e --arg expected "$expected" '.Digest == $expected' <<< "$inspection" > /dev/null; then
            printf '%s\n' "$inspection"
            exit 0
        fi
        observed=$(jq -r '.Digest // "invalid digest"' <<< "$inspection")
    else
        status=$?
        if (( status != 3 )); then
            printf 'Registry verification failed for %s (status %s).\n' "$reference" "$status" >&2
            exit "$status"
        fi
        observed=missing
    fi
    printf 'Waiting for %s: expected %s, observed %s (%s/%s).\n' \
        "$reference" "$expected" "$observed" "$attempt" "$attempts" >&2
    if (( attempt < attempts )); then sleep "$delay"; fi
done
printf 'Registry verification exhausted %s attempts: %s did not resolve to %s.\n' \
    "$attempts" "$reference" "$expected" >&2
exit 1
