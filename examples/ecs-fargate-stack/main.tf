# ECS Fargate stack with GitHub OIDC CI
# --------------------------------------
# One long-running HTTP container (Phoenix/LiveView-shaped defaults) on Fargate
# behind an ALB, plus a keyless GitHub Actions role. Terraform owns the shape;
# CI owns the running image — it pushes to ECR, registers a task-definition
# revision, and calls `ecs update-service`, so the service ignores
# task_definition drift. See ../../docs/methodology.md "Long-running containers".

# 1. The service. Default VPC + public subnets + a public IP on the task: the
#    cheapest posture (no NAT, no endpoints). FARGATE_SPOT is fine for a
#    dev/staging app; switch to FARGATE where an interruption would page you.
#    First apply needs the ECR repo + a real image first — see README.
module "app" {
  source = "../../terraform-modules/ecs-fargate-service"

  name_prefix    = var.name_prefix
  custom_domain  = var.custom_domain
  hosted_zone_id = var.hosted_zone_id

  cpu               = 256
  memory            = 512
  capacity_provider = "FARGATE_SPOT"

  environment = {
    PHX_HOST = var.custom_domain != "" ? var.custom_domain : "localhost"
    PORT     = "4000"
  }

  # Resolved at task start by the execution role; values never enter state.
  # secrets = {
  #   SECRET_KEY_BASE = "arn:aws:ssm:us-east-1:123456789012:parameter/${var.name_prefix}/secret_key_base"
  #   DATABASE_URL    = "arn:aws:ssm:us-east-1:123456789012:parameter/${var.name_prefix}/database_url"
  # }

  # Runtime permissions for the app itself (task role). Empty here; grant the
  # data tier the same way container-cicd-stack grants its DynamoDB table.
  policy_statements = []
}

# 2. Keyless CI role. Permissions are exactly what the deploy workflow needs
#    (ECR push, register revision, update-service, pass roles, read logs),
#    ARN-scoped by the module. Trust covers main, PRs, and the "production"
#    GitHub Environment so a gated deploy job can assume it too.
module "ci_role" {
  source = "../../terraform-modules/github-oidc-role"

  name_prefix = "${var.name_prefix}-deploy"
  github_repo = var.github_repo

  # One OIDC provider per account. Set true only if
  # token.actions.githubusercontent.com is not registered yet.
  create_oidc_provider = false

  subject_claims = [
    "repo:${var.github_repo}:ref:refs/heads/main",
    "repo:${var.github_repo}:pull_request",
    "repo:${var.github_repo}:environment:production",
  ]

  policy_statements = module.app.ci_policy_statements
}
