# desktop-os

A shared AMD x86-64 Rawhide COSMIC OS image, planned in
[issue #1](https://github.com/mevensson/desktop-os/issues/1).

The repository currently provides the development/build toolchain. The OS image
Containerfile and publication workflow will follow as part of
[issue #2](https://github.com/mevensson/desktop-os/issues/2).

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
```

The explicit `path:.` also works while new flake files are still untracked by
Git. Once tracked, plain `nix develop` works too.

The same commands can run non-interactively on a build machine or GitHub runner:

```bash
nix develop path:. --command just check
nix develop path:. --command just doctor
# Once the Containerfile is implemented:
nix develop path:. --command just build
```

`just build` builds `localhost/desktop-os:dev` for `linux/amd64` and refreshes
referenced base tags. An alternative local image name can be passed as an
argument. Until a Containerfile exists, it exits with an explanatory error.

`just inspect-base` defaults to
`quay.io/fedora-ostree-desktops/cosmic-atomic:rawhide`, an unofficial Fedora-derived
base. Its inspection output is useful for compatibility investigation, not proof
of successful installation or boot. For a multi-platform image, the reported
registry digest may identify the index; production base resolution must select
and record the amd64 manifest explicitly.

### Host requirements

Nix supplies userspace tools, not the host configuration needed to run containers.
The host must provide working container namespaces, cgroups, storage, and an OCI
runtime. Rootless Podman normally also needs subordinate UID/GID ranges and the
host's privileged `newuidmap`/`newgidmap` helpers. On NixOS, configure Podman through
the host's `virtualisation.podman` module. Other distributions should follow their
Podman host setup instructions.

Run `just doctor` on each development/build host. A successful `podman info`
confirms initialization, but the eventual OS image build must still establish
whether rootless execution is sufficient or a privileged builder is needed.
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
host; Fedora RPMs in the future Containerfile supply OS image packages such as
fish.

Format Nix and just files with:

```bash
nix fmt path:.
nix develop path:. --command just --fmt
```
