variable "name_prefix" {
  description = "Prefix for the IAM role name (e.g. \"myapp-dev\"). Role is named \"<name_prefix>-github-actions-role\"."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in \"owner/repo\" form (e.g. \"kyleswiger/myapp\")."
  type        = string
}

variable "create_oidc_provider" {
  description = <<-EOT
    Whether to create the GitHub OIDC provider. Set false if it already exists in
    the account — an account may only have one provider per issuer URL, and a
    second `aws_iam_openid_connect_provider` for token.actions.githubusercontent.com
    will fail with EntityAlreadyExists.
  EOT
  type        = bool
  default     = true
}

variable "subject_claims" {
  description = <<-EOT
    OIDC `sub` claims the role will trust, as StringLike patterns. Defaults to
    pushes on main and any pull request from this repo. Tighten to specific
    environments/branches for production (e.g. "repo:owner/repo:environment:prod").
  EOT
  type        = list(string)
  default     = null
}

variable "policy_statements" {
  description = <<-EOT
    Additional inline IAM policy statements (as objects) attached to the role so
    CI can do its job — e.g. s3:PutObject to the site bucket, ecr:* to push
    images, lambda:UpdateFunctionCode. Each element is a standard statement
    object with keys: sid (optional), effect, actions, resources.
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
  description = "Tags applied to the IAM role."
  type        = map(string)
  default     = {}
}
