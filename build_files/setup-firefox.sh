#!/usr/bin/env bash
set -euo pipefail

if (( EUID == 0 )); then
    printf '%s\n' 'Run desktop-os-setup-firefox as your desktop user, without sudo.' >&2
    exit 1
fi

systemctl --user daemon-reload
# Keep retries enabled even if the first download fails (for example offline).
systemctl --user enable --now desktop-os-flatpak-update.timer
if ! systemctl --user start desktop-os-flatpak-update.service; then
    printf '%s\n' \
        'Firefox setup failed; the timer remains enabled for later retries.' \
        'Inspect: journalctl --user -u desktop-os-flatpak-update.service' \
        'Retry: systemctl --user start desktop-os-flatpak-update.service' >&2
    exit 1
fi
printf '%s\n' 'Firefox is installed and automatic user Flatpak updates are enabled.'
