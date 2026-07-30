#!/usr/bin/env bash
# detect-changes.sh
#
# Emits BUILD_* flags describing which components changed between HEAD and a
# baseline commit, so buildspec.yml / run-ci.sh only build what actually changed.
# Writes them to $CHANGE_FLAGS_FILE (default ./change-flags.env) and exports them.
#
# ADAPT the component globs in the "match" section below to your repo layout.
# The defaults assume: ui/, src/api/, src/shared/, terraform/ (or infra/).
#
# Baseline selection:
#   1. FORCE_FULL_BUILD=true              → everything true (manual override).
#   2. CODEBUILD_WEBHOOK_BASE_REF set     → diff against the PR target branch.
#   3. CODEBUILD_WEBHOOK_PREV_COMMIT set  → diff against it (push event).
#   4. HEAD~1                             → single-commit fallback.
#   5. No git history                     → fall back to a full build.

set -euo pipefail

log()      { printf '[detect-changes] %s\n' "$*"; }
set_flag() { export "$1=$2"; echo "$1=$2" >> "${CHANGE_FLAGS_FILE:-./change-flags.env}"; }

: > "${CHANGE_FLAGS_FILE:-./change-flags.env}"

if [[ "${FORCE_FULL_BUILD:-false}" == "true" ]]; then
  log "FORCE_FULL_BUILD=true — treating everything as changed"
  set_flag BUILD_UI true
  set_flag BUILD_API true
  set_flag BUILD_SHARED true
  set_flag BUILD_TERRAFORM true
  set_flag BUILD_RUNNER_IMAGE true
  set_flag ANY_CODE_CHANGED true
  set_flag CHANGED_FILES_COUNT -1
  exit 0
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "not inside a git work tree; forcing full build"
  FORCE_FULL_BUILD=true exec "$0"
fi

# CodePipeline/CodeBuild checkouts default to depth=1; deepen best-effort.
git fetch --no-tags --depth=50 origin "${CODEBUILD_WEBHOOK_HEAD_REF:-main}" 2>/dev/null || true
git fetch --no-tags --depth=50 origin main 2>/dev/null || true

BASE_REF=""
if [[ -n "${CODEBUILD_WEBHOOK_BASE_REF:-}" ]]; then
  BASE_REF="origin/${CODEBUILD_WEBHOOK_BASE_REF#refs/heads/}"
elif [[ -n "${CODEBUILD_WEBHOOK_PREV_COMMIT:-}" ]]; then
  BASE_REF="${CODEBUILD_WEBHOOK_PREV_COMMIT}"
elif git rev-parse HEAD~1 >/dev/null 2>&1; then
  BASE_REF="HEAD~1"
fi

if [[ -z "$BASE_REF" ]] || ! git rev-parse "$BASE_REF" >/dev/null 2>&1; then
  log "no usable baseline ref (tried '${BASE_REF:-<none>}') — forcing full build"
  FORCE_FULL_BUILD=true exec "$0"
fi

log "diffing HEAD against ${BASE_REF}"
CHANGED=$(git diff --name-only "$BASE_REF"...HEAD || true)
CHANGED_COUNT=$(printf '%s\n' "$CHANGED" | grep -c . || true)
log "changed files: ${CHANGED_COUNT}"

match() { printf '%s\n' "$CHANGED" | grep -Eq "$1"; }

BUILD_UI=false
BUILD_API=false
BUILD_SHARED=false
BUILD_TERRAFORM=false
BUILD_RUNNER_IMAGE=false

# --- component globs: adapt to your repo ---
match '^ui/'                               && BUILD_UI=true
match '^src/api/'                          && BUILD_API=true
match '^src/shared/'                       && BUILD_SHARED=true
match '^(terraform|infra)/'                && BUILD_TERRAFORM=true
match '^docker/codebuild-runner/'          && BUILD_RUNNER_IMAGE=true
match '^buildspec(-codebuild-image)?\.yml' && BUILD_RUNNER_IMAGE=true
# A change to shared build scripts forces everything to rebuild.
match '^scripts/'                          && { BUILD_API=true; BUILD_UI=true; BUILD_TERRAFORM=true; }

# Shared code forces the impacted backend(s) to rebuild.
[[ "$BUILD_SHARED" == "true" ]] && BUILD_API=true

# Docs-only / markdown / license changes keep everything false, so downstream
# stages skip wholesale.
ANY_CODE_CHANGED=false
if [[ "$BUILD_UI" == "true" || "$BUILD_API" == "true" || \
      "$BUILD_TERRAFORM" == "true" || "$BUILD_RUNNER_IMAGE" == "true" ]]; then
  ANY_CODE_CHANGED=true
fi

set_flag BUILD_UI "$BUILD_UI"
set_flag BUILD_API "$BUILD_API"
set_flag BUILD_SHARED "$BUILD_SHARED"
set_flag BUILD_TERRAFORM "$BUILD_TERRAFORM"
set_flag BUILD_RUNNER_IMAGE "$BUILD_RUNNER_IMAGE"
set_flag ANY_CODE_CHANGED "$ANY_CODE_CHANGED"
set_flag CHANGED_FILES_COUNT "$CHANGED_COUNT"

log "result: UI=$BUILD_UI API=$BUILD_API SHARED=$BUILD_SHARED TF=$BUILD_TERRAFORM RUNNER=$BUILD_RUNNER_IMAGE ANY=$ANY_CODE_CHANGED"
