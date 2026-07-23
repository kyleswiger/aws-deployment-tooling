output "function_name" {
  description = "The Lambda function name."
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

output "role_arn" {
  description = "ARN of the execution role (to attach further policies out-of-module)."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the execution role."
  value       = aws_iam_role.this.name
}
