// Flying Sandcastle — GitHub issues in, pull requests out.
//
// Based on Sandcastle's `parallel-planner-with-review` template, with the
// final "merge into the current branch" phase replaced by "push each branch
// and open a pull request". A human merges the PRs.
//
// One run of this file:
//   1. Plan:    a planner agent reads issues labelled READY_LABEL and picks
//               the ones that can be worked on in parallel right now.
//   2. Execute: each picked issue gets its own Docker sandbox + git worktree
//               on branch `sandcastle/issue-<id>`. An implementer agent works
//               on it, then a reviewer agent polishes it.
//   3. Publish: on the host (no agent, no tokens spent), each branch with new
//               commits is pushed and a PR is opened with "Closes #<id>". The
//               issue moves from READY_LABEL to REVIEW_LABEL.
//
// It is started by scripts/run.sh (systemd timer), with the project clone as
// the working directory. Configuration comes from environment variables, see
// factory.env.example.

import { execFile } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import * as sandcastle from "@ai-hero/sandcastle";
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";
import { z } from "zod";

const exec = promisify(execFile);
const here = dirname(fileURLToPath(import.meta.url));
const prompt = (name: string) => join(here, name);

// ---------------------------------------------------------------------------
// Configuration (see factory.env.example)
// ---------------------------------------------------------------------------

const env = (key: string, fallback: string) => process.env[key] || fallback;

const BASE_BRANCH = env("BASE_BRANCH", "main");
const READY_LABEL = env("READY_LABEL", "Sandcastle");
const REVIEW_LABEL = env("REVIEW_LABEL", "sandcastle:in-review");
const HUMAN_LABEL = env("HUMAN_LABEL", "sandcastle:needs-human");
const PLANNER_MODEL = env("PLANNER_MODEL", "opus");
const IMPLEMENTER_MODEL = env("IMPLEMENTER_MODEL", "sonnet");
const REVIEWER_MODEL = env("REVIEWER_MODEL", "sonnet");
const MAX_PARALLEL = Number(env("MAX_PARALLEL", "2"));
const IMPLEMENTER_MAX_ITERATIONS = Number(env("IMPLEMENTER_MAX_ITERATIONS", "30"));
const IMAGE_NAME = env("IMAGE_NAME", "sandcastle:factory");

const sandbox = () => docker({ imageName: IMAGE_NAME });

