---
name: review-branch
description: >
  Review a colleague's remote branch against the latest upstream base branch (defaults to upstream/master),
  after locally merging the latest upstream base into the colleague branch to avoid noisy diffs.
  Output includes: what changed, a guided reading path (where to start: files/functions), and a structured review
  focusing on correctness, simplicity, module boundaries, docs/tests coverage, and performance (Go hot paths).
metadata:
  short-description: "Remote branch review vs latest upstream/master (Go-first, CI-tested; no local tests by default)."
  version: 4
---

# review-branch skill (Go-first, upstream default, minimal input, CI-first)

## What you type (minimal input)
Preferred:
- `<review_remote_url> <review_branch>`

Optional flags (in the same message):
- `--paths p1,p2,...`     (prioritize reading/review in these paths)
- `--base master|main`    (override base branch; default is auto: master then main)
- `--no-merge-base`       (NOT recommended; skip merging base into colleague branch; default merges)
- `--run-tests`           (off by default; CI covers tests)

Examples:
- `git@github.com:colleague/their-fork.git feature/x`
- `https://github.com/colleague/their-fork.git feature/x --paths cdc/,pkg/`
- `git@github.com:colleague/their-fork.git feature/x --base main`

## Defaults and assumptions
- The repo has a remote named `upstream`. This is the default base remote.
  - If `upstream` is missing, ask the user for the upstream remote name or URL.
- Base branch auto-detection:
  - Prefer `upstream/master` if it exists or can be fetched.
  - If not, fall back to `upstream/main`.
- Language stack defaults to Go. Bash scripts may exist (e.g., under hack/, scripts/, tests/).
- **Local tests are NOT executed by default** because CI validates. The review should still evaluate whether tests are present/needed.

## Safety rules (non-destructive)
- Never modify the user's current working branch.
- Never rewrite or force-push any remote branch.
- Any created local branches MUST live under `codex/review/*`.
- Prefer using `git worktree` to isolate operations, especially if the main worktree is dirty.
- Do not run `git reset --hard` on any user branch.
- If merge conflicts occur while merging upstream base into the colleague branch, stop and ask the user whether to proceed.

## High-level goal
1) Ensure the comparison base is the **latest** upstream base (default upstream/master).
2) Fetch the colleague branch from the provided remote URL.
3) Locally merge the latest upstream base into the colleague branch (codex-owned branch/worktree only),
   so the diff is only colleague changes (not outdated upstream changes).
4) Deeply understand the change:
   - Read any code you are not sure about.
   - Do not guess intent from names.
   - Follow definitions and call chains until no unknowns remain.
5) Produce a high-quality code review report + guided reading path.

---

# Procedure

## A) Preflight: repo facts and cleanliness
Run:
- `git rev-parse --show-toplevel`
- `git status --porcelain`
- `git remote -v`
- `git branch --show-current`
- `git log -1 --oneline`

If the main worktree is dirty:
- Do not modify files in the main worktree.
- Use a codex-owned worktree for all operations.

If `upstream` remote does not exist:
- Ask the user for the upstream remote name or URL, then stop (do not guess).

## B) Fetch the latest upstream base branch
Default behavior:
- Try:
  - `git fetch --prune upstream master`
  - If that fails or `upstream/master` does not exist, try:
    - `git fetch --prune upstream main`

Set:
- BASE_REMOTE = `upstream`
- BASE_BRANCH = `master` if available else `main`
- BASE = `upstream/<BASE_BRANCH>`

If the user provided `--base <branch>`, prefer that:
- `git fetch --prune upstream <branch>`
- BASE_BRANCH = `<branch>`

If neither master nor main exist, ask user which upstream base branch to use.

## C) Fetch colleague branch from provided remote URL
Use a deterministic remote name: `codex_review_remote`.

Rules:
- If `codex_review_remote` exists and URL matches, reuse it.
- If it exists but URL differs, do not overwrite it; ask user to resolve or choose another name.
- Otherwise:
  - `git remote add codex_review_remote <review_remote_url>`

Fetch:
- `git fetch --prune codex_review_remote <review_branch>`

Create codex-owned local branch:
- RAW_BRANCH = `codex/review/<sanitized_review_branch>`
- `git branch -f RAW_BRANCH codex_review_remote/<review_branch>`

