# Email-as-username Cognito user pool with a public SPA client (no secret,
# SRP auth). Defaults to invite-only. Optionally sends mail from your own SES
# domain identity instead of the throttled Cognito default.

locals {
  use_ses = var.ses_source_arn != "" && var.ses_from_address != ""

  invite_subject = var.invite_email_subject != "" ? var.invite_email_subject : "You're invited to ${var.app_display_name}"
  # {username} renders an opaque UUID for email-username pools, so it's hidden.
  invite_message = var.invite_email_message != "" ? var.invite_email_message : join("", [
    "You've been invited to ${var.app_display_name}.<br><br>",
    "Sign in using this email address and your temporary password: {####}<br><br>",
    "You'll choose your own password the first time you sign in.",
    "<span style=\"display:none\">{username}</span>",
  ])

  reset_subject = var.reset_email_subject != "" ? var.reset_email_subject : "${var.app_display_name} password reset"
  reset_message = var.reset_email_message != "" ? var.reset_email_message : "Your ${var.app_display_name} password reset code is {####}."
}

resource "aws_cognito_user_pool" "main" {
  name                     = var.name_prefix
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  tags                     = var.tags

  admin_create_user_config {
    allow_admin_create_user_only = var.invite_only
    invite_message_template {
      email_subject = local.invite_subject
      email_message = local.invite_message
      sms_message   = "${var.app_display_name}: {username} / {####}"
    }
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = local.reset_subject
    email_message        = local.reset_message
  }

  dynamic "email_configuration" {
    for_each = local.use_ses ? [1] : []
    content {
      email_sending_account = "DEVELOPER"
      from_email_address    = var.ses_from_address
      source_arn            = var.ses_source_arn
    }
  }

  password_policy {
    minimum_length    = var.password_minimum_length
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    mutable             = true
    required            = true
    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }
}

resource "aws_cognito_user_pool_client" "spa" {
  name         = "${var.name_prefix}-spa"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"

  callback_urls = length(var.callback_urls) > 0 ? var.callback_urls : null
  logout_urls   = length(var.logout_urls) > 0 ? var.logout_urls : null

  access_token_validity  = var.access_token_validity_minutes
  id_token_validity      = var.id_token_validity_minutes
  refresh_token_validity = var.refresh_token_validity_days
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

resource "aws_cognito_user_group" "groups" {
  for_each     = var.groups
  name         = each.key
  user_pool_id = aws_cognito_user_pool.main.id
  description  = each.value
}
