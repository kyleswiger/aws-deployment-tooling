# AWS Deployment Tooling

Reusable Terraform modules, CI/CD templates, and scripts for shipping
serverless AWS applications — a static SPA on CloudFront, a Cognito-authenticated
API on Lambda, remote Terraform state, and keyless GitHub CI. Distilled from two
production apps into a project-agnostic toolkit.

> New here? Start with **[docs/methodology.md](docs/methodology.md)** — it
> explains the shared architecture and the one axis (Lambda packaging) that
> varies between projects.

## What's inside

```
terraform-modules/   reusable, parameterized Terraform modules
  static-site/          private S3 + CloudFront (OAC) + optional ACM/Route53
  cognito-user-pool/    email-as-username, invite-only pool + SPA client
  http-api-cognito/     API Gateway v2 + Cognito JWT authorizer → Lambda
  github-oidc-role/     keyless GitHub Actions IAM role (OIDC)
  lambda-zip/           zip-packaged Lambda + role + logs
  lambda-container/     image (ECR) Lambda + repo + role, optional VPC

templates/           copy-paste-and-fill CI/CD boilerplate
  buildspec/            CodeBuild buildspecs (app + runner image)
  github-workflows/     pr-preview, pr-cleanup, deploy-dev-api
  docker/               CodeBuild runner + Python Lambda Dockerfiles
  gitignore.template    baseline .gitignore

scripts/             automation
  bootstrap-state.sh    create the S3+DynamoDB remote-state backend
  bootstrap-ecr.sh      push a placeholder image so a container Lambda can boot
  deploy.sh             profile-driven full deploy (build→apply→sync→invalidate)
  detect-changes.sh     emit BUILD_* flags for change-aware CI
  run-ci.sh             per-phase CodeBuild orchestrator

examples/            complete, wired-together reference stacks
  lightweight-zip-stack/   SPA + Cognito + zip Lambda, profile-driven deploy.sh
  container-cicd-stack/    SPA + Cognito + container Lambda + GitHub OIDC CI

docs/                the methodology, in prose
  methodology.md · remote-state.md · github-oidc.md
  change-aware-ci.md · ephemeral-previews.md

skills/              custom development skills (skill-creator)
```

New to the modules? The [`examples/`](examples) directory has two runnable roots
that wire everything together — `terraform init && terraform plan` against your
own account to see the whole stack before adopting a piece of it.

## The architecture in one picture

```
        Route 53  ──►  CloudFront  ──►  S3 (private, OAC)      static SPA
                            │
   browser ──► Cognito (JWT) ──► API Gateway v2 ──► Lambda ──► data store
```

Every project shares this spine. The only real decision is how the backend is
packaged:

- **Small handler?** `lambda-zip` + the profile-driven [`deploy.sh`](scripts/deploy.sh).
- **Heavy/native deps, PR previews, multiple services?** `lambda-container` +
  change-aware [CodePipeline](docs/change-aware-ci.md).

See the [methodology](docs/methodology.md) for the full decision guide.

## Quick start (lightweight path)

```hcl
# infra/main.tf — us-east-1 (CloudFront ACM certs must live there)
module "site" {
  source        = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/static-site"
  name_prefix   = "myapp"
  custom_domain = "app.example.com"
  hosted_zone_id = "Z0123456789ABCDEF"
}

module "auth" {
  source           = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/cognito-user-pool"
  name_prefix      = "myapp"
  app_display_name = "My App"
}

module "api_lambda" {
  source        = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/lambda-zip"
  function_name = "myapp-api"
  zip_path      = "${path.module}/../backend/dist/api.zip"
  runtime       = "nodejs22.x"
  environment   = { USER_POOL_ID = module.auth.user_pool_id }
}

module "api" {
  source               = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/http-api-cognito"
  name_prefix          = "myapp"
  lambda_function_name = module.api_lambda.function_name
  lambda_invoke_arn    = module.api_lambda.invoke_arn
  cognito_issuer       = module.auth.issuer
  cognito_audience     = module.auth.user_pool_client_id
  cors_allow_origins   = [module.site.site_url, "http://localhost:5173"]
}
```

```bash
# 1. Create remote state (once per account)
./scripts/bootstrap-state.sh myapp-tfstate us-east-1

# 2. Copy scripts/deploy.sh + templates/gitignore.template into your repo,
#    create a profile dir with terraform.tfvars (+ optional backend.hcl), then:
./deploy.sh --profile ../myapp-profile
```

Each module's README documents its full inputs and outputs. The `scripts/` and
`templates/` files carry `<PLACEHOLDER>` tokens and adapt-me comments where you
plug in your project's names.

## Design principles

- **Least privilege** — CI roles get exactly the actions they need, ARN-scoped.
- **No secrets in state or git** — SSM Parameter Store, read at runtime.
- **Cost discipline** — no NAT/VPC endpoints unless required; edge JWT over
  authorizer Lambdas; CloudFront `PriceClass_100`; concurrency caps on Lambdas.
- **Auditable builds** — change-aware CI logs every skipped stage.
- **Keyless CI** — GitHub OIDC, never a stored AWS key.

## Provenance

These patterns are generalized from `sportscard-intelligence` (container-Lambda,
CodePipeline, PR previews) and `cabin-management` (zip-Lambda, profile-driven
`deploy.sh`). Project-specific names have been replaced with variables and
placeholders; the modules are validated with `terraform validate` and the scripts
with `bash -n`.
