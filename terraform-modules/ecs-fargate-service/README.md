# `ecs-fargate-service` module

One long-running HTTP container on ECS Fargate behind an internet-facing ALB
with ACM TLS. Creates the ECR repository, cluster, task definition, service,
security groups, target group + listeners, log group, execution and task roles,
and — when a domain is given — a regional certificate plus Route 53 aliases.

Use it for anything a Lambda can't be: WebSockets, a persistent BEAM/JVM,
long-lived connections, background schedulers inside the app process. Written
with Phoenix/LiveView in mind (port 4000, `/healthz`, a 120 s idle timeout for
the LiveView socket) but nothing is Elixir-specific. For request/response APIs,
[`lambda-zip`](../lambda-zip) or [`lambda-container`](../lambda-container) are
cheaper; see [docs/methodology.md](../../docs/methodology.md).

## Deploy model (important)

Terraform owns the **shape**; CI owns the **running image**:

1. Terraform registers a task definition pointing at `<repo>:<image_tag>` and
   creates the cluster, service, ALB, roles, and log group.
2. CI builds and pushes the image, renders a new task-definition revision with
   the built tag (`aws ecs register-task-definition`), and calls
   `aws ecs update-service`. The circuit breaker rolls back a revision whose
   tasks never become healthy.

The service's `task_definition` (and `desired_count`) are under
`ignore_changes`, so routine `terraform apply` runs never revert what CI just
deployed — the same split as `lambda-container`'s `ignore_changes = [image_uri]`.
The `ci_policy_statements` output grants a CI role exactly those actions.

## Usage

```hcl
module "app" {
  source      = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/ecs-fargate-service"
  name_prefix = "myapp"

  custom_domain  = "app.example.com"
  hosted_zone_id = "Z0123456789ABCDEF"

  cpu               = 256
  memory            = 512
  capacity_provider = "FARGATE_SPOT"

  environment = {
    PHX_HOST = "app.example.com"
    PORT     = "4000"
  }

  # Resolved by the execution role at task start; never in state.
  secrets = {
    SECRET_KEY_BASE = "arn:aws:ssm:us-east-1:123456789012:parameter/myapp/secret_key_base"
    DATABASE_URL    = "arn:aws:ssm:us-east-1:123456789012:parameter/myapp/database_url"
  }

  # Runtime permissions for the app itself (task role).
  policy_statements = [
    {
      sid       = "Uploads"
      actions   = ["s3:PutObject", "s3:GetObject"]
      resources = ["arn:aws:s3:::myapp-uploads/*"]
    },
  ]
}

module "ci_role" {
  source      = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/github-oidc-role"
  name_prefix = "myapp-deploy"
  github_repo = "kyleswiger/myapp"

  policy_statements = module.app.ci_policy_statements
}
```

## First deploy (chicken-and-egg)

The service can't reach a steady state until a real image exists in the repo,
so create the repo first, push, then apply the rest:

```bash
terraform init

# 1. Just the ECR repo.
terraform apply -target='module.app.aws_ecr_repository.this[0]'
REPO_URL=$(terraform state show 'module.app.aws_ecr_repository.this[0]' \
             | awk '/repository_url/{print $3; exit}' | tr -d '"')

# 2. Build and push the real image (arm64 to match the default architecture).
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin "${REPO_URL%%/*}"
docker buildx build --platform linux/arm64 -t "$REPO_URL:latest" --push .

# 3. Everything else. The service pulls :latest and the ALB starts probing
#    health_check_path once health_check_grace_period_seconds has elapsed.
terraform apply
```

If you apply before the image exists, nothing breaks — the service just cycles
tasks (and the circuit breaker trips) until CI pushes one and calls
`update-service`.

## Design notes

- **Network posture is the cheapest possible, on purpose.** With no `vpc_id` /
  `subnet_ids`, the module uses the account's default VPC and every subnet
  flagged `map-public-ip-on-launch`, and gives the task a public IP
  (`assign_public_ip = true`). A task in a *private* subnet still needs to reach
  ECR, CloudWatch Logs, and SSM, which costs a NAT gateway (~$33/mo) or three
  interface endpoints (~$22/mo); a public IPv4 costs $3.65/mo, and the task SG
  admits only the ALB. A production caller passes its own subnets and flips
  `assign_public_ip` off. No NAT, no endpoints are ever created here.
- **The certificate is regional.** ALB certs live in the ALB's own region, so
  there is no `us-east-1` provider alias to configure — unlike
  [`static-site`](../static-site), whose CloudFront cert must be in us-east-1.
  Set `custom_domain` + `hosted_zone_id` and the module issues a DNS-validated
  cert, waits for validation, attaches the 443 listener, redirects 80 → 443,
  and writes A + AAAA aliases. Leave both empty and the ALB serves plain HTTP on
  its DNS name (`url` output) — useful for a first smoke test.
