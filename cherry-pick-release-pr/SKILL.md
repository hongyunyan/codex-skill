---
name: cherry-pick-release-pr
description: Backport a merged GitHub pull request to a release branch through a repository cherry-pick bot, then monitor the generated PR, inspect and fix conflicts or conflict markers, compare original and cherry-pick diff statistics, push any required fixes, and observe checks. Use when the user asks to cherry-pick/backport a PR to a release branch, reply with a `/cherry-pick release-branch` command, check the generated PR for conflicts, or explain why generated PR line counts differ from the original PR.
---

# Cherry Pick Release PR

## Overview

Use this workflow for GitHub repositories that support a PR comment command such as `/cherry-pick release-x.y`.
Drive the request end to end: trigger the bot, find the generated PR, audit it for conflicts and diff drift, fix only what is needed, push to the generated PR branch, and report final status.

## Workflow

1. Resolve the original PR and target release branch.
   - Get PR metadata: title, state, merge status, base/head refs, merge commit, changed file count, additions, and deletions.
   - Confirm the target branch exists locally or remotely. Fetch the target branch before local comparisons.
   - Check recent PR comments for an existing identical `/cherry-pick <branch>` command to avoid duplicate PRs.

2. Trigger the cherry-pick bot.
   - Prefer GitHub connector comments when available.
   - If connector writes are forbidden, use the authenticated `gh` CLI, for example `gh pr comment <pr> --repo <owner/repo> --body '/cherry-pick <branch>'`.
   - Record the comment URL or comment ID when available.

3. Poll for the generated PR.
   - Search open and recently created PRs targeting the release branch.
   - Match by branch name patterns such as `cherry-pick-<original-pr>-to-<target-branch>`, PR title containing `#<original-pr>`, or bot comments linking the new PR.
   - Capture generated PR metadata: URL, number, head repo, head branch, head SHA, base SHA, mergeable state, changed file count, additions, deletions, and check status.

4. Audit the generated PR before assuming it is clean.
   - Do not rely only on GitHub `mergeable`. Also fetch the PR ref and search for textual conflict markers:
     `git grep -n -E '^(<<<<<<<|=======|>>>>>>>)' refs/remotes/<remote>/pr/<number> -- .`
   - Compare original and generated file lists with `git diff --name-status`.
   - Compare per-file line stats with `git diff --numstat <base> <head>`.
   - If the generated PR has different line counts, identify the exact files responsible before explaining.

5. Fix conflicts or release-branch drift when needed.
   - Work in a separate worktree or isolated checkout based on the generated PR head. Do not touch unrelated dirty files in the user's main checkout.
   - Preserve the intended backport behavior. Do not silently import unrelated master-only behavior just to make tests pass.
   - Remove literal conflict markers and reconcile both sides according to the release branch's existing APIs and test layout.
   - When bot output includes tests from the original base that do not fit the release branch, replace them with minimal release-compatible coverage for the cherry-picked behavior.
   - Keep edits narrowly scoped to the generated PR.

6. Validate locally.
   - Run the repository's required formatter after code changes, for example `make fmt` when the repo requires it.
   - Run the smallest relevant tests for changed packages and critical paths.
   - If the repo has special test tags or test helper rules, obey them.
   - Do not claim a check was run unless it actually completed.

7. Push fixes to the generated PR branch.
   - Confirm the PR has `maintainerCanModify` or that the authenticated account can push to the head branch.
   - Commit only the generated PR fixes.
   - Push to the generated PR head branch. Avoid force push unless the user explicitly requested and confirmed it.

8. Observe remote checks.
   - Refresh PR metadata after push.
   - Wait for relevant CI checks to complete when feasible.
   - Distinguish code failures from normal merge gates such as missing approval labels.
   - If a check fails, inspect logs and either fix the issue or report the blocker with evidence.

9. Final report.
   - Provide links to the original PR and generated PR.
   - State whether conflicts existed and what was fixed.
   - Report original vs generated changed files, additions, and deletions.
   - Explain any line-count differences with file-level reasons.
   - List local validation commands and remote check outcomes.
   - Mention remaining non-code gates, such as approvals, separately from conflict or CI status.

## Practical Commands

Use command variants that match the repository and available tools:

```bash
gh pr view <original-pr> --repo <owner/repo> --json number,title,state,mergedAt,baseRefName,headRefName,baseRefOid,headRefOid,mergeCommit,additions,deletions,changedFiles,url
gh api repos/<owner>/<repo>/issues/<original-pr>/comments --paginate --jq '.[] | select(.body | contains("/cherry-pick"))'
gh pr comment <original-pr> --repo <owner/repo> --body '/cherry-pick <target-branch>'
gh pr list --repo <owner/repo> --state all --base <target-branch> --search '<original-pr>' --json number,title,url,headRefName,headRepositoryOwner,headRepository,createdAt,updatedAt,additions,deletions,changedFiles,mergeable,mergeStateStatus,state
git fetch <remote> <target-branch> pull/<generated-pr>/head:refs/remotes/<remote>/pr/<generated-pr>
git grep -n -E '^(<<<<<<<|=======|>>>>>>>)' refs/remotes/<remote>/pr/<generated-pr> -- .
git diff --numstat <original-base-sha> <original-head-sha>
git diff --numstat <generated-base-sha> refs/remotes/<remote>/pr/<generated-pr>
```

## Decision Rules

- If connector write access fails but `gh` is authenticated, use `gh` for the comment and keep going.
- If the bot does not create a PR, inspect the original PR comments for bot errors before retrying.
- If GitHub reports `MERGEABLE` but conflict markers exist in files, treat the PR as needing manual conflict cleanup.
- If the generated PR line count differs from the original, do not assume it is wrong. Release branches often lack or already contain surrounding test/config changes from master.
- If the generated PR branch is not pushable, report the exact permission blocker and the required next action.
- If all code checks pass but `tide` or an equivalent merge gate is pending for approval, report it as a normal approval gate, not as unresolved code work.