Sanitization:
- Replace `/` with `_` and strip characters that are unsafe for a local ref.

## D) Create isolated worktree and merge upstream base into colleague branch (default ON)
Unless the user passed `--no-merge-base`, perform a local-only merge of BASE into RAW_BRANCH.

Worktree path (codex-owned):
- WORKTREE_DIR = `<repo>/.codex/worktrees/review-<sanitized_review_branch>`

If WORKTREE_DIR already exists:
- Remove it via `git worktree remove -f <WORKTREE_DIR>` (codex-owned path only)
- Then remove the directory if necessary.

Create worktree:
- `git worktree add -B RAW_BRANCH <WORKTREE_DIR> RAW_BRANCH`

In the worktree:
- `cd <WORKTREE_DIR>`
- `git merge --no-edit BASE`

If merge conflicts occur:
- Stop and report:
  - which files conflict
  - a short strategy suggestion
- Ask the user whether to proceed with resolution.
- Do not auto-resolve conflicts.

After merge succeeds:
- HEAD = RAW_BRANCH (now includes latest BASE locally)

## E) Compute the review change set (post-merge, minimal noise)
Use:
- `git diff --stat BASE...HEAD`
- `git diff BASE...HEAD`
- Commit list:
  - `git log --oneline --decorate --no-merges BASE..HEAD`

Notes:
- Focus analysis on `BASE..HEAD` (the colleague's delta).
- The merge commit itself (if created) should not dominate the discussion; treat it as an update step.

If `--paths` was provided:
- Also compute path-filtered diffs for prioritization and reading order.

---

# Deep reading requirement (must follow)
The user requires:
- "You have unlimited context; read all code you are not sure about; don't guess by names; remove all doubts until you fully understand the whole picture before writing."

Therefore:
- For each changed subsystem, identify entry points, then follow call chains.
- Open definitions for all symbols that are unclear.
- Trace data flow and invariants across module boundaries.
- If concurrency/state machines are involved, enumerate transitions and failure modes.

---

# Review rubric (must cover)

## 1) Correctness
- Edge cases, error handling, retries/idempotency, partial failure.
- Concurrency: races, locks, goroutines lifecycle, channel ownership.
- State transitions/invariants (especially operator/state-machine code).

## 2) Simplicity
- Prefer straightforward code. Flag over-abstraction and indirection.
- Reduce cognitive load: fewer layers, clear naming, small functions.

## 3) Boundaries / architecture
- Single responsibility, clear ownership, explicit dependencies.
- Avoid leaking internal types across packages without need.

## 4) Docs & tests (CI-first)
- Do NOT run tests locally by default.
- Still assess:
  - whether new behavior has appropriate unit/regression tests
  - whether tests cover important edge cases
  - whether comments explain tricky logic and invariants
- If there are bash test scripts:
  - identify relevant ones (hack/, scripts/, tests/) and recommend which CI jobs or scripts likely validate the change.
- Only run local tests if user provided `--run-tests` (rare).

## 5) Performance (Go-focused)
- Identify hot paths and reduce allocations/copies where possible.
- Look for:
  - unnecessary conversions between string/[]byte
  - repeated allocations in loops
  - map/slice growth patterns
  - interface boxing / escape-to-heap risks
  - redundant memcpy / buffer copies
- When claims matter, recommend benchmark/profiling (do not run by default unless asked).

---

# Output format (Markdown)

## 1) Overview
- What changed (3–8 bullets)
- Risk level: Low / Medium / High + why
- Testing note: "Local tests not executed; CI will verify."

## 2) Guided reading path (very important)
Provide Step 1..N:
- Start location: file + function/symbol
- Why start here
- What to look for (data flow, invariants, state transitions)
Include:
- "If you only have 10 minutes, read these 3 spots"

## 3) Review findings (actionable)
Group by:
- Correctness
- Simplicity
- Boundaries
- Docs & tests
- Performance

Each finding:
- **[Severity: Blocker|High|Med|Low|Nit]** Location (file:line or symbol)
- Issue
- Why it matters
- Concrete suggestion (code-level when possible)

## 4) Questions for the author
Only if truly unresolved after deep reading.

## 5) Follow-ups
- tests to add
- small refactors
- benchmarks/profiles to consider

