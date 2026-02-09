#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  prepare_ci_diagnose.sh <pr_url> [--job <job>]... [--groups g1,g2,...] [--base master|main] [--no-merge-base] [--log-dir <dir>]

Notes:
  - Requires: gh, curl, python3
  - Requires git remote named 'upstream'
  - Downloads logs/artifacts to <log-dir>/pr-<num>/<job>/...
EOF
}

PR_URL=""
BASE_OVERRIDE=""
NO_MERGE_BASE="0"
LOG_DIR=".codex/ci-logs"
GROUPS=""
JOBS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --job) JOBS+=("$2"); shift 2 ;;
    --groups) GROUPS="$2"; shift 2 ;;
    --base) BASE_OVERRIDE="$2"; shift 2 ;;
    --no-merge-base) NO_MERGE_BASE="1"; shift 1 ;;
    --log-dir) LOG_DIR="$2"; shift 2 ;;
    *)
      if [[ -z "$PR_URL" ]]; then PR_URL="$1"; shift 1
      else echo "Unknown arg: $1"; usage; exit 1; fi
      ;;
  esac
done

if [[ -z "$PR_URL" ]]; then usage; exit 1; fi

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1"; exit 1; }; }
need_cmd gh
need_cmd curl
need_cmd python3

git rev-parse --show-toplevel >/dev/null
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "ERROR: git remote 'upstream' not found. Please add it first."
  exit 1
fi

# --- Resolve PR info
PR_JSON="$(gh pr view "$PR_URL" --json number,headRefName,headRepository,headSha,baseRefName,url)"
PR_NUM="$(python3 - <<PY
import json,sys; j=json.loads(sys.stdin.read()); print(j["number"])
PY
<<<"$PR_JSON")"
HEAD_REF="$(python3 - <<PY
import json,sys; j=json.loads(sys.stdin.read()); print(j["headRefName"])
PY
<<<"$PR_JSON")"
HEAD_SHA="$(python3 - <<PY
import json,sys; j=json.loads(sys.stdin.read()); print(j["headSha"])
PY
<<<"$PR_JSON")"
BASE_REF="$(python3 - <<PY
import json,sys; j=json.loads(sys.stdin.read()); print(j["baseRefName"])
PY
<<<"$PR_JSON")"
HEAD_REPO_SSH="$(python3 - <<PY
import json,sys; j=json.loads(sys.stdin.read())
repo=j.get("headRepository") or {}
print(repo.get("sshUrl") or repo.get("url") or "")
PY
<<<"$PR_JSON")"

if [[ -z "$HEAD_REPO_SSH" ]]; then
  echo "ERROR: cannot resolve headRepository.sshUrl/url from PR."
  exit 1
fi

# --- Determine base branch (prefer override, else master then main, else PR base)
BASE_BRANCH=""
if [[ -n "$BASE_OVERRIDE" ]]; then
  BASE_BRANCH="$BASE_OVERRIDE"
else
  # Try upstream/master then upstream/main
  if git fetch --prune upstream master >/dev/null 2>&1; then
    BASE_BRANCH="master"
  elif git fetch --prune upstream main >/dev/null 2>&1; then
    BASE_BRANCH="main"
  else
    # Fall back to PR baseRefName
    git fetch --prune upstream "$BASE_REF" >/dev/null 2>&1 || true
    BASE_BRANCH="$BASE_REF"
  fi
fi

echo "PR #$PR_NUM"
echo "HEAD: $HEAD_REF ($HEAD_SHA)"
echo "BASE: upstream/$BASE_BRANCH"
echo

# --- Create codex-owned remote for PR head
PR_REMOTE="codex_pr_remote"
if git remote get-url "$PR_REMOTE" >/dev/null 2>&1; then
  EXISTING="$(git remote get-url "$PR_REMOTE")"
  if [[ "$EXISTING" != "$HEAD_REPO_SSH" ]]; then
    echo "ERROR: remote '$PR_REMOTE' exists but URL differs."
    echo "Existing: $EXISTING"
    echo "Wanted:   $HEAD_REPO_SSH"
    exit 1
  fi
else
  git remote add "$PR_REMOTE" "$HEAD_REPO_SSH"
fi

echo "== Fetching PR head branch =="
git fetch --prune "$PR_REMOTE" "$HEAD_REF"

