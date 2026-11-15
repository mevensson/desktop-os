# Release identity and metadata contract

## Identity

An OS release is identified by **source repository plus release ID**, not by its
Git revision or a moving image tag:

- GitHub builds: `release-<GITHUB_RUN_ID>-<GITHUB_RUN_ATTEMPT>`.
- Local builds: `local-<random UUID>`, generated for every build invocation.

Weekly runs of the same commit therefore have distinct identities. A workflow
rerun has a distinct attempt and identity too. Local IDs are development
identities, not production releases. GitHub metadata preparation requires a
clean checkout whose HEAD matches `GITHUB_SHA`; local builds record whether the
working tree is dirty. A dirty build's revision/dirty marker is diagnostic, not
a complete snapshot of its uncommitted source.

Release IDs are write-once. The build refuses to overwrite an existing local
`.build/<release-id>/release.json`, including after a failed attempt. Future
publication must enforce the same rule in GHCR and retain the published digest
as the authoritative immutable image reference. Preparing metadata or setting
`build.kind=github` does not authorize production publication.

## Embedded schema version 1

Every new image contains `/usr/share/desktop-os/release.json`, validated by
`scripts/validate-release.jq`. An illustrative GitHub build document is:

```json
{
  "schema_version": 1,
  "release_id": "release-123456789-1",
  "platform": "linux/amd64",
  "source": {
    "repository": "https://github.com/mevensson/desktop-os",
    "revision": "0123456789abcdef0123456789abcdef01234567",
    "dirty": false
  },
  "build": {
    "kind": "github",
    "created": "2026-11-15T12:00:00Z",
    "github": {
      "repository": "mevensson/desktop-os",
      "run_id": "123456789",
      "attempt": "1",
      "run_number": "42",
      "workflow_ref": "mevensson/desktop-os/.github/workflows/build.yml@refs/heads/main"
    }
  },
  "base": {
    "requested": "quay.io/fedora-ostree-desktops/cosmic-atomic:rawhide",
    "reference": "quay.io/fedora-ostree-desktops/cosmic-atomic@sha256:50cdba040e6a02a199763b6bb4a3643cc463fb7a247bff450db258e28a9be1aa",
    "digest": "sha256:50cdba040e6a02a199763b6bb4a3643cc463fb7a247bff450db258e28a9be1aa"
  },
  "inputs": {
    "flake_lock_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }
}
```

`build.created` is metadata-preparation time in UTC. GitHub numeric identifiers
are decimal strings to avoid JSON number precision loss. Local builds have
`build.kind=local` and `build.github=null`. The lock hash is SHA-256 of the exact
root `flake.lock` bytes, covering the current toolchain and any future inputs
added to that file. A saved copy accompanies the local build artifacts.

The JSON is the full client-facing contract. OCI labels mirror revision, source
URL, creation time, base reference/digest, and release ID (as
`org.opencontainers.image.version`). Project labels under
`io.github.mevensson.desktop-os.` expose `build-kind`, `run-id`, `run-attempt`,
`run-number`, and `workflow-ref`; GitHub-only labels are empty for local builds.
`just verify` checks these labels against the embedded JSON and checks the legacy
`/usr/share/desktop-os/base-image` reference too. The derivative's OCI version is
its release ID, rather than the inherited upstream base version.

Consumers must reject unsupported schema versions and missing/invalid required
fields; additional fields can be added within version 1. Metadata describes
inputs and identity, not a signature or proof of production authorization. The
live Rawhide RPM repositories still preclude claiming indefinite historical
reproducibility.

## Shared preparation and build artifacts

`just build` prepares a fresh manifest, resolves the base, and builds the image.
To prepare a shared candidate before separate image/home jobs, use:

```bash
mkdir -p .build
just prepare-release > .build/candidate.json
just build-release .build/candidate.json localhost/desktop-os:candidate
just verify localhost/desktop-os:candidate
```

The builder validates a prepared manifest's source revision, dirty marker, and
lock hash against the current checkout. Clean CI source and inputs must be
selected before preparation, and kept unchanged throughout all consumers.
Local dirty builds cannot establish that their uncommitted source stayed
unchanged, so they are development-only. The pinned base configuration is
validated when metadata is prepared; Podman pulls it by digest when building.

