# TASK

Work on GitHub issue #{{TASK_ID}}: {{ISSUE_TITLE}}

Read it with `gh issue view {{TASK_ID}} --comments`. If it links a parent issue or PRD, read that too.

You are on branch `{{BRANCH}}`. It may already contain work from an earlier run.
If a pull request exists for it, read the review feedback and address all of it:
`gh pr view {{BRANCH}} --comments` (no output means there is no PR yet).

Work only on this issue.

# CONTEXT

Recent commits on this branch:

<recent-commits>

!`git log -n 10 --format="%h %ad %s" --date=short`

</recent-commits>

This is a Next.js project. Before you write code, read `CLAUDE.md`, `AGENTS.md` and `README.md` if they exist, then `package.json` and the files the issue touches, with their tests.

# EXECUTION

Where the change has testable behaviour, use red-green-refactor:

1. RED: write one failing test.
2. GREEN: write the code to make it pass.
3. Repeat until the issue is done, then refactor.

If the project has no test setup yet and the issue needs tests, add a minimal one (Vitest is preferred).

# FEEDBACK LOOPS

Before each commit, run every one of these `package.json` scripts that exists: `lint`, `typecheck`, `test`, `build`. Use `npm run <name>`. Fix what fails. Do not start a dev server that keeps running.

# COMMIT

Commit with a message that starts with `RALPH:` and gives: what was done, key decisions, and notes for the next iteration. Keep it short. Do not push: the factory pushes and opens the pull request.

# WHEN YOU CANNOT FINISH

If you are blocked (the issue is unclear, a secret or external service is missing, tests fail and you cannot fix them), comment on the issue with `gh issue comment {{TASK_ID}} --body "..."`: say what you did and exactly what you need. Then stop.

Do not close the issue and do not change its labels.

When the issue is done and committed, output <promise>COMPLETE</promise>.
