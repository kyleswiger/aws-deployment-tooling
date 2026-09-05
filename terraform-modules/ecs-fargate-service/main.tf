# One long-running HTTP container on ECS Fargate behind an internet-facing ALB
# with ACM TLS: ECR repo, cluster, task definition, service, security groups,
# target group + listeners, log group, execution/task roles, and optional
# cert + Route 53 alias. Written with Phoenix/BEAM in mind (WebSockets, a
# persistent VM) but nothing here is Elixir-specific.
#
# Deploy model: Terraform owns the *shape* — cluster, service, ALB, roles, and
# the task definition's resources/env/secrets. CI owns the *running image*: it
# pushes to ECR, registers a new task-definition revision with the built tag,
# and calls `ecs update-service`. The service's task_definition is therefore
# under ignore_changes (same idea as lambda-container's ignore_changes on
# image_uri). The ci_policy_statements output grants exactly that.
#
# Network posture (deliberate, cheapest): the account's default VPC, its public
# subnets, and a public IP on the task. See variables.tf `assign_public_ip`.

data "aws_caller_identity" "current" {}

# --------------------------------------------------------------------------- #
# Network discovery: default VPC + public subnets unless the caller passes its own.
# --------------------------------------------------------------------------- #
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

data "aws_subnets" "public" {
  count = length(var.subnet_ids) == 0 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

locals {
  vpc_id     = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.public[0].ids

  repo_name = var.ecr_repository_name != "" ? var.ecr_repository_name : "${var.name_prefix}-repo"
  repo_url  = var.create_ecr_repository ? aws_ecr_repository.this[0].repository_url : var.image_repository_url

  use_custom_domain = var.custom_domain != "" && var.hosted_zone_id != ""

  # Region comes from an ARN rather than data.aws_region, whose .name/.region
  # attribute split across provider 5.x/6.x would otherwise force a version pin.
  region     = split(":", aws_ecs_cluster.this.arn)[3]
  account_id = data.aws_caller_identity.current.account_id

  # Task-definition ARNs carry a revision suffix; CI needs every revision of the family.
  task_definition_family_arn = "arn:aws:ecs:${local.region}:${local.account_id}:task-definition/${var.name_prefix}:*"

  # Container definitions want a list of {name, value}; sort for a stable plan.
  container_environment = [
    for k in sort(keys(var.environment)) : { name = k, value = var.environment[k] }
  ]
  container_secrets = [
    for k in sort(keys(var.secrets)) : { name = k, valueFrom = var.secrets[k] }
  ]
}

# --------------------------------------------------------------------------- #
# ECR
# --------------------------------------------------------------------------- #
resource "aws_ecr_repository" "this" {
  count                = var.create_ecr_repository ? 1 : 0
  name                 = local.repo_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags                 = var.tags

  image_scanning_configuration {
    scan_on_push = var.ecr_image_scan_on_push
  }
}

# Keep the repo from growing without bound: expire untagged layers.
resource "aws_ecr_lifecycle_policy" "this" {
  count      = var.create_ecr_repository ? 1 : 0
  repository = aws_ecr_repository.this[0].name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after 14 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = { type = "expire" }
    }]
  })
}

