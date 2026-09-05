output "url" {
  description = "Public URL of the app."
  value       = module.app.url
}

output "ecr_repository_url" {
  description = "ECR repo CI pushes images to."
  value       = module.app.ecr_repository_url
}

output "cluster_name" {
  description = "ECS cluster — CI targets this with update-service."
  value       = module.app.cluster_name
}

output "service_name" {
  description = "ECS service — CI targets this with update-service."
  value       = module.app.service_name
}

output "task_definition_family" {
  description = "Task-definition family CI registers new revisions under."
  value       = module.app.task_definition_family
}

output "container_name" {
  description = "Container name CI substitutes the new image into."
  value       = module.app.container_name
}

output "log_group_name" {
  description = "CloudWatch log group for the container."
  value       = module.app.log_group_name
}

output "github_actions_role_arn" {
  description = "Save as the AWS_GITHUB_ACTIONS_ROLE_ARN repo secret."
  value       = module.ci_role.role_arn
}
