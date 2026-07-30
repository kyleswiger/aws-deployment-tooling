# `lambda-container` module

A container-image (OCI) Lambda plus its ECR repository, execution role, logs
policy, optional inline permissions, and optional VPC attachment. Use this when
the function needs large or native dependencies that don't fit a zip (ML/vision
libraries, headless browsers, etc.). For small handlers, prefer
[`lambda-zip`](../lambda-zip).

## Deploy model (important)

Terraform owns the **infrastructure**; CI owns the **running code**:

1. Terraform pins the function to `<repo>:<image_tag>` and creates the ECR repo,
   role, and log group. On first apply the image doesn't exist yet — bootstrap
   the repo with a placeholder (see `scripts/bootstrap-ecr.sh`).
2. CI builds and pushes the image (SHA + `:latest` + `:cache` tags) and rolls the
   function forward with `aws lambda update-function-code` (see the `run-ci.sh`
   and `deploy-dev-api.yml` templates).

The function's `image_uri` is under `ignore_changes`, so routine `terraform apply`
runs won't revert the code CI just deployed.

## Usage

```hcl
module "api_lambda" {
  source        = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/lambda-container"
  function_name = "myapp-api"
  memory_size   = 1024
  timeout       = 30

  environment = { LOG_LEVEL = "info" }

  policy_statements = [
    {
      sid       = "ReadSecrets"
      actions   = ["ssm:GetParameter"]
      resources = ["arn:aws:ssm:us-east-1:*:parameter/myapp/*"]
    },
  ]

  # Optional VPC attachment (adds the managed VPC-access policy automatically)
  # vpc_config = {
  #   subnet_ids         = module.vpc.private_subnet_ids
  #   security_group_ids = [module.vpc.lambda_sg_id]
  # }
}
```

Grant your CI role `ecr:*` (push) and `lambda:UpdateFunctionCode` on
`ecr_repository_arn` / `function_arn` via the `github-oidc-role` module.

## Inputs (selected)

| Name | Type | Default | Description |
|---|---|---|---|
| `function_name` | string | — | Full function name. |
| `create_ecr_repository` | bool | `true` | Create the repo vs. reuse `image_repository_url`. |
| `image_tag` | string | `latest` | Tag Terraform pins on apply. |
| `vpc_config` | object / null | `null` | Optional VPC attachment. |
| `policy_statements` | list(object) | `[]` | Extra IAM permissions. |
| `reserved_concurrency` | number | `-1` | Concurrency cap. |

## Outputs

`function_name`, `function_arn`, `invoke_arn`, `ecr_repository_url`,
`ecr_repository_arn`, `role_arn`, `role_name`.
