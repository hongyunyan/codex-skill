---
name: dev-with-doc
description: >
  Implement a feature based on a design document stored under /home/hongyunyan/design-doc.
  The user provides a filename and an optional short description. The assistant must read the doc fully,
  validate feasibility against current code, then implement module-by-module with unit tests, keeping the
  system simple and high-performance (Go/infra).
metadata:
  short-description: "Design-doc driven development from /home/hongyunyan/design-doc (deep read, simple, high-perf, module-by-module + unit tests)."
  version: 2
---

# dev-with-doc skill

## Activation proof
The final answer MUST begin with this exact line:
`[skill: dev-with-doc] activated`

## Input format
Recommended:
- `<doc_filename> [--desc "<short description>"]`

Examples:
- `$dev-with-doc rfc-foo.md`
- `$dev-with-doc operator-move.md --desc "处理 maintainer move 后的不一致问题"`

Notes:
- The doc is always resolved under: `/home/hongyunyan/design-doc/`
- The user provides a filename (optionally with subdirectories under that folder).
- If the file does not exist, STOP and ask the user to provide the correct filename.

## Assumptions
- Default language stack: Go (infra project), with some bash scripts.
- You should run unit tests locally and ensure they pass.

## Non-negotiable requirements (from the user)
1) Unlimited context: read all unclear code; do not guess from names; remove all doubts before writing code.
2) Keep it simple: avoid unnecessary abstraction; keep modules single-responsibility and boundaries clear.
3) High performance (infra): pay attention to hot paths; minimize allocations/copies.
4) First validate the design against current code; if issues exist, point them out and propose improvements.
5) Implement all key parts in the design so the system works end-to-end as intended.
6) Write necessary unit tests and ensure tests pass (simple tests covering key logic).
7) Implement module-by-module: implement + test each module before moving to the next.
8) Comments:
   - Add necessary comments for new structs/functions and tricky details.
   - Do not delete existing comments.

## Workflow

### 0) Preflight (repo context)
Run:
- `git rev-parse --show-toplevel`
- `git status --porcelain`
- `git log -1 --oneline`

If the working tree is dirty, proceed carefully and keep changes contained.

### 1) Locate and read the design document (must be complete)
Given `<doc_filename>`, resolve:
- DOC_ROOT = `/home/hongyunyan/design-doc`
- DOC_PATH = `${DOC_ROOT}/${doc_filename}`

Rules:
- Do not search elsewhere by default.
- If DOC_PATH does not exist or is not readable:
  - Tell the user: "Design doc not found under /home/hongyunyan/design-doc: <doc_filename>"
  - Ask them to provide the correct filename (or move the doc there).
  - STOP (do not proceed with implementation).

Read the document fully and extract:
- Goals / non-goals
- Public API changes
- Data flow / state transitions
- Error handling and invariants
- Performance constraints / scalability assumptions
- Testing strategy or required coverage

### 2) Feasibility review (before coding)
Compare design assumptions with current code. Produce:
- Compatibility issues (existing architecture, interfaces, constraints)
- Missing pieces or ambiguous areas in the doc
- Proposed adjustments (minimal, practical) that preserve intent
- A concrete implementation plan

Do NOT start coding until you have a coherent plan.

### 3) Module breakdown (you must invent module boundaries if doc doesn't list them)
Create a module list. For each module:
- Responsibility (one sentence)
- Inputs/outputs (types/interfaces)
- Key functions and their signatures (Go)
- Important invariants
- Unit test plan (what to test)

Keep boundaries explicit and minimal.

### 4) Implementation loop (module-by-module)
For each module, do this sequence:
1) Read existing related code thoroughly (follow call chains; no guessing)
2) Implement minimal API + core logic
3) Add comments for tricky logic and new public-facing items
4) Write unit tests for key logic (simple and focused)
5) Run relevant tests and ensure they pass
6) Only then proceed to the next module

### 5) Testing policy
- Prefer targeted `go test ./path/...` while iterating; run `go test ./...` at the end.
- Mention relevant bash scripts if they exist, but keep unit tests as the core requirement unless the doc explicitly requires otherwise.

### 6) Performance policy (Go infra)
When touching hot paths:
- Avoid per-item allocations in loops
- Minimize []byte/string conversions
- Avoid unnecessary copying of large slices/maps/structs
- Prefer reusing buffers when safe
- Be careful with interface allocations/boxing
- Keep data ownership clear to avoid defensive copies

If performance impact is uncertain:
- Add a small benchmark OR explain what to benchmark and why (prefer minimal benchmarks).

### 7) Final output format
After completion, output:

1) `[skill: dev-with-doc] activated`
2) Design doc summary (goals/non-goals + key decisions)
3) Feasibility findings + any design adjustments (with rationale)
4) Implementation plan (modules + interfaces)
5) What you changed (files, key functions)
6) Tests added + how to run them
7) Performance notes (alloc/copy hotspots considered)
8) Follow-ups / TODOs (only if genuinely needed)

