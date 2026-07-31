# `cognito-user-pool` module

An email-as-username Cognito user pool with a public SPA client (no client
secret, SRP auth). Defaults to **invite-only** (no public sign-up). Optionally
sends invite / password-reset mail from your own SES domain identity instead of
the throttled Cognito default.

Pairs directly with the [`http-api-cognito`](../http-api-cognito) module, which
attaches this pool as a JWT authorizer.

## Usage

```hcl
module "auth" {
  source           = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/cognito-user-pool"
  name_prefix      = "myapp"
  app_display_name = "My App"
  invite_only      = true
  groups           = { admin = "Admins: user invites, settings" }

  # Optional: send mail from your domain (requires a verified SESv2 identity)
  ses_source_arn   = module.email.identity_arn
  ses_from_address = "My App <no-reply@example.com>"
}
```

## Outputs

`user_pool_id`, `user_pool_arn`, `user_pool_client_id`, `issuer`.

The SPA build consumes `user_pool_id` + `user_pool_client_id`; the API authorizer
consumes `issuer` + `user_pool_client_id`.

## Inputs (selected)

| Name | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | string | — | Pool name / client prefix. |
| `app_display_name` | string | — | Name shown in invite/reset emails. |
| `invite_only` | bool | `true` | Disable public sign-up. |
| `groups` | map(string) | `{}` | `name => description` groups to create. |
| `ses_source_arn` / `ses_from_address` | string | `""` | Send mail from your own domain. |
| `*_token_validity_*` | number | 60m / 60m / 30d | Access / ID / refresh token lifetimes. |

See `variables.tf` for the full list, including email subject/body overrides and
Hosted-UI callback/logout URLs.
