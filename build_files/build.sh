#!/usr/bin/env bash
set -euo pipefail

# Fedora owns the desktop/system stack and the fish executable.
dnf5 install --assumeyes fish

# Disable autoremove, then reject unexpected dependent-package removals.
# This protects all inherited packages, not just a short desktop allowlist.
if rpm -q firefox > /dev/null 2>&1; then
    rpm -qa --queryformat '%{NAME}\n' | sort -u > /tmp/packages-before
    dnf5 remove --assumeyes --no-autoremove firefox
    rpm -qa --queryformat '%{NAME}\n' | sort -u > /tmp/packages-after
    while IFS= read -r removed; do
        case "$removed" in
            firefox|firefox-langpacks) ;;
            *) printf 'Unexpected package removed with Firefox: %s\n' "$removed" >&2; exit 1 ;;
        esac
    done < <(comm -23 /tmp/packages-before /tmp/packages-after)
fi

dnf5 clean all
# DNF's countme/runtime state is build-time state, not OS payload.
rm -rf /var/lib/dnf /run/dnf

# Only immutable helpers/units are shipped; Flatpak user state is created later.
cp -a /ctx/system_files/. /
install -D -m 0755 /ctx/build_files/setup-firefox.sh /usr/bin/desktop-os-setup-firefox
install -D -m 0755 /ctx/build_files/update-flatpaks.sh /usr/libexec/desktop-os/flatpak-update
bash /ctx/build_files/verify.sh
