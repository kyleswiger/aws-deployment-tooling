# Example: ECS Fargate service with GitHub OIDC CI

The long-running-container path: one HTTP container on **ECS Fargate** behind
an ALB with TLS, plus a **keyless GitHub Actions role**. Reach for this when the
app needs WebSockets, a persistent VM (Phoenix/BEAM, JVM), or connections that
outlive a Lambda invocation.

**Terraform owns infrastructure and a task-definition template; CI owns the
entire running revision.** The service ignores `task_definition` drift, so
`terraform apply` never fights the revision CI just deployed, but also cannot
roll out task-template changes by itself.

```
Route53 ─► ALB (ACM TLS, :80→:443) ─► Fargate task ─► CloudWatch Logs   module.app
GitHub Actions ─(OIDC)─► IAM role ─► ECR push + register-task-definition + update-service   module.ci_role
```

## Modules used

| Module | Role |
|---|---|
| [`ecs-fargate-service`](../../terraform-modules/ecs-fargate-service) | ECR + cluster + task def + service + ALB + cert; `ignore_changes = [task_definition]`. |
| [`github-oidc-role`](../../terraform-modules/github-oidc-role) | Keyless CI role fed by the service's `ci_policy_statements` output. |

## First-time setup order

Because the service is created from an image that doesn't exist yet, bootstrap
in this order:

```bash
cp terraform.tfvars.example terraform.tfvars   # then edit
terraform init

# 1. Create just the ECR repo — the service can't become healthy until its
#    image exists, so the repo has to come first.
terraform apply -target='module.app.aws_ecr_repository.this[0]'
REPO_URL=$(terraform state show 'module.app.aws_ecr_repository.this[0]' \
             | awk '/repository_url/{print $3; exit}' | tr -d '"')

# 2. Build and push the real image (arm64 to match the module default).
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin "${REPO_URL%%/*}"
docker buildx build --platform linux/arm64 -t "$REPO_URL:latest" --push .

# 3. Now create everything else.
terraform apply
terraform output -raw url

# 4. Wire CI: save the role ARN and let GitHub take over deploys.
terraform output -raw github_actions_role_arn
#   → set as repo secret AWS_GITHUB_ACTIONS_ROLE_ARN
```

From then on, pushes to `main` build and push a new image, register a
task-definition revision with it, and call `ecs update-service` — Terraform is
only re-run when *infrastructure* changes.

## Task-definition handoff

After reviewing and applying a consumer plan that changes environment, secret
references, CPU/memory, command, or task roles, read the root
`task_definition_arn` output and pass it as the optional `task-definition-arn`
input to a reviewed reusable ECS deploy workflow version that supports it:

```bash
terraform output -raw task_definition_arn
```

That ARN selects the Terraform template for the next CI rollout. CI substitutes
the built image while preserving the template's other settings. Empty/omitted
input keeps ordinary image-only deployments based on the running revision;
such deployments **do not** adopt Terraform task-template changes.

Rollback must use the actual service revision captured before the deploy, not
this Terraform output. Verify steady state, `/healthz`, and WebSocket behavior
after deployment. See the module's
[ownership contract](../../terraform-modules/ecs-fargate-service#adopting-task-definition-changes)
for the approval and rollback sequence. No workflow is installed by this
example; wire and pin the consumer workflow separately.

## Notes

- **Cheapest network posture by default.** Default VPC, public subnets, public
  IP on the task; no NAT gateway, no VPC endpoints. The task SG only admits the
  ALB. Pass `vpc_id` / `subnet_ids` to the module for a production VPC.
- **Cost floor ≈ $27–35/mo** — the ALB (~$16 + LCU) dominates; the 0.25 vCPU
  Spot task is ~$3. If that's too much, the app belongs on Lambda.
- **The certificate is regional**, so any provider region works; there is no
  us-east-1 requirement like CloudFront's.
- **Trust includes `environment:production`.** Gate the production deploy job
  behind a GitHub Environment with required reviewers and only that job can
  assume the role for the prod stack — see
  [`docs/github-oidc.md`](../../docs/github-oidc.md).
- **`create_oidc_provider = false`** assumes the account already registered
  `token.actions.githubusercontent.com` (e.g. via `container-cicd-stack`). Flip
  it for a fresh account.
