output "site_url" {
  description = "Public URL of the SPA."
  value       = module.site.site_url
}

output "site_bucket" {
  description = "S3 bucket the built frontend is synced to."
  value       = module.site.site_bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation)."
  value       = module.site.cloudfront_distribution_id
}

output "api_url" {
  description = "Base URL of the API."
  value       = module.api.api_url
}

output "ecr_repository_url" {
  description = "ECR repo CI pushes API images to. Feed to scripts/bootstrap-ecr.sh and the build."
  value       = module.api_lambda.ecr_repository_url
}

output "lambda_function_name" {
  description = "API Lambda name — CI targets this with update-function-code."
  value       = module.api_lambda.function_name
}

output "user_pool_id" {
  description = "Cognito user pool ID."
  value       = module.auth.user_pool_id
}

output "user_pool_client_id" {
  description = "Cognito SPA app client ID (the JWT audience)."
  value       = module.auth.user_pool_client_id
}

output "cognito_issuer" {
  description = "Cognito issuer URL."
  value       = module.auth.issuer
}

output "github_actions_role_arn" {
  description = "Save as the AWS_GITHUB_ACTIONS_ROLE_ARN repo secret."
  value       = module.ci_role.role_arn
}
