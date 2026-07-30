# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **toolkit, not an application**. Nothing here is deployed from this repo — the
Terraform modules, buildspecs, workflows, and scripts are copied or sourced into
other projects. Files carry `<PLACEHOLDER>` tokens and `ADAPT:` comments marking
where a consuming project fills in its own names. Preserve that convention: new
content must stay project-agnostic (no real domains, account IDs, or app names).

`docs/methodology.md` is the conceptual entry point and explains why the pieces
fit together; read it before making structural changes.

## Verification commands

There is no build or test suite. Changes are verified with:

```bash
terraform fmt -check -recursive          # run from repo root; must pass clean
bash -n scripts/*.sh                     # shell syntax check

# Validate a single module or example (offline, no credentials needed):
cd terraform-modules/static-site && terraform init -backend=false && terraform validate

# Plan a full example against a real account:
cd examples/lightweight-zip-stack && cp terraform.tfvars.example terraform.tfvars \
  && terraform init && terraform plan
```

The repo has **no `.gitignore`** (`templates/gitignore.template` is for consumer
projects), so `terraform init` leaves untracked `.terraform/` and
`.terraform.lock.hcl` behind — delete them after validating.

## Architecture

Every project built with this toolkit shares one spine, assembled from six
modules in `terraform-modules/`:

```
Route 53 → CloudFront → S3 (private, OAC)          ← static-site
browser → Cognito (JWT) → API Gateway v2 → Lambda  ← cognito-user-pool,
                                                     http-api-cognito,
                                                     lambda-zip | lambda-container
```

**The only axis that varies is Lambda packaging**, and it determines the whole
deployment driver:

| | zip Lambda | container Lambda |
|---|---|---|
| Module | `lambda-zip` | `lambda-container` |
| Who owns function code | Terraform (`source_code_hash` on the zip) | CI (`lambda update-function-code`); the module sets `lifecycle { ignore_changes = [image_uri] }` |
| Driver | `scripts/deploy.sh` | `scripts/detect-changes.sh` + `scripts/run-ci.sh` under CodeBuild, or `templates/github-workflows/` |
| Reference root | `examples/lightweight-zip-stack` | `examples/container-cicd-stack` |

The two `examples/` roots are the canonical wiring of the modules and the
fastest way to see intended usage; keep them in sync when a module's interface
changes.

### Conventions baked into the modules

- All modules pin `required_version >= 1.5` / `aws >= 5.0` in `versions.tf`, take
  a `name_prefix`, and ship a README documenting every input and output.
- Examples pin the provider to **us-east-1** — CloudFront's ACM cert must live
  there and `static-site` creates the cert with the root's default provider.
- IAM is granted through a `policy_statements` list variable (sid/effect/actions/
  resources) rather than baked-in policies, so consumers stay ARN-scoped and
  least-privilege. `github-oidc-role` works the same way and has a
  `create_oidc_provider` toggle because an account may only register the GitHub
  provider once.
- `http-api-cognito` uses a `{proxy+}` route with payload format 2.0 and an
  edge-validated Cognito JWT authorizer — no authorizer Lambda.
- Secrets never go in Terraform state or tfvars; use SSM Parameter Store.

### The profile pattern (`scripts/deploy.sh`)

Environment-specific values live in a **profile directory outside the repo**
(`terraform.tfvars`, optional `backend.hcl`, `app.config.json`, `public/`). The
script generates `infra/backend.tf` from the profile because a Terraform backend
block can't take variables, and it hard-fails if a non-empty local
`terraform.tfstate` exists while `backend.hcl` selects remote state — migrating
silently would orphan deployed resources. Keep that guard if you touch the
script.

### Change-aware CI (`detect-changes.sh` → `run-ci.sh`)

`detect-changes.sh` diffs HEAD against a baseline (PR target branch →
`CODEBUILD_WEBHOOK_PREV_COMMIT` → `HEAD~1`, falling back to a **full** build if
no usable history) and writes `BUILD_UI` / `BUILD_API` / `BUILD_TERRAFORM` / …
to `change-flags.env`. `run-ci.sh <install|prebuild|build|postbuild>` sources
those flags and runs only the changed components. Two invariants when editing:
every skipped stage must print *why* (a green build has to be auditable), and
any ambiguity resolves toward a full build, never a partial one.

Frontend sync headers are deliberate: hashed assets get
`max-age=31536000,immutable`, `index.html` gets `must-revalidate`, and only
`/index.html` and `/` are invalidated.

## Writing style

Modules and scripts carry comments explaining *why* a non-obvious choice was
made (region pinning, `ignore_changes`, state-migration guard, cache headers).
Match that density — this repo is read as documentation as much as it is
executed.
