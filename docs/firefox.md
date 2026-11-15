# Firefox installation and independent updates

## One-time user setup

On the installed project OS, log in to the desktop and run this from a terminal
as `matte` (or another desktop user), without `sudo`:

```bash
desktop-os-setup-firefox
flatpak info --user org.mozilla.firefox
flatpak run --user org.mozilla.firefox
```

The command requires a running systemd user manager, network access to Flathub,
and space in the user's home for Firefox and its runtimes. Initial download size
can exceed 1 GB. If the application launcher does not immediately discover
Firefox after the first user Flatpak installation, log out and back in.

Setup reloads the user units, enables/starts
`desktop-os-flatpak-update.timer`, and synchronously runs its update service.
Successful completion means the install/update transaction succeeded. Failed
downloads return an error with journal/retry instructions; the timer stays
enabled. Repeating setup is safe: it reuses the remote and updates an existing
Firefox installation without uninstalling it.

## Delivery and schedule

The image supplies only these immutable files:

- `/usr/bin/desktop-os-setup-firefox`
- `/usr/libexec/desktop-os/flatpak-update`
- `/usr/lib/systemd/user/desktop-os-flatpak-update.service`
- `/usr/lib/systemd/user/desktop-os-flatpak-update.timer`

Each update service invocation:

1. Adds `desktop-os-flathub` in **user scope** if absent, using the official
   `https://dl.flathub.org/repo/flathub.flatpakrepo` definition and its GPG key.
2. Installs or updates `org.mozilla.firefox` noninteractively from that remote.
3. Updates all user Flatpak applications and runtimes noninteractively, keeping
   Firefox's runtime and related extensions current too. This also updates any
   other user Flatpaks the account has installed.

Fedora's system remotes and any existing user remote named `flathub` are left in
place. A same-named project remote is reused; setup does not rewrite custom
remote configuration. Remote, signature, download, and transaction errors fail
the service and are available in its journal. Both helpers reject root execution.

The timer runs daily, plus a startup check five minutes after the user manager
starts, with up to one hour of randomized delay. Persistent scheduling catches
up after missed calendar runs. It operates while the user manager is running;
setup does not enable lingering or make a logged-out user stay active. The
service has a one-hour timeout and retries on a later timer activation after a
failure. Manual and timer starts of the same service are serialized by systemd.

No project updater is enabled globally. The base was inspected and had Fedora's
system remote-setup service but no automatic Flatpak update timer. Enrollment
creates the timer symlink and Flatpak state in the user's mutable home after
installation, never in an OS image build layer.

OS builds, Home Manager activation, and OS rollback do not run these updates.
OS rollback does not downgrade Firefox, its Flatpak runtime, or its profile.
Firefox is ensured on every service run, so uninstalling it while this timer is
enabled causes a later run to reinstall it.

## Status, retry, and disabling

```bash
systemctl --user is-enabled desktop-os-flatpak-update.timer
systemctl --user list-timers desktop-os-flatpak-update.timer
systemctl --user status desktop-os-flatpak-update.service
journalctl --user -u desktop-os-flatpak-update.service

# Retry immediately, independently of an OS build or reboot:
systemctl --user start desktop-os-flatpak-update.service

# Stop future scheduled updates (does not cancel an already running transaction):
systemctl --user disable --now desktop-os-flatpak-update.timer
```

A successful oneshot service normally returns to `inactive (dead)`; check its
journal or `systemctl --user show desktop-os-flatpak-update.service -p Result`
for the outcome. Running the setup command again re-enables the timer.

## Installed-OS acceptance procedure

After installation in issue #3:

1. Run setup as the desktop user. Confirm `flatpak info --user
   org.mozilla.firefox` reports `Installation: user` and origin
   `desktop-os-flathub`, and launch Firefox in COSMIC.
2. Run setup again; confirm one Firefox installation and an enabled, active timer.
3. Start the update service manually and confirm its journal reports success.
   Observe a real scheduled run while logged in; check the reported next and last
   trigger times. When a newer upstream release is available, confirm the commit
   or version advances without an OS build.
4. Exercise an offline failure and a subsequent successful retry. Confirm failure
   remains diagnosable and the timer stays enabled. Verify normal security
   settings and desktop launch on the actual installed OS.

## Local verification evidence — 2026-11-15

The updated image built successfully using the locked toolchain and rootless
Podman 6.1.4. Its local image ID is
`8c58288cb465c5d2d62af62d03bfb4c4adca1e64ccecb2db21474b7c40302a4e`;
the selected base is the same amd64 manifest recorded in `image-build.md`.
`just check` and `just verify` passed, including ShellCheck, installed helper
syntax, systemd unit verification, and bootc lint with fatal warnings
(14 passed, 1 skipped by bootc, no warnings).

For integration verification, image
`fe26dc8b1b4de70777d79717f7933b42060e121ffff6b0fbcadddd59926bddc8` was
run in a disposable rootless Podman container with
`/sbin/init --unit=multi-user.target`. The final rebuild above split the two
installed-helper syntax checks into separate commands; its shipped helpers and
units are byte-identical to the integration-tested image. A fresh `matte` user
was created and its actual systemd user manager started. Lingering was enabled
only in that test container to keep the manager available to `podman exec`.

Observed behavior:

- Forcing the service's HTTPS proxy to an unreachable local port made first setup
  fail with exit status 1 and a useful Flatpak error in the user journal. The
  update timer remained `enabled` and `active`.
- Removing that test proxy and rerunning setup installed Firefox **160.0**, ref
  `app/org.mozilla.firefox/x86_64/stable`, commit
  `6e1de891c7933f796cb8ad8091dfa2d75b5e975db5602d76999351fd623b0ebd`,
  from `desktop-os-flathub` in user scope, with the Freedesktop **25.08** runtime
  and related extensions. The journal recorded GPG summary/commit verification.
- Repeating setup succeeded, retained that commit and exactly one user Firefox
  application, and left the system Flatpak application list empty.
- A runtime-only timer override shortened the test wait to two seconds and
  removed randomized delay. The actual timer triggered a new update-service
  invocation, which finished with `Result=success` and `ExecMainStatus=0`. This
  was an already-current/no-op update, not an observed newer Firefox release.
- A fresh container from the image had no `matte` home, root user Flatpak state,
  system Flatpak repository, or globally enabled project timer. Both helpers
  rejected root invocation.

The systemd container had unrelated degraded system services, and Flatpak logged
nested-container `bwrap: Can't mount proc on /proc: Operation not permitted`
warnings during application export triggers. The install/update service still
completed successfully and the app/runtime appeared in the user installation.
This verifies delivery and scheduling in a container; graphical launch,
application exports, installed-OS SELinux behavior, a real daily wait, and a
later upstream version upgrade remain for the installed-OS acceptance procedure.
No VM or hardware boot result is claimed.
