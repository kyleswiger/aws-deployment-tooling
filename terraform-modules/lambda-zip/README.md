# `lambda-zip` module

A zip-packaged Lambda plus its execution role, an always-on CloudWatch Logs
policy, an optional inline permissions policy, and a log group with explicit
retention. Best for small Node/Python handlers whose dependencies fit a zip
bundle. For image artifacts (large deps, native libraries), use
[`lambda-container`](../lambda-container).

## Usage

```hcl
module "api_lambda" {
  source        = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/lambda-zip"
  function_name = "myapp-api"
  zip_path      = "${path.module}/../backend/dist/api.zip"
  runtime       = "nodejs22.x"
  handler       = "index.handler"
  memory_size   = 256
  timeout       = 15

  environment = {
    TABLE_NAME   = aws_dynamodb_table.main.name
    USER_POOL_ID = module.auth.user_pool_id
  }

  policy_statements = [
    {
      sid       = "Dynamo"
      actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
      resources = [aws_dynamodb_table.main.arn, "${aws_dynamodb_table.main.arn}/index/*"]
    },
  ]
}
```

The `source_code_hash` is derived from the zip, so re-running `terraform apply`
after a rebuild redeploys the new code. Build the zip before `apply` (see
`scripts/deploy.sh`, which runs `npm run build` first).

## Inputs (selected)

| Name | Type | Default | Description |
|---|---|---|---|
| `function_name` | string | — | Full function name. |
| `zip_path` | string | — | Path to the deployment zip. |
| `runtime` / `handler` | string | `nodejs22.x` / `index.handler` | Runtime + entrypoint. |
| `environment` | map(string) | `{}` | Env vars. |
| `policy_statements` | list(object) | `[]` | Extra IAM permissions (logs always included). |
| `reserved_concurrency` | number | `-1` | Concurrency cap; -1 = unreserved. |

## Outputs

`function_name`, `function_arn`, `invoke_arn`, `role_arn`, `role_name`.
