# Return the document on success, and fail with a diagnostic otherwise.
def matches($pattern): type == "string" and test($pattern);
def positive_integer: matches("^[1-9][0-9]*$");

. as $release
| if (
    .schema_version == 1 and
    .platform == "linux/amd64" and
    (.source.repository | matches("^https://github.com/[^/]+/[^/]+$")) and
    (.source.revision | matches("^([0-9a-f]{40}|[0-9a-f]{64})$")) and
    (.source.dirty | type == "boolean") and
    (.build.created | matches("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    (.base.requested | type == "string" and length > 0) and
    (.base.digest | matches("^sha256:[0-9a-f]{64}$")) and
    (.base.reference | matches("^[^@]+@sha256:[0-9a-f]{64}$")) and
    (.base.reference | endswith("@" + $release.base.digest)) and
    (.inputs.flake_lock_sha256 | matches("^[0-9a-f]{64}$")) and
    (if .build.kind == "github" then
        .source.dirty == false and
        (.build.github.run_id | positive_integer) and
        (.build.github.attempt | positive_integer) and
        (.build.github.run_number | positive_integer) and
        (.build.github.repository | matches("^[^/]+/[^/]+$")) and
        (.build.github.workflow_ref | matches("^[^/]+/[^/]+/\\.github/workflows/[^@]+@.+$")) and
        .source.repository == ("https://github.com/" + .build.github.repository) and
        .release_id == ("release-" + .build.github.run_id + "-" + .build.github.attempt)
     elif .build.kind == "local" then
        .build.github == null and
        (.release_id | matches("^local-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"))
     else false end)
) then . else error("invalid desktop-os release metadata (schema version 1)") end
