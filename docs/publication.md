# Image validation and GHCR publication

## Workflows and triggers

`.github/workflows/build.yml` calls the shared `build-image.yml` implementation.

| Trigger | Build | Production publication |
| --- | --- | --- |
| Push to `main` in `mevensson/desktop-os` | Yes | Yes |
| Monday at 05:17 UTC | Yes, on default branch | Yes when default branch is `main` |
| Manual dispatch on `main` | Yes | Yes |
| Push to another branch | Yes | No |
| PR targeting `main` | Yes, using the event's merge revision | No |
| Manual dispatch on another branch | Yes | No |

Every build resolves the current Rawhide amd64 base. The checked-in `flake.lock`
is consumed without implicit toolchain updates. GitHub scheduled workflows run
from the default branch, and manual dispatch requires the workflow to exist on
the default branch. GitHub may delay scheduled runs or disable schedules in
inactive repositories. Branch pushes and PR events can both validate the same
change; per-event/ref concurrency cancels superseded validation runs.

The validation caller grants only `contents: read`. The trusted main caller also
grants `packages: write`; only it runs registry login/publication. Checkout does
not persist credentials. Actions are pinned by commit. No `pull_request_target`
workflow or publication credentials are used for proposed changes.

The Ubuntu x86-64 runner installs Nix and uses the same locked toolchain and
`just` commands as development. `scripts/ci-run.sh` runs only Podman operations
through sudo, using the flake's Podman executable. Git, Nix, source/metadata
preparation, and registry credentials stay in the runner's user context. This
avoids relaxing Ubuntu's host user-namespace security settings. Local rootless
build commands remain unchanged. CI builds use the disposable runner's host
network for `RUN` steps so Ubuntu's stub DNS resolver remains reachable; content
verification containers still run with `--network=none`. The runner frees unused preinstalled software
before downloading large OS image layers.

Successful image production, package/unit/metadata checks, and bootc lint are the
release checks. The workflow has no VM, installer, or Home Manager dependency.
The reusable workflow contains the common build implementation, so validation
and production use the same checks.

## Registry configuration and first production run

Production references are:

```text
ghcr.io/mevensson/desktop-os:release-<run-id>-<attempt>
ghcr.io/mevensson/desktop-os:production
ghcr.io/mevensson/desktop-os@sha256:<published-manifest-digest>
```

Prerequisites:

1. Merge the workflow to `main` and keep Actions enabled. The main push triggers
   the first production build. Manual dispatch is also available once merged.
2. Allow the production job's `GITHUB_TOKEN` to write packages. No PAT or custom
   signing secret is required by this workflow. If a pre-existing package is not
   linked to this repository, grant the repository Actions write access in its
   package settings. The image's OCI source label links it to the repository.
3. In the GitHub package settings for `desktop-os`, ensure visibility is
   **Public**. Do not assume a public source repository makes a newly uploaded
   package public. The first upload may create a private package; if so,
   anonymous verification fails before production promotion. Make the package
   public and rerun the workflow as a new attempt, yielding a new release ID.

The publication step logs in with `GITHUB_TOKEN` using a temporary auth file,
then removes that file on exit. It is outside the repository/artifact paths.
No registry credentials are installed on target computers. Container signing
and firmware Secure Boot integration are not prerequisites for this slice.

## Publication protocol

`scripts/publish-image.sh` checks the trusted event/ref and candidate metadata
against the workflow's revision, run ID, attempt, number, and workflow reference.
It verifies the actual local image's embedded metadata and labels, then:

1. Probes the unique release tag. Existing tags are never overwritten. Only an
   explicit registry `manifest unknown`/`name unknown` response means absent;
   authentication, network, and other registry errors fail closed.
2. Pushes the successfully produced image by its **local image ID**, recording
   the digest of the resulting registry manifest.
3. Retrieves the uploaded image by digest into a temporary OCI layout with
   Skopeo's explicit `--src-no-creds` mode (no credential-store fallback).
   This downloads **all layers**, not just
   registry metadata, and checks the preserved manifest digest.
