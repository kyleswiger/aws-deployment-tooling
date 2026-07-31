#!/usr/bin/env bash
# Push a placeholder image to the ECR repositories so a container Lambda can be
# created before any real image exists (chicken-and-egg: the Lambda resource
# needs an image; the image needs the pipeline; the pipeline needs the infra).
#
# Runs the build inside AWS CodeBuild, so no local Docker is required. Idempotent.
#
# ADAPT: PREFIX, the -target list, and the REPOS list to your project's resources.
#
# Usage: ./scripts/bootstrap-ecr.sh   (run from repo root; expects terraform/)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/terraform"

PREFIX="${NAME_PREFIX:-myapp-dev}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
BUILD_PROJECT="${PREFIX}-build"
TFVARS="${TFVARS_FILE:-dev.tfvars}"

echo "==> Creating the CodeBuild project + ECR repositories (targeted apply)..."
# Apply only the resources needed to run a build and hold an image. Adjust the
# target list to match your terraform resource names.
terraform apply \
  -target=aws_codebuild_project.main \
  -target=aws_ecr_repository.api_repo \
  -target=aws_iam_role.codebuild_role \
  -target=aws_iam_role_policy.codebuild_policy \
  -target=aws_s3_bucket.artifacts \
  -var-file="$TFVARS" -auto-approve

# Inline buildspec that builds a scratch image and pushes it to each repo.
BUILDSPEC=$(cat <<'SPEC'
version: 0.2
phases:
  build:
    commands:
      - echo "Building scratch placeholder image..."
      - printf 'FROM scratch\nCOPY scratch.Dockerfile /\nCMD [""]\n' > scratch.Dockerfile
      - docker build -t scratch-image -f scratch.Dockerfile .
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $(echo $ECR_API_REPOSITORY_URL | cut -d/ -f1)
      - for REPO_URL in $ECR_API_REPOSITORY_URL; do docker tag scratch-image:latest $REPO_URL:latest && docker push $REPO_URL:latest; done
SPEC
)

echo "==> Starting CodeBuild job to push placeholder image(s)..."
BUILD_ID=$(aws codebuild start-build \
  --project-name "$BUILD_PROJECT" \
  --buildspec-override "$BUILDSPEC" \
  --artifacts-override '{"type": "NO_ARTIFACTS"}' \
  --source-type-override NO_SOURCE \
  --query 'build.id' --output text)

echo "==> Waiting for build $BUILD_ID (~1-2 min)..."
while true; do
  STATUS=$(aws codebuild batch-get-builds --ids "$BUILD_ID" --query 'builds[0].buildStatus' --output text)
  case "$STATUS" in
    SUCCEEDED) echo "==> ECR bootstrap complete — Lambda image(s) now exist."; break ;;
    FAILED|FAULT|STOPPED|TIMED_OUT) echo "==> Build failed: $STATUS" >&2; exit 1 ;;
  esac
  sleep 5
done
