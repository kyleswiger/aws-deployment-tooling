variable "name_prefix" {
  description = "Prefix for all resources this module creates (e.g. \"myapp\" or \"myapp-dev\")."
  type        = string
}

variable "custom_domain" {
  description = "Optional custom domain for the site (e.g. app.example.com). Leave empty to serve on the CloudFront domain."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for custom_domain. Required when custom_domain is set."
  type        = string
  default     = ""
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 (US/EU) is the cheapest; use PriceClass_All for global low latency."
  type        = string
  default     = "PriceClass_100"
}

variable "spa_fallback" {
  description = <<-EOT
    When true, S3 403/404 responses are rewritten to /index.html with a 200 so a
    client-side router owns routing. Set false for a multi-page static site.
  EOT
  type        = bool
  default     = true
}

variable "additional_aliases" {
  description = "Extra CloudFront aliases beyond custom_domain (e.g. www.example.com). Each must be covered by the ACM cert."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to taggable resources."
  type        = map(string)
  default     = {}
}
