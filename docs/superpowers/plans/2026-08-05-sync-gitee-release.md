# Sync GitHub Releases to Gitee Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically (and, once, historically) mirror every published GitHub Release — metadata and binary attachments — from `achui1980/comic-reader` to the Gitee mirror `achui/comic-reader`, without touching the existing `release.yml` (build+publish) or `sync-gitee.yml` (git mirror) workflows.

**Architecture:** A new standalone workflow `.github/workflows/sync-gitee-release.yml` triggers on `release: types: [published]` (syncs the one new release) and on `workflow_dispatch` (syncs every published release, for the one-time historical backfill and as a safe manual re-run). Both triggers resolve to a list of tags, then loop over that list calling a single reusable Bash script `.github/scripts/sync-one-release-to-gitee.sh <tag>` that does the actual idempotent per-tag sync (read GitHub release via `gh api`, create-if-missing on Gitee via API v5, upload any missing attachment).

**Tech Stack:** GitHub Actions (`ubuntu-latest`), GitHub CLI (`gh`, preinstalled on the runner, auto-authenticated via `GITHUB_TOKEN`), `jq` (preinstalled), `curl`, Gitee OpenAPI v5 (`https://gitee.com/api/v5`), existing secret `GITEE_TOKEN` (already present in the repo, used by `sync-gitee.yml`).

## Global Constraints

