output "role_arn" {
  description = "ARN of the GitHub Actions role. Save as the AWS_GITHUB_ACTIONS_ROLE_ARN repo secret and pass to aws-actions/configure-aws-credentials."
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "Name of the GitHub Actions role (for attaching further policies out-of-module)."
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider (created or looked up)."
  value       = local.provider_arn
}
