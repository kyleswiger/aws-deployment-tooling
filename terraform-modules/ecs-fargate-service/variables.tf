variable "name_prefix" {
  description = "Prefix for all resources this module creates (e.g. \"myapp\"). Also the cluster, service, and task-definition family name."
  type        = string
}

variable "custom_domain" {
  description = "Domain to serve the app on (e.g. \"app.example.com\"). Empty = plain HTTP on the ALB DNS name, no certificate."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID that owns custom_domain. Required only when custom_domain is set."
  type        = string
  default     = ""
}

# --- Image / ECR -------------------------------------------------------------

variable "create_ecr_repository" {
  description = "When true, creates an ECR repository for the image. Set false to reuse an existing repo (pass image_repository_url)."
  type        = bool
  default     = true
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository to create (defaults to \"<name_prefix>-repo\" when empty)."
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
    Image tag Terraform bakes into the task definition it registers. CI then
    registers newer revisions with the built tag and calls update-service; the
    service's task_definition is under ignore_changes so routine applies don't
    roll it back. "latest" is a fine placeholder for the first apply.
  EOT
  type        = string
  default     = "latest"
}

variable "ecr_image_scan_on_push" {
  description = "Enable ECR basic vulnerability scanning on push for the created repository."
  type        = bool
  default     = true
}

# --- Task shape --------------------------------------------------------------

variable "container_name" {
  description = "Name of the single container in the task definition. CI needs it to build a new revision; it is also an output."
  type        = string
  default     = "app"
}

variable "container_port" {
  description = "Port the container listens on; the target group and task SG use it. 4000 is the Phoenix default."
  type        = number
  default     = 4000
}

variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU). Must be a valid Fargate cpu/memory pairing."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory (MiB). Must be a valid Fargate cpu/memory pairing (256 cpu allows 512, 1024, 2048)."
  type        = number
  default     = 512
}

variable "architecture" {
  description = <<-EOT
    CPU architecture of the image. ARM64 (Graviton) is ~20% cheaper per vCPU-hour
    and BEAM/most runtimes build for it natively; build the image with
    `docker buildx --platform linux/arm64` (or on an ARM runner) to match.
  EOT
  type        = string
  default     = "ARM64"
  validation {
    condition     = contains(["ARM64", "X86_64"], var.architecture)
    error_message = "architecture must be \"ARM64\" or \"X86_64\"."
  }
}

variable "command" {
  description = "Override the image's CMD (list form). Null keeps the image default."
  type        = list(string)
  default     = null
}

variable "environment" {
  description = "Plain environment variables for the container (rendered as a sorted name/value list)."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = <<-EOT
    Environment variables resolved at task start from SSM Parameter Store or
    Secrets Manager: env var name => parameter/secret ARN. The *execution* role is
    granted read + kms:Decrypt (via-service scoped) on exactly these ARNs, so the
    values never pass through Terraform state.
  EOT
  type        = map(string)
  default     = {}
}

# --- Service -----------------------------------------------------------------

variable "desired_count" {
  description = "Number of tasks. Under ignore_changes, so a manual scale is not reverted by apply."
  type        = number
  default     = 1
}

variable "capacity_provider" {
  description = <<-EOT
    FARGATE or FARGATE_SPOT. Spot is ~70% cheaper and fine for a dev/staging app
    or anything that tolerates a two-minute interruption notice; the service
    simply re-launches the task. Use FARGATE where an interruption is a page.
  EOT
  type        = string
  default     = "FARGATE"
  validation {
    condition     = contains(["FARGATE", "FARGATE_SPOT"], var.capacity_provider)
    error_message = "capacity_provider must be \"FARGATE\" or \"FARGATE_SPOT\"."
  }
}

variable "health_check_grace_period_seconds" {
  description = "Seconds after task launch before ALB health checks can mark it unhealthy. Cover the app's boot time (migrations, VM start)."
  type        = number
  default     = 60
}

variable "enable_execute_command" {
  description = <<-EOT
    Enable ECS Exec (`aws ecs execute-command`) — an IEx/shell into the running
    task without SSH or a bastion. Adds the ssmmessages statement to the task
    role and initProcessEnabled to the container. Free; on by default.
  EOT
  type        = bool
  default     = true
}

variable "container_insights" {
  description = "Enable CloudWatch Container Insights on the cluster. Off by default: it bills per custom metric and the service/ALB metrics already cover a single-service cluster."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the container log group."
  type        = number
  default     = 30
}

# --- Load balancer -----------------------------------------------------------

variable "health_check_path" {
  description = "HTTP path the target group probes; must return 200 without auth."
  type        = string
  default     = "/healthz"
}

variable "alb_idle_timeout" {
  description = <<-EOT
    ALB idle timeout in seconds. Idle WebSocket connections are closed at this
    limit. Phoenix LiveView heartbeats every 30 s, so 60 would also work; 120
    leaves slack for a briefly backgrounded tab.
  EOT
  type        = number
  default     = 120
}

variable "deregistration_delay" {
  description = "Seconds a draining target keeps in-flight connections during a rollout. AWS defaults to 300, which makes every deploy feel slow; 15 suits short HTTP requests (LiveView sockets reconnect)."
  type        = number
  default     = 15
}

# --- Network -----------------------------------------------------------------

variable "vpc_id" {
  description = "VPC to deploy into. Empty = the account's default VPC."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnets for the ALB and tasks. Empty = every subnet in the VPC with map-public-ip-on-launch (the default VPC's public subnets). An ALB needs at least two in different AZs."
  type        = list(string)
  default     = []
}

variable "assign_public_ip" {
  description = <<-EOT
    Give each task a public IPv4 address. True is the deliberate cheap default:
    a Fargate task in a *private* subnet still has to reach ECR, CloudWatch Logs,
    and SSM, which means either a NAT gateway (~$33/mo + data) or three interface
    VPC endpoints (~$22/mo) just to pull the image and ship logs. A public IP
    costs $3.65/mo and the task SG only admits the ALB anyway. Set false only when
    passing private subnets that already have that egress path.
  EOT
  type        = bool
  default     = true
}

# --- IAM ---------------------------------------------------------------------

variable "policy_statements" {
  description = "Inline IAM permissions the *application* needs at runtime (attached to the task role). Image pull, logs, and secrets are handled by the execution role automatically."
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
