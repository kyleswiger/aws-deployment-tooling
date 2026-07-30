# `http-api-cognito` module

An HTTP API (API Gateway v2) fronting a single proxy-integrated Lambda, guarded
by a **Cognito JWT authorizer**. The authorizer validates access/ID tokens at the
edge — there's no authorizer Lambda to run or pay for. Cheaper and lower latency
than a REST API.

Pairs with [`cognito-user-pool`](../cognito-user-pool) (provides `issuer` and
`user_pool_client_id`) and either Lambda module.

## Usage

```hcl
module "api" {
  source               = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/http-api-cognito"
  name_prefix          = "myapp"
  lambda_function_name = module.api_lambda.function_name
  lambda_invoke_arn    = module.api_lambda.invoke_arn
  cognito_issuer       = module.auth.issuer
  cognito_audience     = module.auth.user_pool_client_id

  cors_allow_origins = [
    module.site.site_url,
    "http://localhost:5173",
  ]
}
```

## Design notes

- **No OPTIONS route.** Preflight requests carry no `Authorization` header, so an
  `OPTIONS`/`ANY` route would 401 at the JWT authorizer. Omitting it lets API
  Gateway's built-in CORS handling answer preflights. Adjust `route_methods` if
  you need more verbs.
- **`$default` auto-deploy stage.** The invoke URL (`api_url`) is stable; no
  manual deployment step.

## Inputs (selected)

| Name | Type | Default | Description |
|---|---|---|---|
| `lambda_function_name` / `lambda_invoke_arn` | string | — | Backing Lambda. |
| `cognito_issuer` / `cognito_audience` | string | — | From the cognito module. |
| `cors_allow_origins` | list(string) | `[]` | Allowed origins (empties dropped). |
| `route_methods` | list(string) | `[GET,POST,PUT,DELETE]` | Proxied methods. |

## Outputs

`api_id`, `api_url`, `api_execution_arn`.
