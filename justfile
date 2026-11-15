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

# Build locally once the OS image's Containerfile has been implemented.
build image="localhost/desktop-os:dev":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -f Containerfile ]]; then
        printf '%s\n' 'Containerfile is not implemented yet; this change establishes the build toolchain.' >&2
        exit 1
    fi
    podman build --platform linux/amd64 --pull=always --file Containerfile --tag "{{ image }}" .
