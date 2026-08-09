variable "name_prefix" {
  description = "Prefix for all resources this module creates (e.g. \"myapp\"). Per-PR Lambdas are expected to be named \"<name_prefix>-preview-pr-<N>\"."
  type        = string
}

variable "preview_domain" {
  description = <<-EOT
    Parent domain for previews (e.g. "preview.example.com"). Each open PR is
    served at https://pr-<N>.<preview_domain>. The module issues a wildcard
    ACM certificate for *.<preview_domain> and points a wildcard Route 53
    alias at the preview CloudFront distribution.
  EOT
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID that owns preview_domain."
  type        = string
}

variable "price_class" {
  description = "CloudFront price class for the preview distribution."
  type        = string
  default     = "PriceClass_100"
}

variable "expire_previews_after_days" {
  description = <<-EOT
    Backstop lifecycle rule: objects under previews/ are expired this many days
    after upload, so orphaned previews (e.g. a cleanup workflow that never ran)
    do not accumulate. Every push to an open PR re-uploads its objects, which
    resets the clock. Set 0 to disable.
  EOT
  type        = number
  default     = 14
}

variable "preview_lambda_policy_statements" {
  description = <<-EOT
    IAM statements attached to the shared execution role that every per-PR
    preview Lambda runs as — grant access to the preview data tier here (e.g.
    the dev DynamoDB table, SSM parameters under /myapp/dev/*). CloudWatch Logs
    access is always included. Each element is a standard statement object with
    keys: sid (optional), effect (optional, default Allow), actions, resources.
  EOT
  type = list(object({
    sid       = optional(string)
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

variable "tags" {
  description = "Tags applied to taggable resources."
  type        = map(string)
  default     = {}
}
