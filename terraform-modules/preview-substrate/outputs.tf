output "preview_bucket" {
  description = "Name of the preview S3 bucket."
  value       = aws_s3_bucket.previews.id
}

output "preview_bucket_arn" {
  description = "ARN of the preview S3 bucket."
  value       = aws_s3_bucket.previews.arn
}

output "cloudfront_distribution_id" {
  description = "ID of the preview CloudFront distribution (for invalidations)."
  value       = aws_cloudfront_distribution.previews.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the preview CloudFront distribution."
  value       = aws_cloudfront_distribution.previews.arn
}

output "preview_domain" {
  description = "Parent preview domain; PR N is served at https://pr-N.<preview_domain>."
  value       = var.preview_domain
}

output "preview_lambda_exec_role_arn" {
  description = "ARN of the shared execution role for per-PR preview Lambdas — pass to the preview-deploy workflow."
  value       = aws_iam_role.preview_lambda_exec.arn
}

output "preview_lambda_exec_role_name" {
  description = "Name of the shared execution role for per-PR preview Lambdas."
  value       = aws_iam_role.preview_lambda_exec.name
}

# Least-privilege statements for the CI role that deploys previews. Feed into
# the github-oidc-role module's policy_statements (concat with the site's own
# statements).
output "ci_policy_statements" {
  description = "IAM statements the CI role needs to deploy and clean up previews; shaped for github-oidc-role's policy_statements input."
  value = [
    {
      sid    = "PreviewSyncSite"
      effect = "Allow"
      actions = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket",
      ]
      resources = [
        aws_s3_bucket.previews.arn,
        "${aws_s3_bucket.previews.arn}/*",
      ]
    },
    {
      sid       = "PreviewInvalidate"
      effect    = "Allow"
      actions   = ["cloudfront:CreateInvalidation"]
      resources = [aws_cloudfront_distribution.previews.arn]
    },
    {
      sid    = "PreviewLambda"
      effect = "Allow"
      actions = [
        "lambda:CreateFunction",
        "lambda:GetFunction",
        "lambda:GetFunctionConfiguration",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:DeleteFunction",
        "lambda:TagResource",
        "lambda:CreateFunctionUrlConfig",
        "lambda:GetFunctionUrlConfig",
        "lambda:UpdateFunctionUrlConfig",
        "lambda:DeleteFunctionUrlConfig",
        "lambda:AddPermission",
        "lambda:RemovePermission",
      ]
      resources = [local.lambda_arn_match]
    },
    {
      sid       = "PreviewPassExecRole"
      effect    = "Allow"
      actions   = ["iam:PassRole"]
      resources = [aws_iam_role.preview_lambda_exec.arn]
    },
  ]
}