SAFE_REF="${HEAD_REF//\//_}"
LOCAL_BRANCH="codex/ci/pr-${PR_NUM}-${SAFE_REF}"
git branch -f "$LOCAL_BRANCH" "$PR_REMOTE/$HEAD_REF"

WORKTREE_DIR="${REPO_ROOT}/.codex/worktrees/ci-pr-${PR_NUM}-${SAFE_REF}"
if git worktree list --porcelain | grep -q "worktree ${WORKTREE_DIR}"; then
  git worktree remove -f "$WORKTREE_DIR" || true
fi
rm -rf "$WORKTREE_DIR" || true

echo "== Creating worktree: $WORKTREE_DIR =="
git worktree add -B "$LOCAL_BRANCH" "$WORKTREE_DIR" "$LOCAL_BRANCH"

if [[ "$NO_MERGE_BASE" == "0" ]]; then
  echo "== Merging upstream/$BASE_BRANCH into PR branch (local-only) =="
  ( cd "$WORKTREE_DIR" && git fetch --prune upstream "$BASE_BRANCH" && git merge --no-edit "upstream/$BASE_BRANCH" ) || {
    echo "ERROR: merge conflict while merging upstream/$BASE_BRANCH. Resolve manually in:"
    echo "  $WORKTREE_DIR"
    exit 2
  }
fi

# --- Find latest ti-chi-bot failure summary comment and extract failed jobs + links
echo
echo "== Fetching PR comments to locate latest ti-chi-bot failure summary =="
OWNER_REPO="$(python3 - <<PY
import json,sys; j=json.loads(sys.stdin.read())
# PR url is enough, but gh doesn't expose owner/repo in pr view json reliably across versions.
# We'll parse from PR_URL:
import re
m=re.search(r'github\\.com/([^/]+)/([^/]+)/pull/\\d+', j["url"])
print(m.group(1)+"/"+m.group(2))
PY
<<<"$PR_JSON")"

COMMENTS_JSON="$(gh api "repos/${OWNER_REPO}/issues/${PR_NUM}/comments" --paginate)"
FAIL_COMMENT="$(python3 - <<PY
import json,sys,re,datetime
comments=json.loads(sys.stdin.read())
target=[]
for c in comments:
  u=(c.get("user") or {}).get("login","")
  body=c.get("body","") or ""
  if u=="ti-chi-bot" and "The following tests failed" in body:
    target.append((c.get("created_at",""), body))
target.sort(key=lambda x: x[0])
print(target[-1][1] if target else "")
PY
<<<"$COMMENTS_JSON")"

if [[ -z "$FAIL_COMMENT" ]]; then
  echo "ERROR: cannot find a ti-chi-bot comment containing 'The following tests failed'."
  echo "You tell me the failing job link(s), or re-run after the bot posts results."
  exit 3
fi

# Parse rows: "<testname> <commit> link"
# We'll extract pairs of (testname, url) for both prow.tidb.net and do.pingcap.net
FAILED_LIST="$(python3 - <<PY
import re,sys
body=sys.stdin.read()
pairs=[]
for line in body.splitlines():
  # e.g. "pull-cdc-mysql-integration-heavy b8473b1 link"
  if "link" in line and ("prow.tidb.net" in line or "do.pingcap.net" in line):
    # capture test name and the first http(s) url
    m=re.search(r'^(\\S+)\\s+\\S+\\s+.*?(https?://\\S+)', line.strip())
    if m:
      pairs.append((m.group(1), m.group(2)))
# print as TSV
for t,u in pairs:
  print(f"{t}\\t{u}")
PY
<<<"$FAIL_COMMENT")"

if [[ -z "$FAILED_LIST" ]]; then
  echo "ERROR: parsed failure summary but found no (job, link) pairs."
  exit 4
fi

# Filter by --job if provided
SELECTED="$(python3 - <<PY
import sys
jobs=set(sys.argv[1].split(",")) if len(sys.argv)>1 and sys.argv[1] else None
rows=[r.split("\\t",1) for r in sys.stdin.read().splitlines() if "\\t" in r]
out=[]
for t,u in rows:
  if jobs is None or t in jobs:
    out.append((t,u))
for t,u in out:
  print(f"{t}\\t{u}")