# --------------------------------------------------------------------------- #
# Cluster + logs
# --------------------------------------------------------------------------- #
resource "aws_ecs_cluster" "this" {
  name = var.name_prefix
  tags = var.tags

  # Container Insights bills per metric; the ALB + service metrics cover a
  # single-service cluster fine. Off unless asked.
  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# --------------------------------------------------------------------------- #
# IAM: execution role (what the ECS agent needs to *start* the task) and task
# role (what the app itself may call at runtime).
# --------------------------------------------------------------------------- #
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The execution role resolves `secrets` at task start, so it (not the task role)
# needs read on those ARNs. Only rendered when secrets are given.
data "aws_iam_policy_document" "execution_secrets" {
  count = length(var.secrets) > 0 ? 1 : 0

  statement {
    sid       = "ReadSecrets"
    actions   = ["ssm:GetParameters", "secretsmanager:GetSecretValue"]
    resources = values(var.secrets)
  }

  # SecureString parameters / customer-KMS secrets decrypt via the KMS key; scoping
  # to the key ARN would need it as an input, so scope by the calling service.
  statement {
    sid       = "DecryptSecrets"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "ssm.${local.region}.amazonaws.com",
        "secretsmanager.${local.region}.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  count  = length(var.secrets) > 0 ? 1 : 0
  name   = "${var.name_prefix}-execution-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets[0].json
}

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "task" {
  count = length(var.policy_statements) > 0 || var.enable_execute_command ? 1 : 0

  dynamic "statement" {
    for_each = var.policy_statements
    content {
      sid       = statement.value.sid
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }

  # ECS Exec: the SSM agent inside the task opens a channel back to SSM.
  dynamic "statement" {
    for_each = var.enable_execute_command ? [1] : []
    content {
      sid = "EcsExec"
      actions = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "task" {
  count  = length(var.policy_statements) > 0 || var.enable_execute_command ? 1 : 0
  name   = "${var.name_prefix}-task-policy"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task[0].json
}

# --------------------------------------------------------------------------- #
# Task definition + service
# --------------------------------------------------------------------------- #
resource "aws_ecs_task_definition" "this" {
  family                   = var.name_prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  tags                     = var.tags

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.architecture
  }

  # No container healthCheck: the ALB target group already probes
  # health_check_path, and a second probe just doubles the noise.
  container_definitions = jsonencode([{
    name      = var.container_name
    image     = "${local.repo_url}:${var.image_tag}"
    essential = true
    command   = var.command
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]
    environment = local.container_environment
    secrets     = local.container_secrets
    # initProcessEnabled runs an init as PID 1 to reap the SSM agent's children
    # under ECS Exec.
    linuxParameters = { initProcessEnabled = true }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = local.region
        awslogs-stream-prefix = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "this" {
  name             = var.name_prefix
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.this.arn
  desired_count    = var.desired_count
  platform_version = "LATEST"
  tags             = var.tags

  enable_execute_command            = var.enable_execute_command
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  # Rolling deploy: bring the new task up alongside the old one, then drain.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Don't block apply on the rollout; the circuit breaker handles a bad image.
  wait_for_steady_state = false

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
  }

  network_configuration {
    subnets          = local.subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  # CI registers new task-definition revisions with the built image and calls
  # update-service; Terraform owns the shape, CI owns the running image (same
  # model as lambda-container's ignore_changes on image_uri). desired_count is
  # ignored so a manual scale-up/down isn't reverted by an unrelated apply.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  # The service can't register targets until a listener owns the target group.
  depends_on = [aws_lb_listener.http, aws_lb_listener.https]
}

# --------------------------------------------------------------------------- #
# Security groups
# --------------------------------------------------------------------------- #
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Internet-facing ALB for ${var.name_prefix}"
  vpc_id      = local.vpc_id
  tags        = var.tags

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "task" {
  name        = "${var.name_prefix}-task-sg"
  description = "Fargate tasks for ${var.name_prefix}; ingress only from the ALB"
  vpc_id      = local.vpc_id
  tags        = var.tags

  ingress {
    description     = "App port from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Egress is what pulls the image, ships logs, and reaches the app's dependencies.
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# --------------------------------------------------------------------------- #
# ALB + target group + listeners
# --------------------------------------------------------------------------- #
resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  ip_address_type    = "ipv4"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids
  tags               = var.tags

  # Idle WebSockets are closed at this timeout. LiveView heartbeats every 30 s,
  # so 60 would also work; 120 leaves slack for a paused tab.
  idle_timeout               = var.alb_idle_timeout
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "this" {
  name        = "${var.name_prefix}-tg"
  target_type = "ip"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  tags        = var.tags

  # How long a draining task keeps its in-flight connections during a rollout.
  # The AWS default (300 s) makes every deploy feel five minutes slow.
  deregistration_delay = var.deregistration_delay

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    type    = "lb_cookie"
    enabled = false
  }
}

resource "aws_lb_listener" "https" {
  count             = local.use_custom_domain ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.this[0].certificate_arn
  tags              = var.tags

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# With a cert, :80 redirects to HTTPS. Without one, :80 serves the app directly
# so the module still works with no domain at all (plain HTTP on the ALB DNS name).
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  tags              = var.tags

  dynamic "default_action" {
    for_each = local.use_custom_domain ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.use_custom_domain ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.this.arn
    }
  }
}

# --------------------------------------------------------------------------- #
# Optional custom domain: regional ACM cert (DNS-validated) + Route 53 aliases.
# ALB certs live in the ALB's own region — no us-east-1 provider alias needed
# (unlike CloudFront in static-site).
# --------------------------------------------------------------------------- #
resource "aws_acm_certificate" "this" {
  count             = local.use_custom_domain ? 1 : 0
  domain_name       = var.custom_domain
  validation_method = "DNS"
  tags              = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.use_custom_domain ? {
    for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "this" {
  count                   = local.use_custom_domain ? 1 : 0
  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# A + AAAA aliases. The ALB is ipv4-only, but an AAAA alias to it is valid and
# lets a future dualstack flip need no DNS change.
resource "aws_route53_record" "alias" {
  for_each = local.use_custom_domain ? toset(["A", "AAAA"]) : toset([])
  zone_id  = var.hosted_zone_id
  name     = var.custom_domain
  type     = each.value

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = false
  }
}
