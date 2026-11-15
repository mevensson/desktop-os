#!/usr/bin/env bash
set -euo pipefail

if (( EUID == 0 )); then
    printf '%s\n' 'Flatpak setup and updates must run as the desktop user, not root.' >&2
    exit 1
fi

# A project-specific user remote avoids changing Fedora's system remotes or an
# existing user Flathub remote. The official repo file supplies the signing key.
flatpak remote-add --user --if-not-exists --from desktop-os-flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user --assumeyes --noninteractive --or-update \
    desktop-os-flathub org.mozilla.firefox
# Update user apps and runtimes together so Firefox's runtime stays current too.
flatpak update --user --assumeyes --noninteractive
