# Lightweight zip-Lambda stack
# --------------------------------
# Static SPA + Cognito + a single zip-packaged API Lambda behind API Gateway v2.
# Ship it with the profile-driven scripts/deploy.sh (build → apply → sync →
# invalidate). No CI role here — see ../container-cicd-stack for the OIDC path.

# 1. Static site: private S3 + CloudFront (OAC), optional custom domain.
module "site" {
  source = "../../terraform-modules/static-site"

  name_prefix    = var.name_prefix
  custom_domain  = var.custom_domain
  hosted_zone_id = var.hosted_zone_id
}

# 2. Auth: invite-only Cognito pool + SPA client.
module "auth" {
  source = "../../terraform-modules/cognito-user-pool"

  name_prefix      = var.name_prefix
  app_display_name = var.app_display_name

  # Where Cognito's hosted UI may redirect back to after login/logout.
  callback_urls = compact([module.site.site_url, var.local_dev_origin])
  logout_urls   = compact([module.site.site_url, var.local_dev_origin])
}

# 3. Backend: zip-packaged Lambda. deploy.sh rebuilds the zip and applies.
module "api_lambda" {
  source = "../../terraform-modules/lambda-zip"

  function_name = "${var.name_prefix}-api"
  zip_path      = var.api_zip_path
  handler       = "index.handler"
  runtime       = var.api_runtime
  memory_size   = 256
  timeout       = 15

  environment = {
    USER_POOL_ID     = module.auth.user_pool_id
    USER_POOL_CLIENT = module.auth.user_pool_client_id
  }
}

# 4. Front door: API Gateway v2 with a Cognito JWT authorizer → the Lambda.
module "api" {
  source = "../../terraform-modules/http-api-cognito"

  name_prefix          = var.name_prefix
  lambda_function_name = module.api_lambda.function_name
  lambda_invoke_arn    = module.api_lambda.invoke_arn
  cognito_issuer       = module.auth.issuer
  cognito_audience     = module.auth.user_pool_client_id

  cors_allow_origins = compact([module.site.site_url, var.local_dev_origin])
}
