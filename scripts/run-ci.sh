#!/usr/bin/env bash
# run-ci.sh <install|prebuild|build|postbuild>
#
# Thin orchestrator called by buildspec.yml. Reads the change flags emitted by
# detect-changes.sh and runs only the phases relevant to what changed. Every
# skipped phase prints why, so build logs stay auditable.
#
# ADAPT the component-specific commands (pip installs, docker builds, lambda
# names) to your repo. This is a faithful skeleton of a working container-Lambda
# + SPA pipeline; the shape is the reusable part.
#
# Required env (set on the CodeBuild project — see codepipeline.tf you keep
# in-repo, and buildspec.yml):
#   ECR_API_REPOSITORY_URL, UI_BUCKET_NAME, CLOUDFRONT_DISTRIBUTION_ID,
#   API_LAMBDA_NAME, RUN_TERRAFORM_APPLY

set -euo pipefail

PHASE="${1:?usage: run-ci.sh <install|prebuild|build|postbuild>}"
FLAGS_FILE="${CHANGE_FLAGS_FILE:-./change-flags.env}"
if [[ -f "$FLAGS_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$FLAGS_FILE"; set +a
fi

log()  { printf '[ci:%s] %s\n' "$PHASE" "$*"; }
skip() { printf '[ci:%s] SKIP %s (%s)\n' "$PHASE" "$1" "$2"; }

: "${AWS_DEFAULT_REGION:=us-east-1}"
: "${IMAGE_TAG:=${CODEBUILD_RESOLVED_SOURCE_VERSION:-latest}}"
: "${ECR_API_REPOSITORY_URL:=}"
: "${UI_BUCKET_NAME:=}"
: "${CLOUDFRONT_DISTRIBUTION_ID:=}"
: "${API_LAMBDA_NAME:=}"
: "${RUN_TERRAFORM_APPLY:=false}"

run_test_gate() {
  if [[ "${BUILD_API:-false}" == "true" ]]; then
    log "running backend test gate"
    mkdir -p reports/pytest
    pip install --cache-dir /root/.cache/pip pytest
    pytest -q tests --junitxml=reports/pytest/pytest.xml
  else
    skip "test gate" "no backend changes"
  fi
}

ensure_dockerd() {
  if docker info >/dev/null 2>&1; then return 0; fi
  log "starting dockerd"
  nohup /usr/local/bin/dockerd \
    --host=unix:///var/run/docker.sock \
    --host=tcp://127.0.0.1:2375 \
    --storage-driver=overlay2 \
    >/var/log/dockerd.log 2>&1 &
  timeout 30 sh -c "until docker info >/dev/null 2>&1; do sleep 1; done"
}

ecr_login() {
  aws ecr get-login-password --region "$AWS_DEFAULT_REGION" \
    | docker login --username AWS --password-stdin "$1" >/dev/null
}

pull_cache() {
  docker pull "$1:cache" 2>/dev/null || docker pull "$1:latest" 2>/dev/null \
    || log "no prior image to cache from ($1)"
}

build_image() {
  local url="$1" dockerfile="$2" name="$3"
  log "building $name image ($url:$IMAGE_TAG)"
  DOCKER_BUILDKIT=1 docker build \
    --cache-from "$url:cache" \
    --cache-from "$url:latest" \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    -t "$url:$IMAGE_TAG" -t "$url:latest" -t "$url:cache" \
    -f "$dockerfile" .
}

push_image() {
  docker push "$1:$IMAGE_TAG"
  docker push "$1:latest"
  docker push "$1:cache"
}

update_lambda() {
  local fn="$1" url="$2"
  [[ -n "$fn" ]] || { log "lambda name not set — skipping update"; return 0; }
  if ! aws lambda get-function --function-name "$fn" >/dev/null 2>&1; then
    log "lambda $fn does not exist yet (bootstrap phase?) — skipping update"
    return 0
  fi
  aws lambda update-function-code --function-name "$fn" --image-uri "$url:$IMAGE_TAG" --publish >/dev/null
  aws lambda wait function-updated --function-name "$fn"
  log "lambda $fn updated to $IMAGE_TAG"
}

case "$PHASE" in
  install)
    ensure_dockerd
    if [[ "${BUILD_API:-false}" == "true" ]]; then
      log "installing python deps"
      pip install --cache-dir /root/.cache/pip -r src/api/requirements.txt
    else
      skip "python installs" "no backend changes"
    fi
    if [[ "${BUILD_UI:-false}" == "true" ]]; then
      log "installing UI deps (npm ci)"
      ( cd ui && npm ci --prefer-offline --no-audit --no-fund )
    else
      skip "npm ci" "no UI changes"
    fi
    ;;

  prebuild)
    run_test_gate
    if [[ "${BUILD_TERRAFORM:-false}" == "true" && "$RUN_TERRAFORM_APPLY" == "true" ]]; then
      log "terraform init + apply (prod.tfvars)"
      ( cd terraform && terraform init -input=false -no-color && \
        terraform apply -auto-approve -input=false -no-color -var-file=prod.tfvars )
    else
      skip "terraform" "TERRAFORM=${BUILD_TERRAFORM:-false} APPLY=$RUN_TERRAFORM_APPLY"
    fi
    if [[ "${BUILD_API:-false}" == "true" ]]; then
      ecr_login "$ECR_API_REPOSITORY_URL"
      pull_cache "$ECR_API_REPOSITORY_URL"
    else
      skip "ecr login/pull" "no backend changes"
    fi
    ;;

  build)
    if [[ "${BUILD_API:-false}" == "true" ]]; then
      build_image "$ECR_API_REPOSITORY_URL" "src/api/Dockerfile" api
    else
      skip "api image build" "src/api and src/shared unchanged"
    fi
    if [[ "${BUILD_UI:-false}" == "true" ]]; then
      log "building UI"
      ( cd ui && npm run build )
    else
      skip "UI build" "ui/ unchanged"
    fi
    ;;

  postbuild)
    if [[ "${BUILD_API:-false}" == "true" ]]; then
      push_image "$ECR_API_REPOSITORY_URL"
      update_lambda "$API_LAMBDA_NAME" "$ECR_API_REPOSITORY_URL"
    else
      skip "api push + lambda update" "no api change"
    fi
    if [[ "${BUILD_UI:-false}" == "true" ]]; then
      log "syncing ui/dist → s3://$UI_BUCKET_NAME"
      # Hashed assets: long immutable cache. Entry document: no-cache so deploys
      # take effect immediately.
      aws s3 sync ui/dist/ "s3://$UI_BUCKET_NAME" --delete \
        --exclude "index.html" \
        --cache-control "public,max-age=31536000,immutable"
      aws s3 cp ui/dist/index.html "s3://$UI_BUCKET_NAME/index.html" \
        --cache-control "public,max-age=0,must-revalidate" \
        --content-type "text/html; charset=utf-8"
      aws cloudfront create-invalidation \
        --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
        --paths "/index.html" "/" >/dev/null
    else
      skip "UI deploy" "ui/ unchanged"
    fi
    ;;

  *)
    echo "unknown phase: $PHASE" >&2; exit 2 ;;
esac