- **Cost floor.** 0.25 vCPU / 512 MiB on FARGATE_SPOT (~$3/mo) or on-demand
  (~$9/mo) + ALB (~$16/mo + LCU) + public IPv4 for task and ALB (~$7/mo)
  ≈ $27–35/mo. The ALB is the floor; if that's too much for a hobby app, a
  Lambda is the answer, not a smaller task.
- **Rollouts.** `deployment_minimum_healthy_percent = 100 / maximum = 200`
  brings the new task up next to the old one; `deregistration_delay = 15`
  (AWS default is 300) so the old task drains quickly; LiveView sockets
  reconnect on their own. Bump `health_check_grace_period_seconds` if the app
  runs migrations on boot.
- **ECS Exec is on by default** (`enable_execute_command`): `aws ecs
  execute-command --cluster myapp --task <id> --container app --interactive
  --command "bin/myapp remote"` gives you an IEx shell without SSH or a bastion.
  It costs nothing; the task role gets the `ssmmessages:*Channel` statement and
  the container runs with `initProcessEnabled`.
- **Secrets stay out of state.** `secrets` maps env var names to SSM/Secrets
  Manager ARNs; the *execution* role gets `ssm:GetParameters` /
  `secretsmanager:GetSecretValue` on exactly those ARNs plus `kms:Decrypt`
  scoped by `kms:ViaService`, and ECS injects the values at task start.
- **ARM64 by default.** Graviton is ~20% cheaper per vCPU-hour and BEAM builds
  for it natively. Build with `--platform linux/arm64` or set
  `architecture = "X86_64"`.
- **No container health check.** The target group already probes
  `health_check_path`; a second in-container probe only adds noise.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | string | — | Prefix for every resource; also the cluster/service/family name. |
| `custom_domain` | string | `""` | Domain to serve on. Empty = plain HTTP on the ALB DNS name. |
| `hosted_zone_id` | string | `""` | Route 53 zone owning `custom_domain`. Required with it. |
| `create_ecr_repository` | bool | `true` | Create the repo vs. reuse `image_repository_url`. |
| `ecr_repository_name` | string | `""` | Repo name; defaults to `<name_prefix>-repo`. |
| `image_repository_url` | string | `""` | Existing repo URL when not creating one. |
| `image_tag` | string | `"latest"` | Tag baked into the Terraform-registered revision. |
| `ecr_image_scan_on_push` | bool | `true` | ECR basic scanning on push. |
| `container_name` | string | `"app"` | Container name in the task definition. |
| `container_port` | number | `4000` | Port the app listens on. |
| `cpu` | number | `256` | Task CPU units. |
| `memory` | number | `512` | Task memory (MiB). |
| `architecture` | string | `"ARM64"` | `ARM64` or `X86_64`. |
| `command` | list(string) | `null` | Override the image CMD. |
| `environment` | map(string) | `{}` | Plain env vars. |
| `secrets` | map(string) | `{}` | Env var → SSM/Secrets Manager ARN, resolved at task start. |
| `desired_count` | number | `1` | Task count (under `ignore_changes`). |
| `capacity_provider` | string | `"FARGATE"` | `FARGATE` or `FARGATE_SPOT`. |
| `health_check_grace_period_seconds` | number | `60` | Boot time before ALB checks count. |
| `enable_execute_command` | bool | `true` | ECS Exec shell access. |
| `container_insights` | bool | `false` | Cluster Container Insights (billed per metric). |
| `log_retention_days` | number | `30` | Log group retention. |
| `health_check_path` | string | `"/healthz"` | Target group probe path (must 200 unauthenticated). |
| `alb_idle_timeout` | number | `120` | ALB idle timeout (s); bounds idle WebSockets. |
| `deregistration_delay` | number | `15` | Drain time (s) for the old task on rollout. |
| `vpc_id` | string | `""` | VPC; empty = the default VPC. |
| `subnet_ids` | list(string) | `[]` | Subnets; empty = the VPC's public subnets. |
| `assign_public_ip` | bool | `true` | Public IP on tasks (avoids NAT/endpoints). |
| `policy_statements` | list(object) | `[]` | Runtime IAM for the app (task role). |
| `tags` | map(string) | `{}` | Tags on taggable resources. |

## Outputs

`cluster_name`, `cluster_arn`, `service_name`, `service_arn`,
`task_definition_family`, `task_definition_arn`, `container_name`,
`ecr_repository_url`, `ecr_repository_arn`, `alb_arn`, `alb_dns_name`,
`alb_zone_id`, `target_group_arn`, `url`, `task_role_arn`, `task_role_name`,
`task_execution_role_arn`, `log_group_name`, and `ci_policy_statements` — a
list shaped for `github-oidc-role`'s `policy_statements` input granting ECR
push, `RegisterTaskDefinition`, `UpdateService` on this service, `RunTask` on
this family, `iam:PassRole` on both task roles, and `logs:GetLogEvents` on the
log group.
