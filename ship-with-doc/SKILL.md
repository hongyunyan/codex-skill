---
name: ship-with-doc
description: >
  Orchestrate three existing skills as sources of truth: write-design-doc -> dev-with-doc -> review-self.
  This orchestrator must read the referenced SKILL.md files at runtime (do not inline their content),
  then execute their workflows sequentially using shared parameters (feature/date/doc filename).
metadata:
  short-description: "One-click: write design doc -> implement -> self review (reuses existing skills)."
  version: 2
---

# ship-with-doc (reusing other skills)

## Activation proof (hard requirement)
The final answer MUST begin with this exact line:
`[skill: ship-with-doc] activated`

Also write a marker file (audit proof):
- `/home/hongyunyan/design-doc/.skill_ship-with-doc_activated`
containing timestamp + doc path + base/head SHAs + which subskills were used.

## Inputs
`$ship-with-doc <feature> [--title "<doc title>"] [--desc "<optional short description>"] [--date YYYYMMDD]`

- <feature> is a slug used for filename: design-<feature>-<date>.md
- If --date omitted, use Asia/Tokyo local date in YYYYMMDD.

## Preconditions
Use ONLY after the plan is explicitly approved by the user.
If approval is unclear, STOP and ask for explicit approval.

## Subskills (sources of truth)
At runtime, you MUST open and read these files and treat them as authoritative:
- `/home/hongyunyan/.codex/skills/write-design-doc/SKILL.md`
- `/home/hongyunyan/.codex/skills/dev-with-doc/SKILL.md`
- `/home/hongyunyan/.codex/skills/review-self/SKILL.md`

Do NOT copy their workflows into this file. Always follow the latest content from those files.

## Composition rules (to avoid activation conflicts)
Because multiple skill specs are being used together:
- Do NOT attempt to satisfy “activation must be first line” requirements from subskills.
- Instead, include a section near the top:
  - `Skills used: write-design-doc, dev-with-doc, review-self`
  - and include each subskill activation token line there.
- Subskills must also write their own marker files (see updated subskill rules).

## Orchestration steps

### Step 0: preflight
- ensure repo has upstream remote; if missing, STOP and ask user
- record current branch, HEAD SHA

### Step 1: Write design doc (delegated to write-design-doc)
- Determine:
  - DOC_ROOT = `/home/hongyunyan/design-doc`
  - DOC_FILE = `design-<feature>-<date>.md`
  - DOC_PATH = `${DOC_ROOT}/${DOC_FILE}`
- Execute the workflow required by `write-design-doc` using:
  - feature = <feature>
  - title = --title (if provided)
  - date = <date>
- Ensure DOC_PATH is created (or -v2 if already exists, as per write-design-doc rules).

### Step 2: Implement from the doc (delegated to dev-with-doc)
- Call dev-with-doc workflow using doc filename ONLY (per its spec):
  - input doc filename = basename(DOC_PATH)
  - optional desc = --desc (if provided)
- Must implement module-by-module and run unit tests as required by dev-with-doc.

### Step 3: Self-review vs latest upstream (delegated to review-self)
- Call review-self workflow using doc filename (same as Step 2).
- Must refresh upstream base to latest before diff (as required by review-self).

### Step 4: write orchestrator marker
Write `/home/hongyunyan/design-doc/.skill_ship-with-doc_activated`:
- timestamp (Asia/Tokyo)
- DOC_PATH
- BASE ref + BASE_SHA (from review-self stage)
- HEAD_SHA
- commit range
- list of subskills used + their marker file paths (if present)

## Final output
1) `[skill: ship-with-doc] activated`
2) Skills used section (and subskill activation tokens)
3) Design doc path
4) Implementation summary (what changed + tests run)
5) Self-review summary (key findings + base/head SHAs)
6) Marker file path