4. Reads the current production image's ordering metadata. A positively absent
   reference bootstraps the channel; invalid or incomparable metadata stops
   promotion instead of replacing it.
5. Copies the verified immutable digest to `production` only if it is newer,
   preserving the digest, then verifies the moving reference.

All production jobs share the `os-production` concurrency slot for the whole
build/publication. That serializes both immutable-tag probes and promotion.
Within the slot, `scripts/promotion-decision.jq` compares run number, then retry
attempt, as exact positive decimal integers. Repository/workflow-path namespaces
must agree. An older completed run or an old run retried later cannot move
production backward. Concurrency alone is not treated as FIFO; pending runs may
be superseded by GitHub, so not every trigger is guaranteed to run.

A failed build never reaches publication. A failed upload, anonymous retrieval,
or ordering check leaves the existing production reference unchanged. A failed
promotion copy can leave its new immutable release available while production
remains on the old complete manifest; registry tag updates do not expose a
partially uploaded manifest. If promotion succeeds but its verification request
fails, production may already point to the new complete image: inspect the
registry before retrying. A successful older build can publish its own unique
reference while being skipped for production promotion.

No other workflow or manual writer should update these tags outside this
protocol. Write-once tags are a publishing convention enforced by the script,
not a registry permission that prevents another package writer from altering a
tag. Use digest references for authoritative immutable consumption.

## Evidence and public pull verification

Each run retains a 30-day `os-evidence-<run-id>-<attempt>` Actions artifact with
the prepared release manifest, selected lock file, local build result and image
ID, RPM inventory, and (after successful publication) `publication.json`.
The publication receipt binds the full release manifest to the GHCR digest,
anonymous-pull time, and promotion decision. These diagnostic Actions artifacts
are not a public client lookup endpoint; anonymously retrievable image labels
and embedded `release.json` carry the release contract.

To independently verify a published digest from a machine with no GHCR login:

```bash
nix develop path:.
temporary=$(mktemp -d)
# Substitute the digest recorded in publication.json:
skopeo copy --src-no-creds --preserve-digests \
  docker://ghcr.io/mevensson/desktop-os@sha256:YOUR_DIGEST \
  "oci:$temporary/image:verified"
skopeo inspect "oci:$temporary/image:verified"
rm -rf "$temporary"
```

Build/local verification commands remain documented in `image-build.md`.

## Local publication-protocol verification — 2026-11-15

`just check` passed, including actionlint for both workflows and ShellCheck for
the scripts. A real disposable Distribution registry was started on a random
loopback port, using rootless Podman. `just test-publication
localhost/desktop-os:metadata-a` created synthetic GitHub-labelled fixtures from
the previously verified OS image and exercised actual pushes, anonymous full
image retrievals, and moving-tag copies:

- Run 2, attempt 1 bootstrapped production.
- Run 1, attempt 9 published its own tag but did not replace run 2.
- Run 2, attempt 2 advanced production.
- Reusing an immutable tag was rejected.
- A PR event was rejected before publication.
- A missing/failed local image left production unchanged.
- A registry connection failure returned an error rather than being treated as
  an absent reference.

The registry, fixture images, and temporary credential/pull files were removed.
This is protocol verification with synthetic workflow identities, not a real
GHCR production release.

Repository inspection confirmed Actions is enabled and the default token policy
is read-only (the trusted job explicitly requests package write access). The
local GitHub CLI login has repository/workflow scopes but no package scopes.
Production GHCR publication and public retrieval require the main-branch
workflow and public package setup above; they are not claimed as verified by
these local tests. Installation/hardware validation remains in issue #3.

The initial remote [push validation run](https://github.com/mevensson/desktop-os/actions/runs/43714490469)
passed Nix setup, actionlint/ShellCheck, and rootful builder initialization, then
failed during DNF repository refresh because the build bridge could not reach
the runner's DNS resolver. The CI wrapper now uses host networking for build
steps. That failed run did not publish any image; both production jobs were
correctly skipped for branch/PR events.
