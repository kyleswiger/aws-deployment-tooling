output "site_url" {
  description = "Public URL of the SPA."
  value       = module.site.site_url
}

output "site_bucket" {
  description = "S3 bucket the built frontend is synced to."
  value       = module.site.site_bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — pass to `aws cloudfront create-invalidation`."
  value       = module.site.cloudfront_distribution_id
}

output "api_url" {
  description = "Base URL of the API. Set this as the frontend's API endpoint."
  value       = module.api.api_url
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
  description = "Cognito issuer URL — the frontend uses this to discover JWKS."
  value       = module.auth.issuer
}
