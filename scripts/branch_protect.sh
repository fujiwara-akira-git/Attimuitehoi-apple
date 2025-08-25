#!/usr/bin/env bash
set -euo pipefail

# Usage: GITHUB_OWNER=fujiwara-akira-git GITHUB_REPO=Attimuitehoi-apple GITHUB_TOKEN=ghp_xxx ./scripts/branch_protect.sh

: ${GITHUB_OWNER:?Need to set GITHUB_OWNER}
: ${GITHUB_REPO:?Need to set GITHUB_REPO}
: ${GITHUB_TOKEN:?Need to set GITHUB_TOKEN}

API_URL="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/branches/main/protection"

echo "Applying branch protection to ${GITHUB_OWNER}/${GITHUB_REPO}..."

curl -sS -X PUT "$API_URL" \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -d '{
    "required_status_checks": null,
    "enforce_admins": false,
    "required_pull_request_reviews": {
      "dismiss_stale_reviews": true,
      "require_code_owner_reviews": false,
      "required_approving_review_count": 1
    },
    "restrictions": null
  }' | jq .

echo "Done. If the request failed, check your token and repository name."
