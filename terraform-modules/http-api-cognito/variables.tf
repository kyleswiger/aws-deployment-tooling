variable "name_prefix" {
  description = "Name for the HTTP API and prefix for related resources."
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the backing Lambda function (used for the invoke permission)."
  type        = string
}

variable "lambda_invoke_arn" {
  description = "invoke_arn of the backing Lambda (aws_lambda_function.<x>.invoke_arn)."
  type        = string
}

variable "cognito_issuer" {
  description = "Cognito issuer URL (from the cognito-user-pool module's `issuer` output)."
  type        = string
}

variable "cognito_audience" {
  description = "JWT audience — the Cognito SPA client ID (cognito-user-pool `user_pool_client_id`)."
  type        = string
}

variable "cors_allow_origins" {
  description = "Allowed CORS origins (e.g. the site URL and http://localhost:5173). Empty strings are dropped."
  type        = list(string)
  default     = []
}

variable "cors_allow_methods" {
  description = "Allowed CORS methods."
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
}

variable "cors_allow_headers" {
  description = "Allowed CORS request headers."
  type        = list(string)
  default     = ["authorization", "content-type"]
}

variable "route_methods" {
  description = <<-EOT
    HTTP methods proxied to the Lambda as `<METHOD> /{proxy+}`, each guarded by
    the JWT authorizer. OPTIONS is deliberately excluded: an ANY/OPTIONS route
    would catch CORS preflights (which carry no Authorization header) and 401 at
    the authorizer. With no OPTIONS route, API Gateway answers preflights itself.
  EOT
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE"]
}

variable "tags" {
  description = "Tags applied to the API."
  type        = map(string)
  default     = {}
}
