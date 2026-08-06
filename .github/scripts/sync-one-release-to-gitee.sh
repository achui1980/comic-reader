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

# NOTE: intentionally no `-e` — a 404 from the "does this release already
# exist" check below is an expected outcome, not an error, so failures are
# checked explicitly via HTTP status codes throughout instead of relying on
# errexit.
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
http_status=$(curl -s --connect-timeout 10 --max-time 60 -o /tmp/gitee_release.json -w "%{http_code}" \
  "${GITEE_API}/releases/tags/${tag}?access_token=${GITEE_TOKEN}")

if [ "$http_status" = "404" ]; then
  echo "--- [$tag] Creating Gitee release ---"
  payload=$(jq -n \
    --arg access_token "$GITEE_TOKEN" \
    --arg tag_name "$tag" \
    --arg name "$name" \
    --arg body "$body" \
    --argjson prerelease "$prerelease" \
    '{access_token: $access_token, tag_name: $tag_name, name: $name, body: $body, prerelease: $prerelease}')

  create_status=$(curl -s --connect-timeout 10 --max-time 60 -o /tmp/gitee_release.json -w "%{http_code}" \
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
attach_files_status=$(curl -s --connect-timeout 10 --max-time 60 -o /tmp/gitee_attach_files.json -w "%{http_code}" \
  "${GITEE_API}/releases/${release_id}/attach_files?access_token=${GITEE_TOKEN}")

if [ "$attach_files_status" != "200" ]; then
  echo "ERROR: [$tag] failed to list existing Gitee attach files (HTTP $attach_files_status)" >&2
  cat /tmp/gitee_attach_files.json >&2
  exit 1
fi

existing_files=$(jq -r '.[].name' /tmp/gitee_attach_files.json)

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
    # Release assets can be large binaries (e.g. Android APKs); use a longer
    # transfer timeout than the small metadata API calls above/below.
    curl -fsSL --connect-timeout 10 --max-time 600 -o "$tmp_file" "$asset_url" || {
      echo "ERROR: [$tag] failed to download $asset_name" >&2
      exit 1
    }

    echo "[$tag] Uploading $asset_name to Gitee..."
    upload_status=$(curl -s --connect-timeout 10 --max-time 600 -o /tmp/gitee_upload.json -w "%{http_code}" \
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
