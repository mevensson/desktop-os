#!/usr/bin/env bash
set -euo pipefail

image=${1:-localhost/desktop-os:dev}
base=${2:-quay.io/fedora-ostree-desktops/cosmic-atomic:rawhide}
resolved=$(bash scripts/resolve-base.sh "$base")
printf 'Building %s from %s\n' "$image" "$resolved"

podman build --platform linux/amd64 --pull=always \
    --build-arg "BASE_IMAGE=${resolved}" \
    --build-arg "BASE_DIGEST=${resolved##*@}" \
    --file Containerfile --tag "$image" .
