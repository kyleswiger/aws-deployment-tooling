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

variable "custom_domain" {
  description = "Custom domain for the SPA (e.g. \"app.example.com\"). Empty = use the CloudFront domain only (no ACM/Route53)."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for custom_domain. Required only when custom_domain is set."
  type        = string
  default     = ""
}

variable "api_zip_path" {
  description = "Path to the built backend deployment package (.zip)."
  type        = string
  default     = "./placeholder/api.zip"
}

variable "api_runtime" {
  description = "Lambda runtime for the API handler."
  type        = string
  default     = "nodejs22.x"
}

variable "local_dev_origin" {
  description = "Local dev server origin to allow through CORS (e.g. Vite's http://localhost:5173)."
  type        = string
  default     = "http://localhost:5173"
}
