# Example: container-Lambda stack with change-aware CI

The full-weight path: a static SPA, Cognito, and an **image-packaged** API
Lambda (ECR), plus a **keyless GitHub Actions role**. Reach for this when the
backend has native or heavy dependencies, when you want per-PR previews, or when
several services share a monorepo.

The dividing principle: **Terraform owns infrastructure; CI owns code.** The
Lambda module ignores `image_uri` drift, so `terraform apply` never fights the
image CI pushes.

```
Route53 ─► CloudFront ─► S3 (private, OAC)                module.site
browser ─► Cognito JWT ─► API Gateway v2 ─► Lambda(image) module.auth / module.api / module.api_lambda
                                              └─► DynamoDB  aws_dynamodb_table.app
GitHub Actions ─(OIDC)─► IAM role ─► ECR push + update-function-code  module.ci_role
```

## Modules used

| Module | Role |
|---|---|
| [`static-site`](../../terraform-modules/static-site) | Private S3 + CloudFront (OAC), optional ACM + Route53. |
| [`cognito-user-pool`](../../terraform-modules/cognito-user-pool) | Invite-only pool + SPA client. |
| [`lambda-container`](../../terraform-modules/lambda-container) | Image Lambda + ECR repo + role; `ignore_changes = [image_uri]`. |
| [`http-api-cognito`](../../terraform-modules/http-api-cognito) | API Gateway v2 + Cognito JWT authorizer → the Lambda. |
| [`github-oidc-role`](../../terraform-modules/github-oidc-role) | Keyless CI role, ARN-scoped to exactly this stack's resources. |

Plus a `aws_dynamodb_table` created inline to show how to grant the Lambda
least-privilege data access via `policy_statements`.

## First-time setup order

Because the Lambda is created from an image that doesn't exist yet, and CI needs
a role that doesn't exist yet, bootstrap in this order:

```bash
cp terraform.tfvars.example terraform.tfvars   # then edit
terraform init

# 1. Create just the ECR repo — the Lambda can't be created until its image
#    exists, so the repo has to come first.
terraform apply -target='module.api_lambda.aws_ecr_repository.this[0]'
REPO_URL=$(terraform state show 'module.api_lambda.aws_ecr_repository.this[0]' \
             | awk '/repository_url/{print $3; exit}' | tr -d '"')

# 2. Push one placeholder image so the Lambda has something to boot from.
#    With local Docker:
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin "${REPO_URL%%/*}"
printf 'FROM public.ecr.aws/lambda/nodejs:22\nCMD ["index.handler"]\n' \
  | docker build -t "$REPO_URL:latest" -f - . && docker push "$REPO_URL:latest"
#    No local Docker? Adapt scripts/bootstrap-ecr.sh — it runs the same push
#    inside CodeBuild — to this stack's repo/targets.

# 3. Now create everything else.
terraform apply

# 4. Wire CI: save the role ARN and let GitHub take over deploys.
terraform output -raw github_actions_role_arn
#   → set as repo secret AWS_GITHUB_ACTIONS_ROLE_ARN
```

From then on, pushes to `main` build and push a new image and call
`lambda update-function-code` — Terraform is only re-run when *infrastructure*
changes.

## Wire up CI

1. Copy the workflow templates you need from
   the GitHub Actions from `kyleswiger/aws-reusable-workflows` into your
   app repo's `.github/workflows/` and replace the `<PLACEHOLDER>` tokens
   (`<NAME_PREFIX>`, `<API_REPO>`, `<DEV_API_URL>`, `<DEV_UI_BUCKET>`,
   `<PREVIEW_DOMAIN>`) with this stack's outputs.
2. Copy [`templates/buildspec`](../../templates/buildspec) and
   [`scripts/detect-changes.sh`](../../scripts/detect-changes.sh) +
   [`scripts/run-ci.sh`](../../scripts/run-ci.sh) if you drive builds through
   CodePipeline/CodeBuild. See [`docs/change-aware-ci.md`](../../docs/change-aware-ci.md).
3. For per-PR frontend previews on top of this, see
   [`docs/ephemeral-previews.md`](../../docs/ephemeral-previews.md).

## Notes

- **The OIDC provider is account-global.** `create_oidc_provider = true` here
  registers `token.actions.githubusercontent.com`. If another stack already did,
  set it `false` and the module looks the provider up.
- **Scope the role tighter for prod.** The default trust is main + any PR. Pin
  `subject_claims` to a GitHub Environment so only a gated deploy can assume it —
  see [`docs/github-oidc.md`](../../docs/github-oidc.md).
- **The DynamoDB table is illustrative.** Swap in whatever data store you need;
  the pattern — create it here, grant the Lambda via `policy_statements` — holds.
