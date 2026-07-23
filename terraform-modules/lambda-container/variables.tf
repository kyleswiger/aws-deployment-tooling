variable "function_name" {
  description = "Full Lambda function name (e.g. \"myapp-api\")."
  type        = string
}

variable "create_ecr_repository" {
  description = "When true, creates an ECR repository for the image. Set false to reuse an existing repo (pass image_repository_url)."
  type        = bool
  default     = true
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository to create (defaults to \"<function_name>-repo\" when empty)."
  type        = string
  default     = ""
}

variable "image_repository_url" {
  description = "ECR repository URL when create_ecr_repository = false. Ignored otherwise."
  type        = string
  default     = ""
}

variable "image_tag" {
  description = <<-EOT
    Image tag to deploy. Terraform pins the function to this tag on apply; the CI
    pipeline then rolls the running code forward with `lambda update-function-code`
    on each build. Use a placeholder tag (e.g. \"latest\") for the initial bootstrap
    before the first real image exists.
  EOT
  type        = string
  default     = "latest"
}

variable "memory_size" {
  description = "Memory (MB)."
  type        = number
  default     = 512
}

variable "timeout" {
  description = "Timeout (seconds)."
  type        = number
  default     = 30
}

variable "environment" {
  description = "Environment variables for the function."
  type        = map(string)
  default     = {}
}

variable "policy_statements" {
  description = "Inline IAM permissions the function needs. Logs permissions are attached automatically."
  type = list(object({
    sid       = optional(string)
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

variable "vpc_config" {
  description = <<-EOT
    Optional VPC attachment: { subnet_ids = [...], security_group_ids = [...] }.
    Null keeps the function outside a VPC (no NAT/endpoint cost). When set, the
    module also attaches the AWS-managed VPC access execution policy.
  EOT
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention for this function."
  type        = number
  default     = 30
}

variable "reserved_concurrency" {
  description = <<-EOT
    Reserved concurrent executions. -1 leaves it unreserved. A hard ceiling here
    also bounds downstream connection fan-out (e.g. RDS max_connections) when each
    cold container opens a connection.
  EOT
  type        = number
  default     = -1
}

variable "ecr_image_scan_on_push" {
  description = "Enable ECR basic vulnerability scanning on push for the created repository."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the function, role, and repository."
  type        = map(string)
  default     = {}
}