The metadata is supplied as a separate named build context. Per-release inputs
are applied after package work so a new identity can reuse unchanged build
layers. Each build retains ignored artifacts in `.build/<release-id>/`:

| File | Meaning |
| --- | --- |
| `release.json` | Prepared manifest, identical to the embedded document |
| `flake.lock` | Exact selected lock-file bytes |
| `image-id` | Podman's ID of the produced local image |
| `build-result.json` | Release ID, requested local tag, and local image ID after metadata verification |
| `packages.txt` | Sorted final RPM inventory |

`release.json` may exist for a failed build; its existence does not mean an image
was produced or published. Verification and inventory use Podman's produced
image ID rather than the moving local tag, avoiding confusion from overlapping
local builds. A local image ID is not a registry manifest digest.

The image's own final digest cannot be embedded in the content that determines
that digest. The later publisher must add the GHCR repository and exact
published digest to a separate publication record, bound to this release ID and
manifest. It must publish successful images independently of home/ISO results.

## Production ordering requirements for the CI/publication slice

Use one production workflow's `run_number`, then `attempt`, as the ordering
tuple. Compare these as decimal integers, never as lexicographic strings. The
repository and workflow path must match before comparing run numbers; counters
from different workflows are not comparable. `run_id` provides identity, not
the ordering rule. Local builds have no production ordering tuple.

Promotion must be serialized and inspect the current production release's
ordering metadata before moving its reference. GitHub concurrency alone does
not guarantee FIFO. An old run rerun after a newer successful run still has an
older run number and must not replace it. Failed builds retain the previous
production reference. These are requirements for the next slice, not an
implemented publication mechanism.

## Association with independently built home outputs (issues #4 and #6)

The home producer can build/cache outputs without any successful OS build. It
must record its own immutable output identity, source repository/revision,
exact selected Home Manager/Nix input lock hash, and activation-package store
path. With the planned shared root flake, record the same complete
`flake.lock` hash as the release; toolchain and home input update policies remain
separate even though both appear in that file.

When available, a shared prepared release manifest lets both producers record
the same release key. A home output built without it can still be cached, then
explicitly associated later after its source and selected inputs are verified.
OS failure must not prevent caching; absent or failed home output must not
prevent OS publication.

The future public association record must bind:

- Source repository and exact OS release ID.
- The prepared release manifest and selected base digest.
- Published OS image digest.
- Exact home output identity, source revision, lock hash, and activation path.

Lookup is by the running image's embedded repository/release ID. A revision
match alone, a latest home output, or a newer workflow run is insufficient.
One home output may be explicitly associated with several releases if its
selected inputs really match; that reuse is recorded, never inferred by clients.
Missing/failed delivery retains the current home generation. Association
publication must preserve correct older records and reject conflicting
replacement. The transport/public lookup location and client activation are
implemented in the publication/integration slices, not in this change.

## Local verification evidence — 2026-11-15

Two rootless builds used the same source revision
`d80e90c24f89aa8304b879ddcc313a1f973f5e15` with `source.dirty=true` for
the in-progress implementation, the same resolved base digest, and the same lock
hash. They produced distinct release identities and local image IDs:

| Release ID | Local image ID |
| --- | --- |
| `local-6e2c3e2e-9ac6-4bf2-8c18-37c0b05c05be` | `sha256:41a6de21cf69cd63cce0bd397a00807406a23b447f874617bc6e9e4f4f9179c9` |
| `local-182b1e42-2561-47cc-adb5-1398e60713d5` | `sha256:bd7dd9017c2989d6a2c29f7b910ff4350f12a75ce4daa486e75516633d40deff` |

One build consumed a separately prepared manifest; the other used the default
prepare-and-build path. Both passed `just verify`, including JSON/OCI/base record
consistency, package/unit checks, and bootc lint with fatal warnings (14 checks
passed, 1 skipped by bootc, no warnings). The second build reused unchanged
package layers while getting its own metadata. `just check` passed.

Boundary checks rejected an unsupported schema version, reuse of an existing
release identity, a prepared manifest with a different source revision or lock
hash, and a real derived image whose OCI version label was deliberately changed
to disagree with its embedded JSON. GitHub-mode preparation rejected the dirty
checkout. Temporary mismatch-test container/image objects were removed.

These are local image/metadata checks. No actual GitHub Actions run, public
release, production promotion, home-output association, or installed-OS lookup
has been verified by this slice.
