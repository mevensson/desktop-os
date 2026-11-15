#!/usr/bin/env bash
set -euo pipefail

# Check externally relevant image contents without attempting a desktop boot.
rpm -q bash fish cosmic-session cosmic-comp cosmic-greeter cosmic-term \
    kernel-core amd-gpu-firmware mesa-dri-drivers mesa-vulkan-drivers \
    NetworkManager flatpak bootc
fish --version
if rpm -q firefox > /dev/null 2>&1; then
    printf '%s\n' 'Firefox must be delivered through Flatpak, not RPM.' >&2
    exit 1
fi

# No account is created or changed here; preserve the base login-shell default.
useradd -D | grep -qx 'SHELL=/bin/bash'
test "$(getent passwd root | cut -d: -f7)" = /bin/bash
test -n "$(ls -A /usr/lib/modules)"