// Fresh dependencies inside every sandbox. Nothing from the host's
// node_modules is copied in, so the host never runs the project's install
// scripts.
const hooks = {
  sandbox: {
    onSandboxReady: [
      {
        command:
          "if [ -f package-lock.json ]; then npm ci; elif [ -f package.json ]; then npm install; fi",
      },
    ],
  },
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const run = async (cmd: string, args: string[]): Promise<string> => {
  const { stdout } = await exec(cmd, args, { maxBuffer: 16 * 1024 * 1024 });
  return stdout.trim();
};

const tryRun = async (cmd: string, args: string[]): Promise<string | null> => {
  try {
    return await run(cmd, args);
  } catch {
    return null;
  }
};

/** Commits on `branch` that BASE_BRANCH doesn't have. */
const commitsAhead = async (branch: string): Promise<number> => {
  const out = await tryRun("git", ["rev-list", "--count", `${BASE_BRANCH}..${branch}`]);
  return out === null ? 0 : Number(out);
};

/**
 * If a PR branch already exists on GitHub (the issue was sent back for more
 * work, or a human pushed fixes to it), continue from it instead of from a
 * possibly stale local copy.
 */
const syncBranchFromRemote = async (branch: string): Promise<void> => {
  const remote = await tryRun("git", ["rev-parse", "--verify", "--quiet", `refs/remotes/origin/${branch}`]);
  if (remote) {
    await run("git", ["branch", "-f", branch, `origin/${branch}`]);
  }
};

const issueComment = (id: string, body: string) =>
  tryRun("gh", ["issue", "comment", id, "--body", body]);

/** Give the issue exactly one of our three state labels. */
const setState = async (id: string, label: string): Promise<void> => {
  await run("gh", ["issue", "edit", id, "--add-label", label]);
  // One call per label: removing a label the issue doesn't have may fail,
  // and that must not stop the others from being removed.
  for (const other of [READY_LABEL, REVIEW_LABEL, HUMAN_LABEL]) {
    if (other !== label) await tryRun("gh", ["issue", "edit", id, "--remove-label", other]);
  }
};

/** Push the branch and open (or reuse) its PR. Returns the PR URL. */
const publish = async (issue: { id: string; title: string; branch: string }): Promise<string> => {
  await run("git", ["push", "--set-upstream", "origin", issue.branch]);

  const existing = await run("gh", [
    "pr", "list", "--head", issue.branch, "--state", "open", "--json", "url", "--jq", ".[0].url // empty",
  ]);
  if (existing) return existing;

  const log = await run("git", ["log", "--format=- %s", `${BASE_BRANCH}..${issue.branch}`]);
  const body = [
    `Closes #${issue.id}`,
    "",
    "Implemented and reviewed by Sandcastle agents.",
    "",
    "## Commits",
    log,
    "",
    `To request changes: comment on this PR, then put the \`${READY_LABEL}\` label back on #${issue.id}.`,
  ].join("\n");

  return run("gh", [
    "pr", "create", "--base", BASE_BRANCH, "--head", issue.branch,
    "--title", `#${issue.id}: ${issue.title}`, "--body", body,
  ]);
};

// ---------------------------------------------------------------------------
// Phase 1: Plan
// ---------------------------------------------------------------------------

const planSchema = z.object({
  issues: z.array(z.object({ id: z.string(), title: z.string(), branch: z.string() })),
});

const plan = await sandcastle.run({
  hooks,
  sandbox: sandbox(),
  name: "planner",
  maxIterations: 1,
  agent: sandcastle.claudeCode(PLANNER_MODEL),
  promptFile: prompt("plan-prompt.md"),
  promptArgs: { READY_LABEL, REVIEW_LABEL },
  output: sandcastle.Output.object({ tag: "plan", schema: planSchema }),
});

// Never trust the agent with branch names: they are used in git commands.
const planned: z.infer<typeof planSchema> = plan.output;
const issues = planned.issues
  .filter((i) => /^\d+$/.test(i.id))
  .map((i) => ({ ...i, branch: `sandcastle/issue-${i.id}` }))
  .slice(0, MAX_PARALLEL);

if (issues.length === 0) {
  console.log("No unblocked issues. Nothing to do.");
  process.exit(0);
}

console.log(`Plan: ${issues.length} issue(s) in parallel (max ${MAX_PARALLEL}):`);
for (const issue of issues) console.log(`  #${issue.id}: ${issue.title} → ${issue.branch}`);

// ---------------------------------------------------------------------------
// Phase 2: Execute + Review (in parallel, one sandbox per issue)
// ---------------------------------------------------------------------------

const settled = await Promise.allSettled(
  issues.map(async (issue) => {
    await syncBranchFromRemote(issue.branch);

    const box = await sandcastle.createSandbox({
      branch: issue.branch,
      sandbox: sandbox(),
      hooks,
    });

    try {
      await box.run({
        name: `implement-#${issue.id}`,
        maxIterations: IMPLEMENTER_MAX_ITERATIONS,
        agent: sandcastle.claudeCode(IMPLEMENTER_MODEL),
        promptFile: prompt("implement-prompt.md"),
        promptArgs: { TASK_ID: issue.id, ISSUE_TITLE: issue.title, BRANCH: issue.branch },
      });

      if ((await commitsAhead(issue.branch)) > 0) {
        await box.run({
          name: `review-#${issue.id}`,
          maxIterations: 1,
          agent: sandcastle.claudeCode(REVIEWER_MODEL),
          promptFile: prompt("review-prompt.md"),
          promptArgs: { BRANCH: issue.branch },
        });
      }
    } finally {
      await box.close();
    }
  }),
);

// ---------------------------------------------------------------------------
// Phase 3: Publish (host only, no agent)
// ---------------------------------------------------------------------------

let failures = 0;

for (const [i, issue] of issues.entries()) {
  const outcome = settled[i];

  if (outcome?.status === "rejected") {
    // Crash, timeout, usage limit... Leave the label alone so the next run retries.
    failures++;
    console.error(`  ✗ #${issue.id} failed: ${outcome.reason}`);
    continue;
  }

  if ((await commitsAhead(issue.branch)) === 0) {
    // The agent finished without committing anything: it is stuck. Stop
    // retrying (that only burns usage) and hand it to a human.
    console.warn(`  ? #${issue.id}: no commits, marking ${HUMAN_LABEL}`);
    await setState(issue.id, HUMAN_LABEL).catch((e) => console.error(`    relabel failed: ${e}`));
    await issueComment(
      issue.id,
      `Sandcastle could not finish this issue (no commits). See the agent's comments above. ` +
        `Clarify the issue, then put the \`${READY_LABEL}\` label back.`,
    );
    continue;
  }

  try {
    const url = await publish(issue);
    await setState(issue.id, REVIEW_LABEL);
    await issueComment(issue.id, `Pull request ready for review: ${url}`);
    console.log(`  ✓ #${issue.id} → ${url}`);
  } catch (error) {
    failures++;
    console.error(`  ✗ #${issue.id}: publishing failed: ${error}`);
  }
}

console.log("\nDone.");
process.exit(failures > 0 ? 1 : 0);
