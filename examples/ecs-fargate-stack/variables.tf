variable "name_prefix" {
  description = "Prefix for all resource names (e.g. \"myapp\")."
  type        = string
  default     = "myapp"
}

variable "github_repo" {
  description = "owner/repo that GitHub Actions deploys from (the OIDC trust subject)."
  type        = string
  default     = "kyleswiger/myapp"
}

variable "custom_domain" {
  description = "Domain to serve the app on. Empty = plain HTTP on the ALB DNS name."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for custom_domain. Required only when custom_domain is set."
  type        = string
  default     = ""
}
