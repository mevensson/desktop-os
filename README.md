# desktop-os

A shared AMD x86-64 Rawhide COSMIC OS image, planned in
[issue #1](https://github.com/mevensson/desktop-os/issues/1).

The repository provides the development/build toolchain, a minimal OS image
build, and user-scoped Firefox Flatpak setup with automatic updates. CI
publication is a subsequent step in
[issue #2](https://github.com/mevensson/desktop-os/issues/2). Local build evidence
is recorded in [docs/image-build.md](docs/image-build.md).
Each build embeds a unique release ID and source/input metadata; see the
[release metadata contract](docs/release-metadata.md).

## Firefox on the installed OS

From a terminal in your desktop session, run once as your normal user:

```bash
desktop-os-setup-firefox
```

This installs Firefox from Flathub in user scope and enables independent daily
updates for user Flatpak applications and runtimes. It is safe to repeat after a
failed download or on an already configured account. See
[docs/firefox.md](docs/firefox.md) for scheduling, diagnostics, and verification.

## Development and build tools

Use Linux x86-64 with Nix and the `nix-command` and `flakes` experimental features
enabled. The root flake supplies locked versions of Podman, Skopeo, jq, just,
ShellCheck, actionlint, a Nix formatter, Bash, Git, and coreutils.

```bash
nix develop path:.
just                  # List commands
just check            # Flake evaluation, formatting, script/workflow linting
just doctor           # Tool versions and Podman host information
just inspect-base     # Inspect the selected Rawhide base without pulling its layers
just resolve-base     # Resolve and validate its exact linux/amd64 manifest
just build            # Build localhost/desktop-os:dev
just verify           # Check the built image and run bootc lint
```

The explicit `path:.` also works while new flake files are still untracked by
Git. Once tracked, plain `nix develop` works too.

The same commands can run non-interactively on a build machine or GitHub runner:

```bash
nix develop path:. --command just check
nix develop path:. --command just doctor
nix develop path:. --command just build
nix develop path:. --command just verify
```

`just build` builds `localhost/desktop-os:dev` for `linux/amd64`. Each invocation
resolves the current Rawhide base to its amd64 manifest digest before building.
An alternative local image name and base reference can be passed as arguments;
see [the image build documentation](docs/image-build.md).
Release manifests, the selected lock file, image IDs, and RPM inventories are
saved under `.build/<release-id>/` (ignored by Git). `just prepare-release` and
`just build-release` support preparing one shared manifest for separate jobs.

`just inspect-base` defaults to
`quay.io/fedora-ostree-desktops/cosmic-atomic:rawhide`, an unofficial Fedora-derived
base. Its inspection output is useful for compatibility investigation, not proof
of successful installation or boot. For a multi-platform image, the reported
registry digest may identify the index. `just resolve-base` selects the amd64
manifest explicitly; the build records it in OCI labels and
`/usr/share/desktop-os/base-image`.

### Automatic shell loading with direnv

Install [direnv](https://direnv.net/) and
[nix-direnv](https://github.com/nix-community/nix-direnv), and enable the direnv
hook in your interactive shell. On NixOS with Home Manager, this can be configured
with `programs.direnv.enable = true;` and
`programs.direnv.nix-direnv.enable = true;`.

Then, from the repository root:

```bash
direnv allow
```

The checked-in `.envrc` loads the default flake development shell when you enter
the repository and unloads it when you leave. nix-direnv caches the environment
and watches `flake.nix` and `flake.lock` for changes. Its local `.direnv/` state is
ignored by Git. Once loaded, run `just check`, `just doctor`, or other commands
directly. Explicit `nix develop` remains available on machines without direnv.

### Host requirements

Nix supplies userspace tools, not the host configuration needed to run containers.
The host must provide working container namespaces, cgroups, storage, and an OCI
runtime. Rootless Podman normally also needs subordinate UID/GID ranges and the
host's privileged `newuidmap`/`newgidmap` helpers. On NixOS, configure Podman through
the host's `virtualisation.podman` module. Other distributions should follow their
Podman host setup instructions.

Run `just doctor` on each development/build host. A successful `podman info`
confirms initialization. The current image has also been built successfully with
rootless Podman on the development host; new hosts still need their own build
verification.
Provide enough disk space for large OS image layers and build-time temporary
files. Registry inspection and Nix package downloads need network access.

### Lock-file policy

`flake.lock` records the toolchain input. Normal development, CI, and weekly OS
builds consume that lock file without updating it. Update the toolchain
deliberately, review the lock-file diff, and rerun the checks:

```bash
nix flake update --flake path:. nixpkgs-tools
nix develop path:. --command just check
nix develop path:. --command just doctor
```

The separate `nixpkgs-tools` input leaves room for Home Manager and its own
package/input update policy in issue #4. Tools supplied here run on the build
host; Fedora RPMs in the Containerfile supply OS image packages such as
fish.

Format Nix and just files with:

```bash
nix fmt path:.
nix develop path:. --command just --fmt
```