- Do not modify `.github/workflows/release.yml` or `.github/workflows/sync-gitee.yml` — this is a new, independent workflow.
- No new GitHub Secrets: GitHub side reads with the built-in `GITHUB_TOKEN`; Gitee side reuses the existing `GITEE_TOKEN` secret as the API v5 `access_token`.
- GitHub repo: owner `achui1980`, repo `comic-reader`. Gitee repo: owner `achui`, repo `comic-reader` (`https://gitee.com/achui/comic-reader.git`).
- Per-tag sync must be idempotent: re-running for a tag that's already fully synced must be a safe no-op (no duplicate releases, no duplicate attachment uploads, no errors).
- Draft GitHub releases must be skipped (safety net; current `release.yml` always publishes with `draft:false`).
- A single tag failing to sync must not abort the rest of the batch (relevant for the `workflow_dispatch` historical-backfill path, which processes every tag in one run).
- Do not create a `target_commitish` when creating a Gitee release — the tag is already mirrored to Gitee by `sync-gitee.yml`, so Gitee auto-associates it.
- Do not actually trigger the live workflow on GitHub during implementation — local verification is limited to syntax checks and read-only dry runs against the real GitHub API (no Gitee credentials are available locally). The final live `workflow_dispatch` run is performed by the user after this plan is merged (per spec's own verification section).

---

### Task 1: Per-release sync script

**Files:**
- Create: `.github/scripts/sync-one-release-to-gitee.sh`

**Interfaces:**
- Consumes: nothing from other tasks (first task).
- Produces: an executable Bash script invoked as `sync-one-release-to-gitee.sh <tag>`.
  - Required env vars at call time: `GH_OWNER`, `GH_REPO`, `GITEE_OWNER`, `GITEE_REPO`, `GITEE_TOKEN`, and `GH_TOKEN` (consumed implicitly by the `gh` CLI, not read directly by the script).
  - Exit code `0` on success or on a deliberate skip (draft release).
  - Exit code `1` on any failure (missing arg, GitHub API failure, Gitee API failure, download/upload failure) after printing an `ERROR: ...` line to stderr.
  - Task 2 relies on exactly this argument order, these env var names, and these exit code semantics.

- [ ] **Step 1: Write the script**

Create `.github/scripts/sync-one-release-to-gitee.sh`:

```bash
#!/usr/bin/env bash
# Sync a single GitHub release (by tag) to Gitee: creates the release if
# missing and uploads any attachment assets that are not yet on Gitee.
# Idempotent: safe to re-run for the same tag any number of times.
#
# Required env vars:
#   GH_OWNER, GH_REPO       - GitHub repo to read releases from
#   GITEE_OWNER, GITEE_REPO - Gitee repo to sync releases to
#   GITEE_TOKEN             - Gitee API v5 access token
#   GH_TOKEN                - used implicitly by the `gh` CLI
#
# Usage: sync-one-release-to-gitee.sh <tag>

set -uo pipefail

tag="${1:-}"
if [ -z "$tag" ]; then
  echo "Usage: $0 <tag>" >&2
  exit 1
fi

: "${GH_OWNER:?GH_OWNER not set}"
: "${GH_REPO:?GH_REPO not set}"
: "${GITEE_OWNER:?GITEE_OWNER not set}"
: "${GITEE_REPO:?GITEE_REPO not set}"
: "${GITEE_TOKEN:?GITEE_TOKEN not set}"

GITEE_API="https://gitee.com/api/v5/repos/${GITEE_OWNER}/${GITEE_REPO}"

echo "--- [$tag] Fetching GitHub release info ---"
release_json=$(gh api "repos/${GH_OWNER}/${GH_REPO}/releases/tags/${tag}") || {
  echo "ERROR: [$tag] failed to fetch GitHub release" >&2
  exit 1
}

draft=$(echo "$release_json" | jq -r '.draft')
if [ "$draft" = "true" ]; then
  echo "[$tag] is a draft release, skipping."
  exit 0
fi

name=$(echo "$release_json" | jq -r '.name // ""')
body=$(echo "$release_json" | jq -r '.body // ""')
prerelease=$(echo "$release_json" | jq -r '.prerelease')

echo "--- [$tag] Checking for existing Gitee release ---"
http_status=$(curl -s -o /tmp/gitee_release.json -w "%{http_code}" \
  "${GITEE_API}/releases/tags/${tag}?access_token=${GITEE_TOKEN}")

if [ "$http_status" = "404" ]; then
  echo "--- [$tag] Creating Gitee release ---"
  payload=$(jq -n \
    --arg token "$GITEE_TOKEN" \
    --arg tag "$tag" \
    --arg name "$name" \
    --arg body "$body" \
    --argjson prerelease "$prerelease" \
    '{access_token: $token, tag_name: $tag, name: $name, body: $body, prerelease: $prerelease}')

  create_status=$(curl -s -o /tmp/gitee_release.json -w "%{http_code}" \
    -X POST -H "Content-Type: application/json" \
    -d "$payload" \
    "${GITEE_API}/releases")

  if [ "$create_status" != "200" ] && [ "$create_status" != "201" ]; then
    echo "ERROR: [$tag] failed to create Gitee release (HTTP $create_status)" >&2
    cat /tmp/gitee_release.json >&2
    exit 1
  fi
elif [ "$http_status" != "200" ]; then
  echo "ERROR: [$tag] unexpected HTTP $http_status checking Gitee release" >&2
  cat /tmp/gitee_release.json >&2
  exit 1
else
  echo "[$tag] Gitee release already exists."
fi

release_id=$(jq -r '.id' /tmp/gitee_release.json)
if [ -z "$release_id" ] || [ "$release_id" = "null" ]; then
  echo "ERROR: [$tag] could not determine Gitee release id" >&2
  cat /tmp/gitee_release.json >&2
  exit 1
fi
echo "[$tag] Gitee release id: $release_id"

echo "--- [$tag] Syncing attachments ---"
existing_files=$(curl -s "${GITEE_API}/releases/${release_id}/attach_files?access_token=${GITEE_TOKEN}" | jq -r '.[].name')

asset_count=$(echo "$release_json" | jq '.assets | length')
i=0
while [ "$i" -lt "$asset_count" ]; do
  asset_name=$(echo "$release_json" | jq -r ".assets[$i].name")
  asset_url=$(echo "$release_json" | jq -r ".assets[$i].browser_download_url")

  if printf '%s\n' "$existing_files" | grep -qxF "$asset_name"; then
    echo "[$tag] $asset_name already on Gitee, skipping."
  else
    echo "[$tag] Downloading $asset_name from GitHub..."
    tmp_file="/tmp/gitee_asset_${i}"
    curl -sL -o "$tmp_file" "$asset_url" || {
      echo "ERROR: [$tag] failed to download $asset_name" >&2
      exit 1
    }

    echo "[$tag] Uploading $asset_name to Gitee..."
    upload_status=$(curl -s -o /tmp/gitee_upload.json -w "%{http_code}" \
      -X POST \
      -F "access_token=${GITEE_TOKEN}" \
      -F "file=@${tmp_file};filename=${asset_name}" \
      "${GITEE_API}/releases/${release_id}/attach_files")

    rm -f "$tmp_file"

    if [ "$upload_status" != "200" ] && [ "$upload_status" != "201" ]; then
      echo "ERROR: [$tag] failed to upload $asset_name (HTTP $upload_status)" >&2
      cat /tmp/gitee_upload.json >&2
      exit 1
    fi
  fi
  i=$((i + 1))
done

echo "--- [$tag] Sync complete ---"
exit 0
```

- [ ] **Step 2: Make it executable and syntax-check it**

Run:
```bash
chmod +x .github/scripts/sync-one-release-to-gitee.sh
bash -n .github/scripts/sync-one-release-to-gitee.sh
```
Expected: `chmod` prints nothing; `bash -n` prints nothing and exits 0 (no syntax errors).

- [ ] **Step 3: Dry-run the GitHub-read logic against the real repo (read-only, no Gitee calls)**

This validates the `jq` field extraction the script relies on, using a real non-draft release with attachments, without needing any Gitee credentials.

Run:
```bash
gh api repos/achui1980/comic-reader/releases/tags/v1.0.0 | jq -r '.draft, .name, .prerelease, (.assets | length)'
```
Expected output (4 lines):
```
false
Comic Reader v1.0.0
false
3
```

- [ ] **Step 4: Verify the draft-skip branch with synthetic data**

Run:
```bash
echo '{"draft": true}' | jq -r '.draft'
```
Expected output:
```
true
```
This confirms the `draft = $(... jq -r '.draft')` extraction yields the exact string `"true"` that the script's `if [ "$draft" = "true" ]` check compares against.

- [ ] **Step 5: Commit**

```bash
git add .github/scripts/sync-one-release-to-gitee.sh
git commit -m "feat: add per-release Gitee sync script"
```

---

### Task 2: Workflow wiring (triggers + tag list + loop)

**Files:**
- Create: `.github/workflows/sync-gitee-release.yml`

**Interfaces:**
- Consumes: `.github/scripts/sync-one-release-to-gitee.sh <tag>` from Task 1 (same argument, env vars, and exit-code contract as documented there).
- Produces: a workflow named "Sync Releases to Gitee" with job `sync-releases`, triggered by `release: types: [published]` and `workflow_dispatch`. No later task depends on this workflow's internals beyond "it exists and runs the Task 1 script for every relevant tag."

- [ ] **Step 1: Write the workflow file**

Create `.github/workflows/sync-gitee-release.yml`:

```yaml
# 同步 GitHub Release 到 Gitee。
#
# 与 .github/workflows/sync-gitee.yml(同步分支/tag)是独立的两个 workflow:
# 这个文件只负责同步 Release 的标题/说明/二进制附件,不涉及 git 对象。
#
# 触发方式:
#   - release: published  -> 只同步刚发布的这一个 tag(覆盖"未来")
#   - workflow_dispatch    -> 遍历所有已发布的 release 逐一同步
#                             (用于一次性补齐历史,以及日常安全重跑)
#
# 认证:
#   - GitHub 侧读取用内置 GITHUB_TOKEN(gh CLI 自动使用)
#   - Gitee 侧写入复用已有的 GITEE_TOKEN secret,无需新增 secret
name: Sync Releases to Gitee

on:
  release:
    types: [published]
  workflow_dispatch: {}

permissions:
  contents: read

env:
  GH_OWNER: achui1980
  GH_REPO: comic-reader
  GITEE_OWNER: achui
  GITEE_REPO: comic-reader

jobs:
  sync-releases:
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      GITEE_TOKEN: ${{ secrets.GITEE_TOKEN }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Determine tags to sync
        id: determine_tags
        run: |
          if [ "${{ github.event_name }}" = "release" ]; then
            tag="${{ github.event.release.tag_name }}"
            echo "tags=$tag" >> "$GITHUB_OUTPUT"
          else
            tags=$(gh api "repos/${GH_OWNER}/${GH_REPO}/releases" --paginate --jq '.[].tag_name' | tr '\n' ' ')
            echo "tags=$tags" >> "$GITHUB_OUTPUT"
          fi

      - name: Sync each tag to Gitee
        run: |
          chmod +x .github/scripts/sync-one-release-to-gitee.sh
          failed=""
          for tag in ${{ steps.determine_tags.outputs.tags }}; do
            echo "=== Syncing tag: $tag ==="
            if ! .github/scripts/sync-one-release-to-gitee.sh "$tag"; then
              echo "!!! Failed to sync tag: $tag"
              failed="$failed $tag"
            fi
          done
          if [ -n "$failed" ]; then
            echo "The following tags failed to sync:$failed"
            exit 1
          fi
```

- [ ] **Step 2: Validate YAML syntax**

Run:
```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/sync-gitee-release.yml'); puts 'YAML OK'"
```
Expected output:
```
YAML OK
```

- [ ] **Step 3: Dry-run the `workflow_dispatch` tag-listing command against the real repo**

This is the exact command used in the "Determine tags to sync" step's `else` branch (workflow_dispatch path).

Run:
```bash
gh api "repos/achui1980/comic-reader/releases" --paginate --jq '.[].tag_name' | tr '\n' ' '
```
Expected: a space-separated list containing all 9 currently published tags, including at least these:
```
v1.2.1-build.18 v1.2.0-build.17 v1.1.2-build.16 v1.1.1-build.15 v1.1.0-build.14 v1.0.4-build.13 v1.0.4-build.12 v1.0.3 v1.0.0
```
(Order may vary slightly and additional tags may appear if new releases were published after this plan was written — that's fine, it just confirms the command returns a non-empty, space-separated tag list.)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/sync-gitee-release.yml
git commit -m "feat: add workflow to sync GitHub releases to Gitee"
```

---

### Task 3: Final self-review and manual verification handoff

**Files:**
- Modify: none (review-only task; no code changes expected unless the review in Step 1 finds a real problem).

**Interfaces:**
- Consumes: the script from Task 1 and the workflow from Task 2.
- Produces: nothing new — this task's output is a verification report to the user plus (if needed) a follow-up fix commit.

- [ ] **Step 1: Re-run both syntax checks together**

Run:
```bash
bash -n .github/scripts/sync-one-release-to-gitee.sh && echo "script syntax OK"
ruby -ryaml -e "YAML.load_file('.github/workflows/sync-gitee-release.yml'); puts 'workflow YAML OK'"
```
Expected output:
```
script syntax OK
workflow YAML OK
```
If either check fails, fix the corresponding file and re-commit (`git commit --amend` if the previous commit was the one introducing the file, otherwise a new fix commit) before moving on.

- [ ] **Step 2: Walk the spec's requirements against the two files and confirm each is covered**

Open `docs/superpowers/specs/2026-08-05-sync-gitee-release-design.md` and check off each of these against the actual file contents (all should already be true from Tasks 1–2; this step is a read-only confirmation, not new code):

- [ ] Two triggers present: `release: types: [published]` and `workflow_dispatch` (spec "触发方式").
- [ ] No new secrets referenced anywhere — only `secrets.GITHUB_TOKEN` and `secrets.GITEE_TOKEN` (spec "认证").
- [ ] Draft releases are skipped (spec step 2 of "核心同步逻辑").
- [ ] Gitee release lookup uses `GET .../releases/tags/$tag`, create uses `POST .../releases` without `target_commitish` (spec steps 3–4).
- [ ] Attachment sync compares existing Gitee filenames against GitHub asset names and only uploads the missing ones (spec step 5).
- [ ] A single tag's failure inside the `workflow_dispatch` loop does not stop the loop, but the job exits non-zero at the end if anything failed (spec "错误处理").

- [ ] **Step 3: Report manual verification steps to the user**

Since there is no local Gitee credential available in this environment, the live end-to-end test must be run by the user after these commits are pushed. Tell the user to do the following (do not run these yourself):

1. Push the branch/commits to GitHub (`git push`).
2. On GitHub, go to the repo's **Actions** tab → select **"Sync Releases to Gitee"** → click **"Run workflow"** (this exercises the `workflow_dispatch` / historical-backfill path against all 9+ existing releases).
3. Watch the run's log for the `Sync each tag to Gitee` step; confirm it completes without a final "failed to sync" error.
4. On Gitee, open `https://gitee.com/achui/comic-reader/releases` and confirm every tag from GitHub now has a matching release with the same title/notes and all three attachment files (`.dmg`/`.zip`/`.apk`).
5. Re-run the same `workflow_dispatch` a second time to confirm idempotency (no duplicate releases, no duplicate attachments, no errors).
6. From then on, publishing a new GitHub release will auto-trigger this workflow via the `release: published` event — no further manual action needed.

- [ ] **Step 4: Commit any fixes found during review (only if Step 1 or Step 2 surfaced an issue)**

```bash
git add -A
git commit -m "fix: address issues found in sync-gitee-release self-review"
```
If no issues were found, skip this step — there is nothing to commit.
