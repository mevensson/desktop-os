# Issue tracker: GitHub

Issues and specs live in GitHub Issues for `mevensson/desktop-os`.
Use the `gh` CLI for all operations.

## Conventions

- Create: `gh issue create --title "..." --body "..."`
- Read: `gh issue view <number> --json number,title,body,labels,comments`
- List: `gh issue list --state open --json number,title,body,labels`
  with appropriate label and state filters.
- Comment: `gh issue comment <number> --body "..."`
- Apply or remove labels: `gh issue edit <number> --add-label "..."`
  or `--remove-label "..."`
- Close: post the explanation with `gh issue comment`, then run
  `gh issue close <number>`. Comment separately so explanations are
  preserved even when an issue is already closed.

Infer the repository from the Git remote. Before the first issue creation
of a session, verify the target with `gh repo view --json nameWithOwner`.
It should be `mevensson/desktop-os`; confirm with the user if it differs.
Never file issues into the upstream skills repository.

## Parent issues and dependencies

Use native GitHub sub-issues and blocking dependencies where available.

With gh 2.94+:
- Create a child: `gh issue create --parent <parent> ...`
- Attach an existing child:
  `gh issue edit <parent> --add-sub-issue <child>`
- Record a blocker:
  `gh issue edit <child> --add-blocked-by <blocker>`

With older gh versions, use the GitHub API:
- Sub-issue:
  `gh api --method POST repos/mevensson/desktop-os/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>`
- Blocking dependency:
  `gh api --method POST repos/mevensson/desktop-os/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`

Obtain numeric database IDs with
`gh api repos/mevensson/desktop-os/issues/<number> --jq .id`;
these are not issue numbers or node IDs.

If native relationships are unavailable, put `Part of #<parent>` and
`Blocked by: #<number>, #<number>` at the top of the child issue body.
A ticket is unblocked when every blocker is closed.

Count open native blockers with:
`gh api repos/mevensson/desktop-os/issues/<number> --jq .issue_dependencies_summary.blocked_by`

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Skill operations

When a skill says "publish to the issue tracker", create a GitHub issue.
When a skill says "fetch the relevant ticket", read the GitHub issue.
