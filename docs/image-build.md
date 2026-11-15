# Minimal OS image build

## Build and inspect

Enter the locked toolchain with `nix develop path:.` (or direnv), then run:

```bash
just check
just resolve-base
just build
just verify
```

`just build` defaults to `localhost/desktop-os:dev`. The host-side resolver fetches
the Rawhide index, selects exactly one Linux amd64 manifest, and validates its
configuration's architecture and OS. It also accepts a single-manifest reference
and rejects a non-amd64 configuration. The selected digest is passed to the
Containerfile so that a later tag change cannot change the base of that build.

To select a different local output name or revisit an identified base:

```bash
just build localhost/desktop-os:experiment \
  quay.io/fedora-ostree-desktops/cosmic-atomic@sha256:50cdba040e6a02a199763b6bb4a3643cc463fb7a247bff450db258e28a9be1aa
just verify localhost/desktop-os:experiment
```

Use the shared build command: the Containerfile requires the resolved `BASE_IMAGE`
and `BASE_DIGEST` arguments. It follows the Universal Blue
[image-template](https://github.com/ublue-os/image-template) pattern of mounting
build scripts from a scratch context stage. `.containerignore` limits that
context to the Containerfile, build files, and immutable system files.

The build:

- Retains the base's Fedora COSMIC desktop, kernel, AMD firmware/graphics, and
  networking stack.
- Installs Fedora fish and its dependencies through DNF5.
- Removes RPM Firefox with autoremove disabled; fails if that transaction removes
  any package except `firefox` or `firefox-langpacks`.
- Checks required packages, executes fish, and verifies that the root shell and
  default shell for newly created accounts remain `/bin/bash`.
- Cleans DNF caches and generated runtime/countme state.
- Ships the Firefox user setup/update helpers and user service/timer; validates
  their shell syntax and systemd units without downloading Flatpaks in a layer.
- Runs `bootc container lint --fatal-warnings` before producing the final image.

No accounts are provisioned by the build. The exact base reference is stored in
`/usr/share/desktop-os/base-image` and the OCI labels
`org.opencontainers.image.base.name` and `org.opencontainers.image.base.digest`.
For example:

```bash
podman image inspect localhost/desktop-os:dev \
  --format '{{ index .Labels "org.opencontainers.image.base.digest" }}'
podman run --rm --network=none --entrypoint cat localhost/desktop-os:dev \
  /usr/share/desktop-os/base-image
```

The Nix lock pins the host tools, and the base digest pins the base image. DNF
still reads live Rawhide repositories; this is not a promise of indefinitely
reproducible historical builds. Podman may reuse build layers for unchanged
inputs. The default build resolves Rawhide again on every invocation.

## Minimal-image slice verification — 2026-11-15

This records the initial image before the Firefox helpers were added. The
follow-up image and Firefox integration evidence are in
[firefox.md](firefox.md#local-verification-evidence--2026-11-15).

Built with the checked-in Nix toolchain on a Linux x86-64 NixOS development host,
using rootless Podman 6.1.4 without `sudo` or `--privileged`.

| Item | Observed result |
| --- | --- |
| Base | `quay.io/fedora-ostree-desktops/cosmic-atomic:rawhide` |
| Base version | `46.20261115.0` |
| Multi-platform index | `sha256:7a596fb08beb7c4a069864d1aef961c866a204acb3925cd3130e159741c3b7b7` |
| Selected amd64 manifest | `sha256:50cdba040e6a02a199763b6bb4a3643cc463fb7a247bff450db258e28a9be1aa` |
| Final local image ID (not a published registry digest) | `be6efc11a261977d32ba689ac8f9f245173844d7a22414d4b246dac50b2619a8` |
| Image platform | `linux/amd64` |
| Added payload RPMs | `fish-4.6.0-2.fc45`, `ncurses-term-6.6-3.fc45` (DNF also imported Fedora RPM signing keys) |
| Removed RPMs | `firefox-160.0-1.fc46`, `firefox-langpacks-160.0-1.fc46` |
| COSMIC | Session, compositor, greeter, and terminal `1.11.0-1.fc46` retained |
| Kernel | `7.4.0-0.rc2.261111g067c5c24cef2.21.fc46.x86_64` retained |
| AMD GPU firmware | `20261019-1.fc46` retained |
| Mesa DRI and Vulkan | `26.3.0-1.fc46` retained |
| NetworkManager | `1.58.1-5.fc46` retained |
| Flatpak | `1.19.2-1.fc46` retained |
| Fish execution | `fish, version 4.6.0` |
| Root/new-account default shell | `/bin/bash` |
| bootc lint, at build and in the resulting container | 14 checks passed, 1 skipped by bootc, no warnings; no project skip flags |

`just check` passed, including ShellCheck on the build/resolution/verification
scripts. The resolver accepted the pinned amd64 manifest and rejected the
corresponding arm64 manifest. The final image's base labels and filesystem record
matched the selected amd64 reference.

The first build exposed DNF-generated `/run/dnf` and `/var/lib/dnf` state through
bootc warnings. Cleaning that state produced the warning-free final build above.

This is a successful local image-production and container-content check.
Installation, a booted COSMIC session, real AMD graphics/networking, and hardware
boot have not been exercised. The base is an unofficial Fedora-derived image,
not a Universal Blue-maintained COSMIC distribution. Firefox is installed in user
scope after boot using the [documented setup command](firefox.md), rather than
embedded in an image layer. GHCR publication and remote CI execution have not
been performed.
