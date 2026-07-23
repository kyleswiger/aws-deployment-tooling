output "user_pool_id" {
  description = "Cognito user pool ID."
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "Cognito user pool ARN (e.g. for Lambda AdminCreateUser grants or the API authorizer)."
  value       = aws_cognito_user_pool.main.arn
}

output "user_pool_client_id" {
  description = "SPA app client ID. The browser bundle and the JWT authorizer both use this as the audience."
  value       = aws_cognito_user_pool_client.spa.id
}

output "issuer" {
  description = "OIDC issuer URL for the pool. API Gateway JWT authorizers and SPA OIDC libraries need this."
  value       = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}
