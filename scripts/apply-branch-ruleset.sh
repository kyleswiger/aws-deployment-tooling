#!/usr/bin/env bash
#
# Apply the shared default-branch ruleset to one or more GitHub repositories.
#
#   ./scripts/apply-branch-ruleset.sh kyleswiger/repo-a kyleswiger/repo-b
#   ./scripts/apply-branch-ruleset.sh --ruleset ./my-ruleset.json owner/repo
#   ./scripts/apply-branch-ruleset.sh --dry-run owner/repo
#
# Idempotent: matches an existing ruleset by its `name` and updates it in place,
# otherwise creates a new one. Re-running never produces duplicates.
#
# Requires: gh (authenticated), jq.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULESET_FILE="${SCRIPT_DIR}/../templates/github-rulesets/default-branch-protection.json"
DRY_RUN=0
REPOS=()

usage() {
  sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^#\s\?//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ruleset) RULESET_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage 0 ;;
    -*) echo "unknown flag: $1" >&2; usage 1 ;;
    *) REPOS+=("$1"); shift ;;
  esac
done

[[ ${#REPOS[@]} -gt 0 ]] || usage 1

for cmd in gh jq; do
  command -v "$cmd" >/dev/null || { echo "error: $cmd is required" >&2; exit 1; }
done

[[ -f "$RULESET_FILE" ]] || { echo "error: no ruleset file at $RULESET_FILE" >&2; exit 1; }
jq empty "$RULESET_FILE" || { echo "error: $RULESET_FILE is not valid JSON" >&2; exit 1; }

RULESET_NAME="$(jq -r '.name' "$RULESET_FILE")"
failed=0

for repo in "${REPOS[@]}"; do
  echo "==> ${repo}"

  # `gh api` exits non-zero on 4xx; capture the body so we can explain the
  # common failures (private repo without Pro, missing repo) instead of
  # dumping a raw REST error.
  if ! existing="$(gh api "repos/${repo}/rulesets" 2>&1)"; then
    if grep -q "Upgrade to GitHub Pro" <<<"$existing"; then
      echo "    SKIPPED: rulesets require GitHub Pro on private repos." >&2
      echo "    Make the repo public or upgrade, then re-run this script." >&2
    else
      echo "    FAILED: ${existing}" >&2
    fi
    failed=1
    continue
  fi

  ruleset_id="$(jq -r --arg n "$RULESET_NAME" \
    'map(select(.name == $n)) | first | .id // empty' <<<"$existing")"

  if [[ -n "$ruleset_id" ]]; then
    method=PUT
    endpoint="repos/${repo}/rulesets/${ruleset_id}"
    action="update existing ruleset ${ruleset_id}"
  else
    method=POST
    endpoint="repos/${repo}/rulesets"
    action="create ruleset"
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "    DRY RUN: would ${action} via ${method} ${endpoint}"
    continue
  fi

  echo "    ${action}..."
  if ! result="$(gh api --method "$method" "$endpoint" --input "$RULESET_FILE" 2>&1)"; then
    echo "    FAILED: ${result}" >&2
    failed=1
    continue
  fi

  echo "    OK: $(jq -r '"\(.name) (id \(.id)) enforcement=\(.enforcement)"' <<<"$result")"
done

exit "$failed"
