---
name: ci-diagnose
description: >
  Diagnose GitHub CI failures for a PR by determining whether the failure is introduced by the PR or is a
  pre-existing/intermittent bug in the current code (excluding pure infra/environment issues), using local checkout,
  CI logs (Jenkins or Prow), failed group/case extraction, and deep code reading. No code changes are made.
  No local tests are run by default (CI is authoritative).
metadata:
  short-description: "PR → checkout → fetch CI logs (Jenkins/Prow) → find failed cases → attribute PR-caused vs pre-existing/flaky (non-infra) → deep code analysis → fix ideas."
  version: 1
---

# ci-diagnose skill

## Activation banner (for you to confirm it really ran)
Always print this as the first line of the final answer:
- `[skill: ci-diagnose] activated`

## What the user provides
Required:
- `<github_pr_url>`

Optional:
- `--job <job_name>` (can appear multiple times; if absent, analyze all failed jobs from the latest ti-chi-bot failure summary)
- `--groups g1,g2,...` (optional; if absent, analyze all failed groups/stages/cases found in logs)
- `--base master|main` (optional; default auto: master then main)
- `--no-merge-base` (optional; default merges upstream base into PR head locally to match CI-style merge testing)
- `--log-dir <path>` (optional; default `.codex/ci-logs`)

Examples:
- `$ci-diagnose https://github.com/pingcap/ticdc/pull/3769`
- `$ci-diagnose https://github.com/pingcap/ticdc/pull/3769 --job pull-cdc-mysql-integration-heavy`
- `$ci-diagnose https://github.com/pingcap/ticdc/pull/3769 --job pull-unit-test --groups pkg/cdc/...,scheduler`

## Assumptions / constraints
- A git remote named `upstream` exists locally. If missing, ASK (do not guess).
- Default language is Go; there may be bash scripts.
- Do NOT run tests locally by default (CI covers).
- Do NOT modify or push any remote branches.
- Use codex-owned branches under `codex/ci/*` and codex-owned worktrees under `.codex/worktrees/*`.

## High-level steps
1) Resolve PR head repo/branch/SHA and base branch (via `gh`).
2) Check out the PR branch into a codex-owned worktree.
3) Fetch the latest upstream base (master → main fallback).
4) By default, merge upstream/<base> into the PR branch locally (codex-owned only) unless `--no-merge-base`.
5) Find the **latest** ti-chi-bot comment that contains "The following tests failed" for this PR.
6) From that comment, extract failed jobs and their "Details" links:
   - Jenkins (do.pingcap.net)
   - Prow/Spyglass (prow.tidb.net/view/gs/...)
7) For selected jobs:
   - Download logs/artifacts with curl into a local log directory.
   - Identify failed groups/stages (if applicable) and failed cases.
8) Attribute the failure:
   - If likely introduced by the PR, pinpoint which PR changes cause the failure.
   - If not obviously related to PR changes but not a pure infra/environment issue, explain why the current code can
     fail intermittently using evidence from logs and deep code reading (e.g., race, ordering, timing, shared state).
9) Deeply read code relevant to failed cases (no guessing from names; follow call chains until fully understood).
10) Output: root cause analysis + fix ideas (no code changes).

## Log download strategy (must be robust)
### A) Jenkins detail links (do.pingcap.net/jenkins/blue/...)
- BlueOcean UI requires JS, so do NOT rely on rendering it.
- Parse job name + build number from the BlueOcean URL.
- Convert to classic build URL:
  `https://do.pingcap.net/jenkins/job/pingcap/job/ticdc/job/<jobName>/<buildNum>/`
- Fetch:
  - `consoleText` (always)
  - `api/json?tree=artifacts[fileName,relativePath]` to list artifacts
  - Download artifacts that look like logs (or match provided groups)
- Optionally try:
  - `<buildUrl>wfapi/describe` (if present) to list stages and failed nodes

If curl is blocked (auth/SSO), ASK the user to provide the log files or a downloaded artifact bundle.

### B) Prow links (prow.tidb.net/view/gs/...)
- The view page is JS-driven. Use Spyglass buildlog iframe instead:
  Build an iframe URL that references the same `gs/<bucket>/<path>` and requests `build-log.txt`.
- From the iframe HTML, extract the "Raw build-log.txt" link (storage.googleapis.com) and download it.
- Also attempt best-effort downloads of common json metadata (ignore 404):
  `started.json`, `finished.json`, `prowjob.json`, `metadata.json`

If curl is blocked or artifacts are not public, ASK the user to provide the logs.

## Failure parsing (must support both integration & unit tests)
### Integration / grouped tests
- Determine failing groups from:
  - Jenkins pipeline stage list (if wfapi available)
  - artifact filenames/paths (common group log naming)
  - log markers indicating group start/end
- Within each group log, identify failing cases by patterns like:
  - `=== RUN`, `--- FAIL`, `panic:`, `FATAL`, `Error Trace`, `timed out`, SQL errors, etc.
- Summarize each failed case with the minimal evidence lines and the most likely code entry points.

### Unit tests (Go)
- Parse go test output:
  - `--- FAIL: TestXxx`
  - `FAIL <pkg> <time>`
  - stack traces and panic sections
- Prefer mapping failing tests to exact `_test.go` definitions and the production code they cover.
- If junit xml is available in artifacts, use it as an index; otherwise parse plain logs.

## Deep reading requirement (non-negotiable)
- You have unlimited context.
- Read all code you are not sure about.
- Do not infer from names.
- Follow symbols to definitions and trace data flow and invariants until there are no unknowns.
- Only then write the diagnosis.

## Output format (Markdown)
1) Activation banner (required)
2) CI failure summary
   - PR, commit SHA, local worktree path
   - failed jobs analyzed + run links
   - logs downloaded to: <path>
3) Failed groups/stages + failed cases
   - per job → per group (if any) → per case
4) Root cause analysis
   - what happened
   - why it happened (invariants broken, race, timing, env, flaky, etc.)
   - whether it is PR-caused or pre-existing (and whether the PR only exposed it)
   - where in code (files/functions)
5) Fix ideas (no code changes)
   - minimal fix
   - safer refactor if needed
   - test coverage suggestions (but note: local tests not run)
6) Questions/unknowns (only if truly necessary) + what evidence would resolve them
