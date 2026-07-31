variable "name_prefix" {
  description = "Prefix for all resource names (e.g. \"myapp\")."
  type        = string
  default     = "myapp"
}

variable "app_display_name" {
  description = "Human-readable app name, shown in Cognito invite emails."
  type        = string
  default     = "My App"
}

variable "github_repo" {
  description = "owner/repo that GitHub Actions deploys from (the OIDC trust subject)."
  type        = string
  default     = "kyleswiger/myapp"
}

variable "custom_domain" {
  description = "Custom domain for the SPA. Empty = CloudFront domain only."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for custom_domain. Required only when custom_domain is set."
  type        = string
  default     = ""
}

variable "local_dev_origin" {
  description = "Local dev server origin to allow through CORS."
  type        = string
  default     = "http://localhost:5173"
}
