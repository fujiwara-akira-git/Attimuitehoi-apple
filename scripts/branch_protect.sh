#!/usr/bin/env bash
set -euo pipefail

# Improved branch protection script
# Supports: env vars, CLI args, multiple repos (comma-separated), optional JSON config file
# Default: apply a simple PR review requirement (1 approving review)

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -o OWNER        GitHub owner (env: GITHUB_OWNER)
  -r REPO         GitHub repo (single) (env: GITHUB_REPO)
  -R REPOS        Comma-separated repos (overrides -r)
  -b BRANCH       Branch to protect (default: main)
  -t TOKEN        GitHub token (env: GITHUB_TOKEN)
  -f CONFIG       JSON file to use as protection payload (overrides default)
  -y              Skip confirmation prompt (yes)
  -n              Dry-run (show request but don't send)
  -v              Verbose
  -h              Show this help

Environment variables are used as defaults: GITHUB_OWNER, GITHUB_REPO, GITHUB_TOKEN
Example:
  GITHUB_TOKEN=ghp_xxx GITHUB_OWNER=fujiwara-akira-git ./scripts/branch_protect.sh -R "Attimuitehoi-apple,Attimuitehoi-web"
EOF
}

OWNER="${GITHUB_OWNER:-}" || true
REPO="${GITHUB_REPO:-}" || true
REPOS=""
BRANCH="main"
TOKEN="${GITHUB_TOKEN:-}" || true
CONFIG_FILE=""
ASSUME_YES=false
DRY_RUN=false
VERBOSE=false

while getopts ":o:r:R:b:t:f:ynvh" opt; do
  case $opt in
    o) OWNER="$OPTARG" ;;
    r) REPO="$OPTARG" ;;
    R) REPOS="$OPTARG" ;;
    b) BRANCH="$OPTARG" ;;
    t) TOKEN="$OPTARG" ;;
    f) CONFIG_FILE="$OPTARG" ;;
    y) ASSUME_YES=true ;;
    n) DRY_RUN=true ;;
    v) VERBOSE=true ;;
    h) usage; exit 0 ;;
    :) echo "Missing argument for -$OPTARG"; usage; exit 1 ;;
    \?) echo "Invalid option: -$OPTARG"; usage; exit 1 ;;
  esac
done

if [ -z "$OWNER" ]; then
  echo "Error: GitHub owner not set. Use -o or set GITHUB_OWNER." >&2
  usage
  exit 1
fi

if [ -z "$TOKEN" ]; then
  echo "Error: GitHub token not set. Use -t or set GITHUB_TOKEN." >&2
  usage
  exit 1
fi

# Build list of repos
if [ -n "$REPOS" ]; then
  IFS=',' read -ra REPO_LIST <<<"$REPOS"
elif [ -n "$REPO" ]; then
  REPO_LIST=("$REPO")
else
  echo "Error: No repository specified. Use -r or -R, or set GITHUB_REPO." >&2
  usage
  exit 1
fi

# Determine payload
if [ -n "$CONFIG_FILE" ]; then
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found: $CONFIG_FILE" >&2
    exit 1
  fi
  BODY=$(cat "$CONFIG_FILE")
else
  read -r -d '' BODY <<'JSON' || true
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1
  },
  "restrictions": null
}
JSON
fi

echo "Branch protection settings summary:"
echo "  Owner: $OWNER"
echo "  Branch: $BRANCH"
echo "  Repos: ${REPO_LIST[*]}"
echo "  Dry-run: $DRY_RUN"

if [ "$ASSUME_YES" = false ]; then
  read -r -p "Proceed to apply protection? [y/N]: " ans
  case "$ans" in
    [yY]|[yY][eE][sS]) : ;;
    *) echo "Aborted by user."; exit 0 ;;
  esac
fi

for r in "${REPO_LIST[@]}"; do
  API_URL="https://api.github.com/repos/${OWNER}/${r}/branches/${BRANCH}/protection"
  echo "Applying protection to ${OWNER}/${r} -> branch '${BRANCH}'"

  if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN: Would PUT $API_URL with body:" > /dev/stderr
    echo "$BODY" | sed -n '1,200p' > /dev/stderr
    continue
  fi

  # Send request and capture HTTP code and response
  resp_file=$(mktemp)
  http_code=$(curl -sS -w "%{http_code}" -o "$resp_file" -X PUT "$API_URL" \
    -H "Authorization: token ${TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -d "$BODY") || true

  if command -v jq >/dev/null 2>&1; then
    echo "Response (HTTP $http_code):"
    jq . "$resp_file" || cat "$resp_file"
  else
    echo "Response (HTTP $http_code):"
    cat "$resp_file"
    echo "(Install 'jq' for pretty JSON output)"
  fi

  rm -f "$resp_file"

  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    echo "Protection applied successfully to ${OWNER}/${r}"
  else
    echo "Failed to apply protection to ${OWNER}/${r} (HTTP $http_code)" >&2
  fi
done

echo "All done."
