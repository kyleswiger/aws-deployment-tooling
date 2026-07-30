# Container-Lambda stack with change-aware CI
# ---------------------------------------------
# Static SPA + Cognito + an image-packaged API Lambda (ECR), plus a keyless
# GitHub Actions role. Terraform owns infrastructure; CI owns code — it pushes
# images and calls `lambda update-function-code`, so the Lambda module ignores
# image_uri drift. See ../../docs/change-aware-ci.md.

# 1. Static site.
module "site" {
  source = "../../terraform-modules/static-site"

  name_prefix    = var.name_prefix
  custom_domain  = var.custom_domain
  hosted_zone_id = var.hosted_zone_id
}

# 2. Auth.
module "auth" {
  source = "../../terraform-modules/cognito-user-pool"

  name_prefix      = var.name_prefix
  app_display_name = var.app_display_name

  callback_urls = compact([module.site.site_url, var.local_dev_origin])
  logout_urls   = compact([module.site.site_url, var.local_dev_origin])
}

# 3. Data store (example). App-specific — shown here so the Lambda has something
#    to be granted access to.
resource "aws_dynamodb_table" "app" {
  name         = "${var.name_prefix}-app"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }
  attribute {
    name = "sk"
    type = "S"
  }
}

# 4. Backend: image-packaged Lambda + its ECR repo. First apply needs a
#    placeholder image in the repo — run scripts/bootstrap-ecr.sh once. After
#    that, CI pushes real images and updates the function code.
module "api_lambda" {
  source = "../../terraform-modules/lambda-container"

  function_name         = "${var.name_prefix}-api"
  create_ecr_repository = true
  memory_size           = 512
  timeout               = 30

  environment = {
    TABLE_NAME   = aws_dynamodb_table.app.name
    USER_POOL_ID = module.auth.user_pool_id
  }

  # Least-privilege data access for the handler.
  policy_statements = [
    {
      sid     = "AppTableAccess"
      effect  = "Allow"
      actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
      resources = [
        aws_dynamodb_table.app.arn,
        "${aws_dynamodb_table.app.arn}/index/*",
      ]
    },
  ]
}

# 5. Front door.
module "api" {
  source = "../../terraform-modules/http-api-cognito"

  name_prefix          = var.name_prefix
  lambda_function_name = module.api_lambda.function_name
  lambda_invoke_arn    = module.api_lambda.invoke_arn
  cognito_issuer       = module.auth.issuer
  cognito_audience     = module.auth.user_pool_client_id

  cors_allow_origins = compact([module.site.site_url, var.local_dev_origin])
}

# 6. Keyless CI role. Trust defaults to main + any PR (fine for a dev role);
#    scope subject_claims to a GitHub Environment for prod. Permissions are
#    exactly what the deploy workflow needs, ARN-scoped.
module "ci_role" {
  source = "../../terraform-modules/github-oidc-role"

  name_prefix = "${var.name_prefix}-deploy"
  github_repo = var.github_repo

  # One OIDC provider per account. If token.actions.githubusercontent.com is
  # already registered, set this false and the module looks it up.
  create_oidc_provider = true

  policy_statements = [
    {
      sid       = "SyncSite"
      effect    = "Allow"
      actions   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetObject"]
      resources = [module.site.site_bucket_arn, "${module.site.site_bucket_arn}/*"]
    },
    {
      sid       = "Invalidate"
      effect    = "Allow"
      actions   = ["cloudfront:CreateInvalidation"]
      resources = [module.site.cloudfront_distribution_arn]
    },
    {
      sid       = "EcrAuth"
      effect    = "Allow"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    },
    {
      sid       = "PushImage"
      effect    = "Allow"
      actions   = ["ecr:BatchCheckLayerAvailability", "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
      resources = [module.api_lambda.ecr_repository_arn]
    },
    {
      sid       = "DeployLambda"
      effect    = "Allow"
      actions   = ["lambda:UpdateFunctionCode", "lambda:GetFunction"]
      resources = [module.api_lambda.function_arn]
    },
  ]
}
