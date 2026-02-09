#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  prepare_review.sh <pr_url>
  prepare_review.sh <remote_url> <branch>
Options:
  --base master|main   (default: master)
  --paths p1,p2,...    (optional; only prints a note for Codex to prioritize)
Notes:
  - Requires local git remote named 'upstream' to exist.
  - Does NOT run tests (CI covers).
EOF
}

BASE_BRANCH="master"
PATHS=""

ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE_BRANCH="$2"; shift 2 ;;
    --paths) PATHS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if [[ ${#ARGS[@]} -lt 1 ]]; then
  usage; exit 1
fi

INPUT1="${ARGS[0]}"
INPUT2="${ARGS[1]:-}"

is_pr_url() {
  [[ "$1" =~ ^https?:// ]] && [[ "$1" =~ /pull/([0-9]+) ]]
}

require_upstream() {
  if ! git remote get-url upstream >/dev/null 2>&1; then
    echo "ERROR: upstream remote not found. Please add it first:"
    echo "  git remote add upstream <url>"
    exit 1
  fi
}

# repo root
git rev-parse --show-toplevel >/dev/null
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

require_upstream

# Resolve PR -> (remote_url, branch, baseRefName)
REVIEW_REMOTE_URL=""
REVIEW_BRANCH=""
PR_BASE_REF=""

if is_pr_url "$INPUT1"; then
  PR_URL="$INPUT1"
  if command -v gh >/dev/null 2>&1; then
    # gh pr view supports URL and --json fields, including headRefName/headRepository/baseRefName :contentReference[oaicite:4]{index=4}
    JSON="$(gh pr view "$PR_URL" --json headRefName,headRepository,baseRefName)"
    # Use python for JSON parsing (portable)
    REVIEW_BRANCH="$(python3 - <<PY
import json; import sys
j=json.loads(sys.stdin.read())
print(j["headRefName"])
PY
<<<"$JSON")"
    REVIEW_REMOTE_URL="$(python3 - <<PY
import json; import sys
j=json.loads(sys.stdin.read())
repo=j["headRepository"] or {}
# Prefer sshUrl if present, else fall back to url
print(repo.get("sshUrl") or repo.get("url") or "")
PY
<<<"$JSON")"
    PR_BASE_REF="$(python3 - <<PY
import json; import sys
j=json.loads(sys.stdin.read())
print(j.get("baseRefName",""))
PY
<<<"$JSON")"
  else
    # Fallback: GitHub REST API (private PR needs GITHUB_TOKEN) :contentReference[oaicite:5]{index=5}
    if [[ "$PR_URL" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
      OWNER="${BASH_REMATCH[1]}"; REPO="${BASH_REMATCH[2]}"; NUM="${BASH_REMATCH[3]}"
    else
      echo "ERROR: Unsupported PR URL format (expected github.com/OWNER/REPO/pull/NUM)"
      exit 1
    fi

    API="https://api.github.com/repos/${OWNER}/${REPO}/pulls/${NUM}"
    AUTH_HEADER=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      AUTH_HEADER=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi

    JSON="$(curl -sSL "${AUTH_HEADER[@]}" -H "Accept: application/vnd.github+json" "$API")"
    REVIEW_BRANCH="$(python3 - <<PY
import json,sys
j=json.loads(sys.stdin.read())
print(j["head"]["ref"])
PY
<<<"$JSON")"
    REVIEW_REMOTE_URL="$(python3 - <<PY
import json,sys
j=json.loads(sys.stdin.read())
repo=j["head"]["repo"]
print(repo.get("ssh_url") or repo.get("clone_url") or "")
PY
<<<"$JSON")"
    PR_BASE_REF="$(python3 - <<PY
import json,sys
j=json.loads(sys.stdin.read())
print(j["base"]["ref"])
PY
<<<"$JSON")"
  fi

  if [[ -z "$REVIEW_REMOTE_URL" || -z "$REVIEW_BRANCH" ]]; then
    echo "ERROR: Failed to resolve PR -> (remote_url, branch)."
    echo "If this is a private PR, ensure 'gh auth login' or set GITHUB_TOKEN."
    exit 1
  fi

  # Optional sanity check: if PR base != expected, warn
  if [[ -n "$PR_BASE_REF" && "$PR_BASE_REF" != "$BASE_BRANCH" ]]; then
    echo "NOTE: PR base branch is '$PR_BASE_REF' but script is using --base '$BASE_BRANCH'."
    echo "      If your upstream default base is '$PR_BASE_REF', rerun with: --base $PR_BASE_REF"
  fi
else
  # remote + branch
  if [[ -z "$INPUT2" ]]; then usage; exit 1; fi
  REVIEW_REMOTE_URL="$INPUT1"
  REVIEW_BRANCH="$INPUT2"
fi

echo "== Fetching latest upstream/${BASE_BRANCH} =="
if git show-ref --verify --quiet "refs/remotes/upstream/${BASE_BRANCH}"; then
  :
fi
git fetch --prune upstream "${BASE_BRANCH}" || {
  if [[ "$BASE_BRANCH" == "master" ]]; then
    echo "master not found, trying main..."
    BASE_BRANCH="main"
    git fetch --prune upstream "${BASE_BRANCH}"
  else
    exit 1
  fi
}
BASE_REF="upstream/${BASE_BRANCH}"

# Prepare colleague remote
REVIEW_REMOTE_NAME="codex_review_remote"
if git remote get-url "$REVIEW_REMOTE_NAME" >/dev/null 2>&1; then
  EXISTING_URL="$(git remote get-url "$REVIEW_REMOTE_NAME")"
  if [[ "$EXISTING_URL" != "$REVIEW_REMOTE_URL" ]]; then
    echo "ERROR: remote '$REVIEW_REMOTE_NAME' exists but URL differs."
    echo "Existing: $EXISTING_URL"
    echo "Wanted:   $REVIEW_REMOTE_URL"
    exit 1
  fi
else
  git remote add "$REVIEW_REMOTE_NAME" "$REVIEW_REMOTE_URL"
fi

echo "== Fetching colleague branch =="
git fetch --prune "$REVIEW_REMOTE_NAME" "$REVIEW_BRANCH"

SAFE_BRANCH="${REVIEW_BRANCH//\//_}"
RAW_BRANCH="codex/review/${SAFE_BRANCH}"

git branch -f "$RAW_BRANCH" "$REVIEW_REMOTE_NAME/$REVIEW_BRANCH"

WORKTREE_DIR="${REPO_ROOT}/.codex/worktrees/review-${SAFE_BRANCH}"

if git worktree list --porcelain | grep -q "worktree ${WORKTREE_DIR}"; then
  git worktree remove -f "${WORKTREE_DIR}"
fi
rm -rf "${WORKTREE_DIR}"

echo "== Creating worktree and merging ${BASE_REF} into ${RAW_BRANCH} (local-only) =="
git worktree add -B "$RAW_BRANCH" "$WORKTREE_DIR" "$RAW_BRANCH"
(
  cd "$WORKTREE_DIR"
  git merge --no-edit "$BASE_REF" || {
    echo "ERROR: Merge conflict while merging ${BASE_REF} into ${RAW_BRANCH}."
    echo "Please resolve conflicts manually in: ${WORKTREE_DIR}"
    exit 2
  }
)

echo
echo "Prepared for review (CI-tested; no local tests run)."
echo "BASE: ${BASE_REF}"
echo "HEAD: ${RAW_BRANCH} (includes latest BASE via local merge)"
if [[ -n "$PATHS" ]]; then
  echo "PRIORITY PATHS: $PATHS"
fi
echo
echo "Next diffs:"
echo "  git diff --stat ${BASE_REF}...${RAW_BRANCH}"
echo "  git log --oneline --no-merges ${BASE_REF}..${RAW_BRANCH}"

