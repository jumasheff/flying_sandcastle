# ISSUES READY FOR WORK

<ready-issues>

!`gh issue list --state open --label "{{READY_LABEL}}" --limit 100 --json number,title,body,labels,comments,blockedBy --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body], openBlockers: [(.blockedBy.nodes? // .blockedBy // [])[]? | select(.state == "OPEN") | .number]}]'`

</ready-issues>

# ISSUES IN REVIEW (a pull request is open, not merged yet)

<in-review-issues>

!`gh issue list --state open --label "{{REVIEW_LABEL}}" --limit 100 --json number,title,labels --jq '[.[] | select([.labels[].name] | index("{{READY_LABEL}}") | not) | {number, title}]'`

</in-review-issues>

The ready list is the only source of work. Do not query GitHub for more issues.

# TASK

Build a dependency graph of the ready issues. Issue B is **blocked** if:

- `openBlockers` is not empty (GitHub issue dependencies), or the body says `Blocked by #N` / `Depends on #N` and #N is still open;
- B needs code, infrastructure, an API shape or a decision that another ready issue introduces;
- B and another ready issue will change the same files or modules, so working on them at the same time will cause merge conflicts;
- B needs code from an **in-review** issue. Its pull request is not merged yet, so that code is not on the base branch.

An issue is **unblocked** when nothing above applies.

Branch name for every issue: exactly `sandcastle/issue-{id}`.

# OUTPUT

Output your plan as JSON in `<plan>` tags. Include only unblocked issues, highest priority first:

<plan>
{"issues": [{"id": "42", "title": "Fix auth bug", "branch": "sandcastle/issue-42"}]}
</plan>

If every ready issue is blocked only by other **ready** issues (a cycle), include the one with the weakest dependencies. Never include an issue that is blocked by an in-review issue.

Always output the `<plan>` tags. With nothing to do, output `<plan>{"issues": []}</plan>`.
