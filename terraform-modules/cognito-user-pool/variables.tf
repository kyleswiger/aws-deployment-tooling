variable "name_prefix" {
  description = "Name for the user pool and prefix for its client (e.g. \"myapp\")."
  type        = string
}

variable "invite_only" {
  description = "When true, disables public sign-up — users must be created by an admin (AdminCreateUser)."
  type        = bool
  default     = true
}

variable "app_display_name" {
  description = "Human-readable app name used in invite/reset email subjects and bodies."
  type        = string
}

variable "invite_email_subject" {
  description = "Subject line for the admin-invite email."
  type        = string
  default     = ""
}

variable "invite_email_message" {
  description = <<-EOT
    HTML body for the admin-invite email. MUST contain the {####} placeholder
    (temporary password). {username} is required by Cognito validation but renders
    as an opaque UUID for email-username pools — hide it in a display:none span.
    Leave empty to use a sensible default built from app_display_name.
  EOT
  type        = string
  default     = ""
}

variable "reset_email_subject" {
  description = "Subject for the forgot-password code email."
  type        = string
  default     = ""
}

variable "reset_email_message" {
  description = "Body for the forgot-password email. MUST contain {####}. Empty uses a default."
  type        = string
  default     = ""
}

variable "ses_source_arn" {
  description = <<-EOT
    Optional verified SESv2 identity ARN. When set, Cognito sends invite/reset mail
    from your own domain (email_sending_account = DEVELOPER) instead of the rate-
    limited Cognito default. Pair with ses_from_address.
  EOT
  type        = string
  default     = ""
}

variable "ses_from_address" {
  description = "From address for Cognito mail when ses_source_arn is set (e.g. \"MyApp <no-reply@example.com>\")."
  type        = string
  default     = ""
}

variable "callback_urls" {
  description = "OAuth redirect URLs for the Hosted UI / SPA (only used when a Hosted-UI flow is configured downstream)."
  type        = list(string)
  default     = []
}

variable "logout_urls" {
  description = "URLs allowed after logout."
  type        = list(string)
  default     = []
}

variable "groups" {
  description = "User groups to create (e.g. { admin = \"Admins with elevated rights\" })."
  type        = map(string)
  default     = {}
}

variable "password_minimum_length" {
  description = "Minimum password length."
  type        = number
  default     = 10
}

variable "access_token_validity_minutes" {
  description = "Access token lifetime in minutes."
  type        = number
  default     = 60
}

variable "id_token_validity_minutes" {
  description = "ID token lifetime in minutes."
  type        = number
  default     = 60
}

variable "refresh_token_validity_days" {
  description = "Refresh token lifetime in days."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to the user pool."
  type        = map(string)
  default     = {}
}
