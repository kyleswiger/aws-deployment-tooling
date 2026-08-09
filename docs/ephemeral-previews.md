# Ephemeral PR preview environments

Every pull request gets a **real, browsable preview environment**: its own
frontend URL *and* its own backend Lambda, sharing only the slow/fixed-cost
infrastructure. The design principle: split every environment into **slow
infra** (deployed once by Terraform) and **fast code** (deployed per-PR by CI in
seconds). Per-PR pieces are only things that are free while idle — S3 objects
and Lambda functions — so previews cost ~$0/month fixed.

## Architecture

```
  PR push ─► GitHub Actions (preview-deploy.yml)
               ├─ build backend → create/update Lambda <prefix>-preview-pr-<N>
               │    └─ Function URL (per-PR API endpoint, free while idle)
               ├─ build UI with VITE_API_BASE_URL=<function-url>
               ├─ s3 sync ui/dist → s3://<preview-bucket>/previews/pr-<N>/
               ├─ invalidate /previews/pr-<N>/*
               ├─ comment https://pr-<N>.preview.example.com on the PR
               └─ Playwright e2e against the live preview URL

  https://pr-<N>.preview.example.com
     └─► CloudFront (*.preview.example.com, one distribution)
           └─ viewer-request function: host → /previews/pr-<N>/ prefix
                └─► per-PR bundle → per-PR Lambda → shared preview data tier
```

## The pieces

| Piece | Lives in | Cadence |
|---|---|---|
| `preview-substrate` Terraform module (bucket, wildcard cert, CloudFront + router function, shared Lambda exec role, CI policy statements) | `aws-deployment-tooling/terraform-modules/preview-substrate` | applied once per site |
| `preview-deploy.yml` / `preview-cleanup.yml` reusable workflows | `kyleswiger/aws-reusable-workflows` | called per PR event |
| Thin caller workflow + module instantiation | each app repo | one-time wiring |

## Design choices that matter

- **Host-based routing, not per-PR distributions.** A CloudFront distribution
  takes minutes to create and update; a `s3 sync` takes seconds. One wildcard
  distribution + a viewer-request function mapping `pr-<N>.<domain>` onto the
  `previews/pr-<N>/` prefix means Vite's root-absolute `/assets/…` paths work
  with no `base` config, and the rewritten URI is the cache key so previews
  never bleed into each other.
- **Key previews by PR number, not branch name.** `pr-123` is stable, short,
  and needs no sanitization; branch names collide after stripping (`docs/x` and
  `docsx` map to the same label).
- **Per-PR backend as Lambda + Function URL.** Zero idle cost, creates in
  seconds, no API Gateway needed. Each PR's UI bundle is built with its own
  Function URL baked in, so two open PRs never share a backend. CORS is handled
  in-app with an origin regex (e.g. `https://pr-\d+\.preview\.example\.com`).
- **A dedicated preview bucket, never the prod UI bucket.** Prod deploys that
  `s3 sync --delete` against the bucket root would silently wipe previews; a
  separate bucket also keeps CI's S3 permissions away from prod assets.
- **Previews run the dev auth mode, against a dev data tier.** Point the
  preview Lambda at dev data (a dev logical database on an existing instance, a
  dev DynamoDB table) and enable header/dev auth — this is also exactly what
  backend-dependent Playwright specs need.
- **CI never creates IAM.** The substrate module provisions one shared
  execution role; CI's only IAM permission is `iam:PassRole` on that role, and
  its Lambda permissions are scoped to `<prefix>-preview-pr-*`.
- **Belt-and-braces cleanup.** `preview-cleanup.yml` deletes the Lambda and S3
  prefix on PR close; an S3 lifecycle rule expires `previews/` objects after N
  days in case cleanup never ran. Orphaned Lambdas cost nothing while idle.
- **Fail loudly, not silently.** A deploy that couldn't authenticate to AWS
  must not post a success comment; gate the comment on the sync step actually
  running.

## End-to-end testing

After the preview deploys, the workflow runs Playwright with
`PLAYWRIGHT_BASE_URL=https://pr-<N>.preview.example.com` — real CDN, real
Lambda, real data tier. Because each PR has its own backend, parallel PRs don't
stomp each other's state; specs that need auth use the dev auth mode the
preview backend runs with.

## One-time setup checklist

1. Apply `preview-substrate` in the site's Terraform (choose `preview_domain`,
   pass data-tier statements for the preview Lambda role).
2. Feed `module.preview.ci_policy_statements` into the site's
   `github-oidc-role`; save the role ARN as the `AWS_GITHUB_ACTIONS_ROLE_ARN`
   repo secret.
3. Add thin caller workflows for `preview-deploy.yml` (on
   `pull_request: [opened, synchronize, reopened]`) and `preview-cleanup.yml`
   (on `pull_request: [closed]`) from `kyleswiger/aws-reusable-workflows`.
4. Ensure the backend honors the preview env vars the caller passes (dev auth
   mode, dev data tier, CORS origin regex).
