output "function_name" {
  description = "The Lambda function name (pass to CI for update-function-code)."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "The Lambda function ARN."
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "invoke_arn for API Gateway integration."
  value       = aws_lambda_function.this.invoke_arn
}

output "ecr_repository_url" {
  description = "ECR repository URL (created or passed through). CI logs in and pushes here."
  value       = local.repo_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN (for scoping a CI role's push permissions). Empty when reusing an external repo."
  value       = var.create_ecr_repository ? aws_ecr_repository.this[0].arn : ""
}

output "role_arn" {
  description = "ARN of the execution role."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the execution role."
  value       = aws_iam_role.this.name
}
