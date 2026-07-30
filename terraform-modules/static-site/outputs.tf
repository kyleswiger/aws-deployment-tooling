output "site_bucket" {
  description = "Name of the private S3 bucket holding the built site. `aws s3 sync` your dist/ here."
  value       = aws_s3_bucket.site.bucket
}

output "site_bucket_arn" {
  description = "ARN of the site bucket (useful for granting a CI role PutObject)."
  value       = aws_s3_bucket.site.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID. Pass to `aws cloudfront create-invalidation` after each deploy."
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN (useful for a CI role's CreateInvalidation grant)."
  value       = aws_cloudfront_distribution.site.arn
}

output "cloudfront_domain_name" {
  description = "The *.cloudfront.net domain. Use this as the site URL when no custom domain is set."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "site_url" {
  description = "Canonical site URL (custom domain if set, otherwise the CloudFront domain)."
  value       = local.use_custom_domain ? "https://${var.custom_domain}" : "https://${aws_cloudfront_distribution.site.domain_name}"
}
