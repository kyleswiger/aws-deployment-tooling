output "cluster_name" {
  description = "ECS cluster name (pass to CI for update-service)."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "service_name" {
  description = "ECS service name (pass to CI for update-service)."
  value       = aws_ecs_service.this.name
}

output "service_arn" {
  description = "ECS service ARN."
  value       = aws_ecs_service.this.id
}

output "task_definition_family" {
  description = "Task-definition family CI registers new revisions under."
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_arn" {
  description = "ARN of the task-definition revision Terraform registered (CI moves the service past it)."
  value       = aws_ecs_task_definition.this.arn
}

output "container_name" {
  description = "Name of the container in the task definition; CI uses it when rendering a new revision."
  value       = var.container_name
}

output "ecr_repository_url" {
  description = "ECR repository URL (created or passed through). CI logs in and pushes here."
  value       = local.repo_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN (for scoping a CI role's push permissions). Empty when reusing an external repo."
  value       = var.create_ecr_repository ? aws_ecr_repository.this[0].arn : ""
}

output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "ALB DNS name; the app answers here over plain HTTP when no custom domain is set."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID, for alias records in other zones."
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "Target group ARN."
  value       = aws_lb_target_group.this.arn
}

output "url" {
  description = "Public URL of the app: https://<custom_domain> when set, else http://<alb_dns_name>."
  value       = local.use_custom_domain ? "https://${var.custom_domain}" : "http://${aws_lb.this.dns_name}"
}

output "task_role_arn" {
  description = "ARN of the task (application) role."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Name of the task (application) role."
  value       = aws_iam_role.task.name
}

output "task_execution_role_arn" {
  description = "ARN of the task execution role (image pull, logs, secrets)."
  value       = aws_iam_role.execution.arn
}

output "log_group_name" {
  description = "CloudWatch log group the container writes to."
  value       = aws_cloudwatch_log_group.this.name
}

# Least-privilege statements for the CI role that builds and deploys this
# service. Feed into the github-oidc-role module's policy_statements (concat
# with anything else the workflow needs).
output "ci_policy_statements" {
  description = "IAM statements a deploy workflow needs (ECR push, register task definition, update service, pass roles, read logs); shaped for github-oidc-role's policy_statements input."
  value = concat(
    [
      {
        sid       = "EcrAuth"
        effect    = "Allow"
        actions   = ["ecr:GetAuthorizationToken"]
        resources = ["*"]
      },
    ],
    var.create_ecr_repository ? [
      {
        sid    = "EcrPush"
        effect = "Allow"
        actions = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        resources = [aws_ecr_repository.this[0].arn]
      },
    ] : [],
    [
      {
        # Neither action supports resource-level ARNs.
        sid       = "EcsTaskDefinition"
        effect    = "Allow"
        actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
        resources = ["*"]
      },
      {
        sid       = "EcsService"
        effect    = "Allow"
        actions   = ["ecs:DescribeServices", "ecs:UpdateService"]
        resources = [aws_ecs_service.this.id]
      },
      {
        # One-off tasks (migrations, release scripts) from any revision of the family.
        sid       = "EcsRunTask"
        effect    = "Allow"
        actions   = ["ecs:DescribeTasks", "ecs:RunTask"]
        resources = [local.task_definition_family_arn]
      },
      {
        sid       = "EcsDescribeTasks"
        effect    = "Allow"
        actions   = ["ecs:DescribeTasks"]
        resources = ["arn:aws:ecs:${local.region}:${local.account_id}:task/${aws_ecs_cluster.this.name}/*"]
      },
      {
        # RegisterTaskDefinition / RunTask hand these roles to the task.
        sid       = "PassTaskRoles"
        effect    = "Allow"
        actions   = ["iam:PassRole"]
        resources = [aws_iam_role.task.arn, aws_iam_role.execution.arn]
      },
      {
        sid       = "ReadLogs"
        effect    = "Allow"
        actions   = ["logs:GetLogEvents"]
        resources = [aws_cloudwatch_log_group.this.arn, "${aws_cloudwatch_log_group.this.arn}:*"]
      },
    ],
  )
}
