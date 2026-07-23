variable "function_name" {
  description = "Full Lambda function name (e.g. \"myapp-api\")."
  type        = string
}

variable "zip_path" {
  description = "Path to the deployment .zip, typically built under the calling module's path.module (e.g. ../backend/dist/api.zip)."
  type        = string
}

variable "handler" {
  description = "Function handler (e.g. \"index.handler\" for Node, \"main.handler\" for Python)."
  type        = string
  default     = "index.handler"
}

variable "runtime" {
  description = "Lambda runtime identifier (e.g. \"nodejs22.x\", \"python3.12\")."
  type        = string
  default     = "nodejs22.x"
}

variable "memory_size" {
  description = "Memory (MB). Also scales proportional CPU."
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Timeout (seconds)."
  type        = number
  default     = 15
}

variable "environment" {
  description = "Environment variables for the function."
  type        = map(string)
  default     = {}
}

variable "policy_statements" {
  description = <<-EOT
    Inline IAM policy statements granting the function what it needs (DynamoDB,
    SNS, Cognito admin, etc.). Logs permissions are always attached automatically.
  EOT
  type = list(object({
    sid       = optional(string)
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

variable "log_retention_days" {
  description = "CloudWatch log retention for this function."
  type        = number
  default     = 30
}

variable "reserved_concurrency" {
  description = "Reserved concurrent executions. -1 leaves it unreserved (account default)."
  type        = number
  default     = -1
}

variable "tags" {
  description = "Tags applied to the function and role."
  type        = map(string)
  default     = {}
}
