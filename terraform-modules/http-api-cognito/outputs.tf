output "api_id" {
  description = "HTTP API ID."
  value       = aws_apigatewayv2_api.main.id
}

output "api_url" {
  description = "Invoke URL for the $default stage. This is the API base URL the SPA calls."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_execution_arn" {
  description = "Execution ARN of the API (for additional lambda:InvokeFunction permissions)."
  value       = aws_apigatewayv2_api.main.execution_arn
}
