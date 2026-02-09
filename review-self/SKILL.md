---
name: review-self
description: >
  Review the current branch changes relative to the latest upstream/master (or upstream/main fallback).
  Optionally read a design document from /home/hongyunyan/design-doc/<filename> and review the implementation
  for correctness, simplicity, boundaries, comments, tests, performance, and alignment with the design.
metadata:
  short-description: "Review current branch vs latest upstream/master; optionally design-doc guided; Go/infra standards."
  version: 2
---

# review-self skill (current branch review; optional design doc; always refresh base)

## Activation proof (must show to confirm skill ran)
The final answer MUST begin with this exact line:
`[skill: review-self] activated`

## Input format
### A) No design doc (pure code review)
- `$review-self`

### B) With design doc (design-guided review)
- `$review-self <doc_filename> [--desc "<optional short description>"]`

Examples:
- `$review-self`
- `$review-self operator-move.md`
- `$review-self operator-move.md --desc "focus on scheduler and operator transitions"`

## Assumptions
- You have a git remote named `upstream` locally. If missing, ask the user and STOP.
- Base branch defaults to upstream/master; if not available, upstream/main.
- Default stack is Go (infra) + possible bash scripts.

## Non-negotiable standards (must enforce)
- Keep it simple; avoid over-abstraction.
- Modules single-responsibility; boundaries clear; easy to understand.
- Necessary comments for functions/structs/tricky logic; do not delete existing comments.
- Necessary unit tests covering key paths; tests should be concise and non-bloated.
- Production-grade and high-performance; minimize allocations/copies on hot paths.
- Unlimited context: read all unclear code; do not guess by names; remove all doubts before writing the review.
- Review-only: do NOT modify code.

## Design doc handling
If a doc filename is provided:
- DOC_ROOT = `/home/hongyunyan/design-doc`
- DOC_PATH = `${DOC_ROOT}/${doc_filename}`
- If DOC_PATH does not exist or is not readable:
  - Tell the user: "Design doc not found under /home/hongyunyan/design-doc: <doc_filename>"
  - Ask them to provide the correct filename.
  - STOP.

Must read the doc fully and extract goals/non-goals, architecture, data flow/invariants, perf expectations, and test expectations.

## Workflow

### 0) Repo preflight
Run:
- `git rev-parse --show-toplevel`
- `git status --porcelain`
- `git branch --show-current`
- `git remote -v`
- `git log -1 --oneline`

If `upstream` remote is missing:
- Ask user what remote is upstream (name or URL) and STOP.

### 1) Refresh the base branch to latest (required)
Goal: ensure diff base is up-to-date so the comparison is correct.

Actions:
1) Fetch latest from upstream for both candidates (best effort):
   - `git fetch --prune upstream master` (preferred)
   - if master fetch fails or ref doesn't exist, try:
     - `git fetch --prune upstream main`

2) Choose BASE:
   - If `refs/remotes/upstream/master` exists → BASE = `upstream/master`
   - Else if `refs/remotes/upstream/main` exists → BASE = `upstream/main`
   - Else ask user which upstream base branch to use and STOP.

3) Record BASE_SHA for the report:
   - `git rev-parse BASE`

Important:
- Do NOT checkout BASE.
- Only refresh remote-tracking refs (`upstream/master` or `upstream/main`).

### 2) Identify the review change set (current branch vs latest BASE)
Let:
- HEAD = current branch HEAD (`git rev-parse HEAD`)

Compute:
- Summary: `git diff --stat BASE...HEAD`
- Full diff: `git diff BASE...HEAD`
- Commit list: `git log --oneline --decorate BASE..HEAD`

If there are staged/uncommitted changes, also include:
- `git diff --stat`
- `git diff`

### 3) Build a guided reading map (before judging)
From the diff:
- Identify entry points (exported APIs, controllers/operators, main orchestrators, key handlers).
- Determine likely call chains.
- Create a recommended reading order: top-down into core logic, then helpers/data structures.

### 4) Deep reading (no guessing)
For each major changed area:
- Open definitions for unclear symbols.
- Follow call chains until behavior and invariants are fully understood.
- If there is state machine behavior:
  - enumerate states and transitions touched
  - identify edge cases (removed node/task, retries, cancellation, partial failure)

### 5) Review criteria (must cover)
1) Correctness: edge cases, errors, idempotency, races, ordering, cleanup.
2) Simplicity: remove unnecessary layers; avoid premature abstractions.
3) Boundaries: clear ownership, minimal coupling, avoid leakage across packages.
4) Comments & readability: tricky parts explained; new public items documented.
5) Tests: are key paths covered with concise unit tests?
6) Performance: allocations/copies/conversions/lock contention on hot paths; suggest bench targets if needed.

### 6) Output format (Markdown)
1) `[skill: review-self] activated`
2) Base & diff info (required)
   - BASE ref + BASE SHA (prove it was refreshed)
   - HEAD SHA
   - commit range: `BASE..HEAD`
3) What changed (high-level summary)
4) Guided reading path (where to start: files/functions + why)
5) Design alignment (only if doc provided)
   - matches / mismatches / missing / doc issues
6) Review findings (actionable)
   - by category: Correctness / Simplicity / Boundaries / Comments / Tests / Performance
   - each item:
     - **[Severity: Blocker|High|Med|Low|Nit]** Location (file:line or symbol)
     - issue → why → suggested fix direction (no code edits)
7) Risk assessment + suggested next steps