PY
"$(IFS=,; echo "${JOBS[*]:-}")" <<<"$FAILED_LIST")"

if [[ -z "$SELECTED" ]]; then
  echo "ERROR: no failed jobs matched --job filters."
  echo "Failed jobs found:"
  echo "$FAILED_LIST" | sed 's/\t/ -> /g'
  exit 5
fi

echo
echo "Selected failed jobs (from latest ti-chi-bot failure summary):"
echo "$SELECTED" | sed 's/\t/ -> /g'
echo

mkdir -p "$LOG_DIR/pr-$PR_NUM"

# --- Download logs per job
download_jenkins() {
  local job="$1"
  local url="$2"

  # Parse .../detail/<jobName>/<buildNum>/...
  local jobName buildNum
  jobName="$(python3 - <<PY
import re,sys
u=sys.stdin.read()
m=re.search(r'/detail/([^/]+)/([0-9]+)/', u)
print(m.group(1) if m else "")
PY
<<<"$url")"
  buildNum="$(python3 - <<PY
import re,sys
u=sys.stdin.read()
m=re.search(r'/detail/([^/]+)/([0-9]+)/', u)
print(m.group(2) if m else "")
PY
<<<"$url")"
  if [[ -z "$jobName" || -z "$buildNum" ]]; then
    echo "WARN: cannot parse Jenkins jobName/buildNum from $url"
    return 0
  fi

  local buildUrl="https://do.pingcap.net/jenkins/job/pingcap/job/ticdc/job/${jobName}/${buildNum}/"
  local outDir="${LOG_DIR}/pr-${PR_NUM}/${job}/${buildNum}"
  mkdir -p "$outDir"

  echo "== Jenkins: $job ($jobName #$buildNum) =="
  echo "Build URL: $buildUrl"
  echo "Downloading consoleText..."
  curl -fsSL "$buildUrl/consoleText" -o "$outDir/consoleText.txt" || {
    echo "ERROR: curl consoleText failed (auth/SSO?)."
    echo "Please download logs/artifacts manually and give me the files."
    return 1
  }

  echo "Downloading artifacts list..."
  curl -fsSL "${buildUrl}api/json?tree=artifacts[fileName,relativePath]" -o "$outDir/artifacts.json" || true

  # Try wfapi (optional)
  curl -fsSL "${buildUrl}wfapi/describe" -o "$outDir/wfapi_describe.json" 2>/dev/null || true

  # Download artifacts that look like logs (or match groups)
  python3 - "$outDir" "$GROUPS" <<'PY'
import json,sys,os,re,subprocess
outdir=sys.argv[1]
groups=sys.argv[2].split(",") if sys.argv[2] else []
p=os.path.join(outdir,"artifacts.json")
if not os.path.exists(p):
  print("No artifacts.json; skipping artifact downloads.")
  sys.exit(0)
j=json.load(open(p))
arts=j.get("artifacts",[])
def want(rel, fn):
  s=(rel or "")+" "+(fn or "")
  if groups:
    return any(g and g in s for g in groups)
  # default: logs/text + compressed bundles
  return bool(re.search(r'(\.log|\.txt|\.out|\.json|\.xml|\.tar\.gz|\.tgz|\.zip)$', s))
wanted=[a for a in arts if want(a.get("relativePath",""), a.get("fileName",""))]
print(f"Artifacts matched: {len(wanted)}/{len(arts)}")
for a in wanted:
  rel=a.get("relativePath","")
  if not rel: continue
  # buildUrl is not stored here; we'll read from a small marker file created by bash later
PY
  # We can't easily download each artifact without buildUrl inside python.
  # We'll do it in bash by reading JSON via python and emitting relativePaths.
  rels="$(python3 - <<PY
import json,sys,os,re
outdir=sys.argv[1]; groups=sys.argv[2].split(",") if sys.argv[2] else []
j=json.load(open(os.path.join(outdir,"artifacts.json")))
arts=j.get("artifacts",[])
def want(rel, fn):
  s=(rel or "")+" "+(fn or "")
  if groups:
    return any(g and g in s for g in groups)
  return bool(re.search(r'(\.log|\.txt|\.out|\.json|\.xml|\.tar\.gz|\.tgz|\.zip)$', s))
