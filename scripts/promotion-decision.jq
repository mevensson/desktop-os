# Input: [candidate registry inspection, current inspection or null].
def project_label($name): .Labels["io.github.mevensson.desktop-os." + $name];
def decimal: type == "string" and test("^[1-9][0-9]*$");
def workflow: project_label("workflow-ref") | split("@")[0];
def valid:
    .Os == "linux" and .Architecture == "amd64" and
    (.Digest | test("^sha256:[0-9a-f]{64}$")) and
    project_label("build-kind") == "github" and
    (project_label("run-number") | decimal) and (project_label("run-attempt") | decimal) and
    (project_label("run-id") | decimal) and
    (.Labels["org.opencontainers.image.version"] ==
        ("release-" + project_label("run-id") + "-" + project_label("run-attempt"))) and
    (workflow | test("^[^/]+/[^/]+/\\.github/workflows/[^@]+$"));
# Exact positive-integer comparison, without floating-point conversion.
def compare_decimal($a; $b):
    if ($a|length) < ($b|length) then -1
    elif ($a|length) > ($b|length) then 1
    elif $a < $b then -1 elif $a > $b then 1 else 0 end;

.[0] as $candidate | .[1] as $current |
if ($candidate | valid | not) then error("invalid candidate ordering metadata")
elif $current == null then "promote"
elif ($current | valid | not) then error("invalid current production ordering metadata")
elif ($candidate|workflow) != ($current|workflow) or
     $candidate.Labels["org.opencontainers.image.source"] != $current.Labels["org.opencontainers.image.source"]
then error("production repository/workflow ordering namespace differs")
else compare_decimal(($candidate|project_label("run-number")); ($current|project_label("run-number"))) as $run |
    if $run < 0 then "skip-older"
    elif $run > 0 then "promote"
    elif ($candidate|project_label("run-id")) != ($current|project_label("run-id")) then
        error("same run number has conflicting run identity")
    else compare_decimal(($candidate|project_label("run-attempt")); ($current|project_label("run-attempt"))) as $attempt |
        if $attempt < 0 then "skip-older"
        elif $attempt > 0 then "promote"
        elif $candidate.Digest == $current.Digest then "unchanged"
        else error("same release identity has conflicting image digest") end
    end
end
