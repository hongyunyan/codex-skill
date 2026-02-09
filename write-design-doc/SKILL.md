---
name: write-design-doc
description: >
  Write a standalone, reader-friendly design document for an already-approved plan, and save it to
  /home/hongyunyan/design-doc as design-<feature>-<yyyymmdd>.md. The doc must be objective, self-contained,
  include sufficient background, concrete details, ASCII diagrams when helpful, and code pointers when relevant.
metadata:
  short-description: "Approved-plan → standalone design doc saved under /home/hongyunyan/design-doc."
  version: 1
---

# write-design-doc skill

## Activation proof (important)
The final answer MUST begin with this exact line:
`[skill: write-design-doc] activated`

## When to use
Use this skill ONLY when the plan has already been agreed/approved by the user in the conversation.
If the plan is still in flux, do not write the doc yet. Instead, summarize open issues and ask for approval.

## Input format
Recommended:
- `$write-design-doc <feature> [--title "<doc title>"] [--date YYYYMMDD]`

Examples:
- `$write-design-doc operator-move --title "Operator Move Consistency and Scheduling"`
- `$write-design-doc ci-log-diagnose`
- `$write-design-doc foo-bar --date 20251227`

Rules:
- `<feature>` will be used in filename slug: `design-<feature>-<date>.md`.
- `<feature>` must be a safe slug: lowercase letters/digits and hyphens only.
  - If user provides something else, sanitize:
    - lowercase
    - spaces/underscores → hyphen
    - remove characters other than [a-z0-9-]
- If `--date` omitted, use local current date in YYYYMMDD.

## Output artifact requirements
- Create the file under: `/home/hongyunyan/design-doc/`
- Filename MUST be: `design-<feature>-<yyyymmdd>.md`
- The document must NOT mention the user, the chat, or "we discussed earlier".
  - Write as an objective standalone doc for readers who have not seen prior discussion.
- The doc must be concrete, detailed, and implementable.
- Must include enough background to be understandable.
- Use ASCII diagrams when they help readability.
- If the design refers to existing code, include specific code pointers:
  - file paths and relevant functions/types (e.g., `pkg/foo/bar.go: func Baz(...)`)
  - avoid vague references.

## Non-negotiable writing standards
- Clarity first: short paragraphs, explicit headings, consistent terminology.
- No hand-waving: specify data structures, invariants, failure modes, rollout steps.
- Avoid unnecessary abstraction: keep the design simple and focused.
- Performance-minded (infra): mention hot paths and allocation/copy concerns where relevant.
- Make tradeoffs explicit: why this approach vs alternatives.
- Include testing strategy (unit/integration/e2e/CI) and observability if applicable.

## Workflow

### 0) Confirm approval status
- If the user has not explicitly approved the plan, ask for approval and STOP.
- If approved, proceed.

### 1) Collect context from the conversation and repo
- Summarize the problem statement, constraints, and the chosen solution.
- Identify any repo-specific context:
  - module boundaries
  - existing APIs
  - relevant components
- For any repo/code references:
  - locate the exact files and symbols; do not guess from names.
  - if uncertain, read until fully understood.

### 2) Determine title, feature slug, and date
- `feature_slug`:
  - use user-provided `<feature>` (sanitized)
- `date`:
  - use `--date` if provided else `date +%Y%m%d`
- `doc_title`:
  - use `--title` if provided else derive from feature_slug (Title Case)

### 3) Write the document (structure)
The document MUST include these sections (adapt as needed):

1. Title
2. Status
   - e.g., "Status: Proposed (Approved)"
   - include date and owner team (generic, no personal names)
3. Background / Context
   - what the system does today
   - why this problem matters
   - relevant constraints (perf, compatibility, ops)
4. Problem Statement
   - precise definition
   - scope and assumptions
5. Goals / Non-Goals
6. Current State (as-is)
   - current architecture and key flows
   - include code pointers
7. Proposed Design (to-be)
   - overview
   - architecture diagram (ASCII)
   - components/modules (responsibilities + boundaries)
   - APIs / data structures (tables or bullet specs)
   - state transitions / invariants (ASCII state machine if relevant)
   - error handling & retries
   - concurrency model (goroutines/locks/queues) if relevant
8. Detailed Design
   - step-by-step flows
   - edge cases and failure scenarios
   - compatibility/migration considerations
9. Performance Considerations
   - hot paths
   - allocations/copies to avoid
   - complexity analysis where relevant
10. Testing Strategy
   - unit tests: what to cover
   - integration/e2e/CI: what signals confirm correctness
11. Observability / Operations (if relevant)
   - logs/metrics/tracing
   - alerts and debugging workflow
12. Rollout Plan
   - staged rollout, feature flags, backward compatibility
   - rollback plan
13. Alternatives Considered
   - why rejected
14. Open Questions / Future Work (only if truly remaining)
15. References
   - links or internal docs; no chat references

### 4) Write the file to /home/hongyunyan/design-doc
- Ensure directory exists:
  - `mkdir -p /home/hongyunyan/design-doc`
- Write the content to:
  - `/home/hongyunyan/design-doc/design-<feature>-<yyyymmdd>.md`
- If file already exists:
  - do NOT overwrite silently.
  - choose a deterministic suffix like `-v2`, `-v3` OR ask the user.
  - default behavior: create `-v2` to avoid blocking.

### 5) Final response
- Begin with `[skill: write-design-doc] activated`
- Report:
  - the exact file path created
  - a short bullet summary of the doc contents (no duplication of the whole doc)
  - any remaining assumptions or follow-ups (if any)