for a in arts:
  rel=a.get("relativePath",""); fn=a.get("fileName","")
  if rel and want(rel,fn):
    print(rel)
PY
"$outDir" "$GROUPS")"

  if [[ -n "$rels" ]]; then
    echo "Downloading selected artifacts..."
    while IFS= read -r rel; do
      [[ -z "$rel" ]] && continue
      mkdir -p "$outDir/artifacts/$(dirname "$rel")"
      curl -fsSL "${buildUrl}artifact/${rel}" -o "$outDir/artifacts/${rel}" || true
    done <<< "$rels"
  else
    echo "No artifacts matched (or artifacts list unavailable)."
  fi

  echo "Saved Jenkins logs to: $outDir"
}

download_prow() {
  local job="$1"
  local url="$2"
  local outDir="${LOG_DIR}/pr-${PR_NUM}/${job}"
  mkdir -p "$outDir"

  echo "== Prow: $job =="
  echo "View URL: $url"

  # Parse bucket/path from /view/gs/<bucket>/<path...>
  local bucket path
  bucket="$(python3 - <<PY
import re,sys
u=sys.stdin.read()
m=re.search(r'/view/gs/([^/]+)/(.+)$', u)
print(m.group(1) if m else "")
PY
<<<"$url")"
  path="$(python3 - <<PY
import re,sys
u=sys.stdin.read()
m=re.search(r'/view/gs/([^/]+)/(.+)$', u)
print(m.group(2) if m else "")
PY
<<<"$url")"

  if [[ -z "$bucket" || -z "$path" ]]; then
    echo "WARN: cannot parse bucket/path from $url"
    return 0
  fi

  local gs_src="gs/${bucket}/${path}"
  local req_json
  req_json="$(python3 - <<PY
import json,sys,urllib.parse
req={"artifacts":["build-log.txt"],"index":1,"src":sys.argv[1]}
print(urllib.parse.quote(json.dumps(req,separators=(',',':'))))
PY
"$gs_src")"
  local top_enc
  top_enc="$(python3 - <<PY
import urllib.parse,sys
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
"$url")"

  local iframe="https://prow.tidb.net/spyglass/lens/buildlog/iframe?lensIndex=1&req=${req_json}&topURL=${top_enc}"

  echo "Downloading Spyglass buildlog iframe..."
  if ! curl -fsSL "$iframe" -o "$outDir/spyglass_buildlog.html"; then
    echo "ERROR: curl spyglass iframe failed."
    echo "Please download build-log.txt manually and provide it."
    return 1
  fi

  # Extract Raw build-log link (storage.googleapis.com) from iframe HTML
  local raw
  raw="$(python3 - <<'PY'
import re,sys
html=open(sys.argv[1]).read()
m=re.search(r'href="([^"]*storage\\.googleapis\\.com[^"]*)"', html)
print(m.group(1) if m else "")
PY
"$outDir/spyglass_buildlog.html")"

  if [[ -z "$raw" ]]; then
    echo "ERROR: cannot find raw build-log.txt link in spyglass HTML."
    echo "Please provide the logs manually."
    return 1
  fi

  echo "Downloading raw build-log.txt..."
  if ! curl -fsSL "$raw" -o "$outDir/build-log.txt"; then
    echo "ERROR: curl raw build-log failed."
    echo "Please provide the logs manually."
    return 1
  fi

  # Best-effort common metadata (ignore failures)
  for f in started.json finished.json prowjob.json metadata.json; do
    curl -fsSL "https://storage.googleapis.com/${bucket}/${path}/${f}" -o "$outDir/${f}" 2>/dev/null || true
  done

  echo "Saved Prow logs to: $outDir"
}

while IFS=$'\t' read -r job link; do
  if [[ "$link" == *"do.pingcap.net"* ]]; then
    download_jenkins "$job" "$link" || true
  elif [[ "$link" == *"prow.tidb.net"* ]]; then
    download_prow "$job" "$link" || true
  else
    echo "WARN: unknown CI link for $job: $link"
  fi
done <<< "$SELECTED"

echo
echo "Worktree: $WORKTREE_DIR"
echo "Logs root: $LOG_DIR/pr-$PR_NUM"
echo "Next: open downloaded logs + relevant code and start diagnosis."

