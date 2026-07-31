# Deployment methodology

This toolkit distills the patterns behind two production AWS applications into
reusable Terraform modules, CI/CD templates, and scripts. Both apps are
serverless, single-account, single-developer-friendly, and cost-conscious. They
share a spine and diverge in exactly one axis: **how the backend is packaged and
deployed.**

## The shared spine

Every project built this way has the same shape:

```
        Route 53  ──►  CloudFront  ──►  S3 (private, OAC)      static SPA
                            │
   browser ──► Cognito (JWT) ──► API Gateway ──► Lambda ──► data store
```

- **Static SPA** on a private S3 bucket, served only through CloudFront via an
  Origin Access Control. → [`static-site`](../terraform-modules/static-site)
- **Auth** via a Cognito user pool (email-as-username, invite-only by default)
  with a public SPA client. → [`cognito-user-pool`](../terraform-modules/cognito-user-pool)
- **API** behind a Cognito JWT authorizer (validated at the edge, no authorizer
  Lambda). → [`http-api-cognito`](../terraform-modules/http-api-cognito)
- **Custom domains** via DNS-validated ACM certs in `us-east-1` + Route 53
  aliases (built into `static-site`).
- **Remote state** in a versioned, encrypted, TLS-only S3 bucket with a DynamoDB
  lock table. → [`bootstrap-state.sh`](../scripts/bootstrap-state.sh)
- **Keyless CI** — GitHub Actions assumes an IAM role via OIDC; no static keys.
  → [`github-oidc-role`](../terraform-modules/github-oidc-role)

## The one axis that varies: backend packaging

| | **Zip Lambda** | **Container Lambda** |
|---|---|---|
| Module | [`lambda-zip`](../terraform-modules/lambda-zip) | [`lambda-container`](../terraform-modules/lambda-container) |
| Best for | small Node/Python handlers | large or native deps (ML, headless browsers) |
| Artifact | `.zip` built locally / in CI | OCI image in ECR |
| Deploy driver | `deploy.sh` (Terraform owns code via `source_code_hash`) | CI `update-function-code` (Terraform ignores `image_uri`) |
| Complexity | one script, optional CodeBuild | CodePipeline + CodeBuild + ECR |

Pick the lightest one that fits. Reach for containers only when a zip can't hold
the dependencies.

## Two deployment drivers

### 1. Profile-driven `deploy.sh` (lightweight)

One script does the whole deploy: build backend → `terraform apply` → build
frontend → `s3 sync` → CloudFront invalidation. All environment-specific values
live in a **profile directory kept outside the repo** (gitignored), so the repo
carries no domains, account IDs, or state. See
[`deploy.sh`](../scripts/deploy.sh) and [remote-state.md](remote-state.md).

Good for: small teams, few environments, fast iteration.

### 2. Change-aware CodePipeline (heavier)

A CodePipeline sources from GitHub and runs CodeBuild against
[`buildspec.yml`](../templates/buildspec/buildspec.yml). A
[`detect-changes.sh`](../scripts/detect-changes.sh) step diffs the commit and
emits `BUILD_*` flags so [`run-ci.sh`](../scripts/run-ci.sh) only builds, tests,
and deploys the components that actually changed. Images are tagged with the
commit SHA plus moving `:latest`/`:cache` tags for caching and rollback.

Good for: container backends, multiple components, per-PR previews, auditability.
See [change-aware-ci.md](change-aware-ci.md) and
[ephemeral-previews.md](ephemeral-previews.md).

## Cross-cutting principles

- **Least privilege, always.** CI roles get exactly the S3/ECR/Lambda/CloudFront
  actions they need, scoped to specific ARNs (see `github-oidc-role` usage).
- **Secrets never in Terraform state or git.** Use SSM Parameter Store
  (SecureString) and read at runtime, or CodeBuild `PARAMETER_STORE` env vars.
- **Cost discipline.** No NAT gateways or VPC endpoints unless a resource truly
  needs VPC egress; prefer edge-validated JWT over authorizer Lambdas; set Lambda
  reserved concurrency so a burst can't exhaust a small database's connections;
  CloudFront `PriceClass_100` by default.
- **Immutable frontend caching.** Hashed assets get `max-age=31536000,immutable`;
  the entry document (`index.html`) gets `no-cache` so deploys land immediately.
- **Everything skippable prints why.** Change-aware builds log every skipped
  stage so a green build is auditable, not mysterious.

## Choosing a starting point

- **Simple CRUD app, one or two environments** → zip Lambda + `deploy.sh`
  (model on `cabin-management`).
- **Backend with heavy deps, PR previews, multiple services** → container Lambda
  + CodePipeline (model on `sportscard-intelligence`).

Both use the same `static-site`, `cognito-user-pool`, `http-api-cognito`,
`github-oidc-role`, and `bootstrap-state.sh` — only the Lambda module and
deployment driver change.
