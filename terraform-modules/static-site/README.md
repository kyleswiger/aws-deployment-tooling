# `static-site` module

Private S3 bucket served through CloudFront via Origin Access Control (OAC), with
an optional ACM certificate + Route 53 alias for a custom domain. This is the
SPA-hosting spine shared by every project built with this toolkit.

- No public S3 access — only the CloudFront distribution (matched by ARN) can read.
- SPA fallback (`403/404 → /index.html`) so a client-side router owns deep links.
- Long-lived TLS via DNS-validated ACM; the distribution only attaches an
  `ISSUED` cert (it depends on the validation resource, not the raw cert).

## Provider requirement

ACM certificates used by CloudFront **must** live in `us-east-1`. If your stack's
default region is elsewhere, pass a us-east-1 aliased provider:

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "site" {
  source        = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/static-site"
  providers     = { aws = aws.us_east_1 }
  name_prefix   = "myapp"
  custom_domain = "app.example.com"
  hosted_zone_id = "Z0123456789ABCDEF"
}
```

If your whole stack is already in `us-east-1`, the `providers` line is optional.

## Usage (CloudFront domain only)

```hcl
module "site" {
  source      = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/static-site"
  name_prefix = "myapp-dev"
}
```

## Deploying content

```bash
aws s3 sync ./dist "s3://$(terraform output -raw site_bucket)" --delete
aws cloudfront create-invalidation \
  --distribution-id "$(terraform output -raw cloudfront_distribution_id)" \
  --paths "/*"
```

For hashed-asset builds, prefer immutable caching on assets and no-cache on the
entry document (see `scripts/deploy.sh` and `scripts/run-ci.sh` in this repo).

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | string | — | Prefix for created resources. |
| `custom_domain` | string | `""` | Custom domain; empty serves on CloudFront domain. |
| `hosted_zone_id` | string | `""` | Route 53 zone ID; required with `custom_domain`. |
| `additional_aliases` | list(string) | `[]` | Extra aliases (e.g. `www.`); each is added as a SAN + alias record. |
| `price_class` | string | `PriceClass_100` | CloudFront price class. |
| `spa_fallback` | bool | `true` | Rewrite 403/404 to `/index.html`. |
| `tags` | map(string) | `{}` | Tags for taggable resources. |

## Outputs

`site_bucket`, `site_bucket_arn`, `cloudfront_distribution_id`,
`cloudfront_distribution_arn`, `cloudfront_domain_name`, `site_url`.
