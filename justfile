set shell := ["bash", "-euo", "pipefail", "-c"]

base_image := "quay.io/fedora-ostree-desktops/cosmic-atomic:rawhide"

# List the available commands.
default:
    @just --list

# Validate the flake and formatting; lint scripts/workflows when present.
check:
    nix flake check path:.
    just --fmt --check
    nixfmt --check flake.nix
    just _lint

[private]
_lint:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s globstar nullglob
    scripts=(build_files/**/*.sh scripts/**/*.sh)
    workflows=(.github/workflows/*.yml .github/workflows/*.yaml)
    if ((${#scripts[@]})); then shellcheck "${scripts[@]}"; fi
    if ((${#workflows[@]})); then actionlint "${workflows[@]}"; fi

# Show tool versions and verify that Podman can initialize on this host.
doctor:
    nix --version
    podman --version
    skopeo --version
    jq --version
    just --version
    shellcheck --version
    actionlint --version
    podman info

# Inspect the current Rawhide base's amd64 configuration and registry digest.
inspect-base image=base_image:
    skopeo inspect --no-tags --override-os linux --override-arch amd64 "docker://{{ image }}"

# Resolve and validate the actual linux/amd64 manifest, not the image index.
resolve-base image=base_image:
    bash scripts/resolve-base.sh "{{ image }}"

# Build from a freshly resolved Rawhide base or an explicitly supplied digest.
build image="localhost/desktop-os:dev" base=base_image:
    bash scripts/build-image.sh "{{ image }}" "{{ base }}"

# Prepare a shared release manifest before independent image/home builds.
prepare-release base=base_image:
    bash scripts/prepare-release.sh "{{ base }}"

# Build using a previously prepared manifest (the source checkout must match).
build-release metadata image="localhost/desktop-os:dev":
    bash scripts/build-image.sh "{{ image }}" --release "{{ metadata }}"

# Check the built image's packages/default shell and rerun normal bootc linting.
verify image="localhost/desktop-os:dev":
    bash scripts/verify-release.sh "{{ image }}"
    podman run --rm --interactive --network=none --entrypoint /bin/bash "{{ image }}" < build_files/verify.sh
    podman run --rm --network=none --entrypoint bootc "{{ image }}" container lint --fatal-warnings
