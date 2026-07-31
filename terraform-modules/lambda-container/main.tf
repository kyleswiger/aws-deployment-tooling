# A container-image (OCI) Lambda plus its ECR repository, execution role, logs
# policy, optional inline permissions, and optional VPC attachment. Best when the
# function needs large or native dependencies that don't fit a zip.
#
# Deploy model: Terraform pins the function to <repo>:<image_tag> and manages the
# infrastructure; CI builds and pushes the image (SHA + :latest + :cache tags)
# and rolls the running code forward with `aws lambda update-function-code`. So
# `terraform apply` and code deploys are decoupled — see the `run-ci.sh` template.

locals {
  repo_name = var.ecr_repository_name != "" ? var.ecr_repository_name : "${var.function_name}-repo"
  repo_url  = var.create_ecr_repository ? aws_ecr_repository.this[0].repository_url : var.image_repository_url
}

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

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "permissions" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }

  dynamic "statement" {
    for_each = var.policy_statements
    content {
      sid       = statement.value.sid
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.function_name}-policy"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}

# Managed policy that grants ENI create/delete for VPC-attached functions.
resource "aws_iam_role_policy_attachment" "vpc_access" {
  count      = var.vpc_config != null ? 1 : 0
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = aws_iam_role.this.arn
  package_type  = "Image"
  image_uri     = "${local.repo_url}:${var.image_tag}"
  memory_size   = var.memory_size
  timeout       = var.timeout
  tags          = var.tags

  reserved_concurrent_executions = var.reserved_concurrency

  dynamic "environment" {
    for_each = length(var.environment) > 0 ? [1] : []
    content {
      variables = var.environment
    }
  }

  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  # CI rolls the image forward out-of-band via update-function-code; don't let
  # Terraform fight it and revert to the pinned tag on unrelated applies.
  lifecycle {
    ignore_changes = [image_uri]
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${aws_lambda_function.this.function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}
