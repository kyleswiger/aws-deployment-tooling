# `preview-substrate` module

The once-per-site infrastructure that makes **real per-PR preview environments**
a fast-path deploy. Apply this module once; after that, deploying a preview is
an `aws s3 sync` plus a Lambda create/update — seconds, not minutes — with zero
fixed monthly cost (CloudFront, Lambda, and Function URLs are all pay-per-use).

Each open PR gets:

- **Frontend** at `https://pr-<N>.<preview_domain>` — one shared CloudFront
  distribution aliased to `*.<preview_domain>`; a viewer-request CloudFront
  function maps the `pr-<N>` host onto `s3://<bucket>/previews/pr-<N>/` and
  rewrites extensionless URIs to that preview's `index.html` (per-prefix SPA
  fallback, which distribution-wide `custom_error_response` cannot do).
  Because the rewrite happens at viewer-request, the rewritten URI is the cache
  key — previews never share cached objects, and Vite's root-absolute
  `/assets/…` paths work without setting `base`.
- **Backend** as a per-PR Lambda named `<name_prefix>-preview-pr-<N>` with a
  Function URL, created by CI using the shared execution role this module
  provisions. CI never needs `iam:CreateRole` — it only passes the role.

The companion CI half lives in
[`kyleswiger/aws-reusable-workflows`](https://github.com/kyleswiger/aws-reusable-workflows)
(`preview-deploy.yml` / `preview-cleanup.yml`).

## Provider requirement

The wildcard ACM certificate is attached to CloudFront and **must** live in
`us-east-1`; per-PR Lambdas must be created in the same region as this module.
If your stack's default region is elsewhere, pass a us-east-1 aliased provider
(`providers = { aws = aws.us_east_1 }`) as with `static-site`.

## Usage

```hcl
module "preview" {
  source         = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/preview-substrate"
  name_prefix    = "myapp"
  preview_domain = "preview.example.com"
  hosted_zone_id = data.aws_route53_zone.main.zone_id

  # Data-tier access for the per-PR backend Lambdas (point previews at the
  # dev/preview data tier, never prod):
  preview_lambda_policy_statements = [
    {
      sid       = "PreviewTable"
      actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
      resources = [aws_dynamodb_table.preview.arn, "${aws_dynamodb_table.preview.arn}/index/*"]
    },
  ]
}

# Grant the CI role its preview permissions:
module "github_oidc" {
  source            = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/github-oidc-role"
  name_prefix       = "myapp"
  github_repo       = "kyleswiger/myapp"
  policy_statements = concat(local.ci_statements, module.preview.ci_policy_statements)
}
```

## Cleanup story

Previews are removed two ways, belt and braces:

1. The `preview-cleanup.yml` workflow deletes the Lambda and the S3 prefix when
   the PR closes.
2. A lifecycle rule expires anything under `previews/` after
   `expire_previews_after_days` (default 14) days, so a cleanup run that never
   fired cannot leak objects forever. Pushes to a still-open PR re-upload its
   objects and reset the clock. Orphaned Lambdas cost nothing while idle.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | string | — | Prefix for created resources; per-PR Lambdas are `<name_prefix>-preview-pr-<N>`. |
| `preview_domain` | string | — | Parent domain for previews (e.g. `preview.example.com`). |
| `hosted_zone_id` | string | — | Route 53 zone that owns `preview_domain`. |
| `price_class` | string | `PriceClass_100` | CloudFront price class. |
| `expire_previews_after_days` | number | `14` | Backstop expiry for `previews/` objects; `0` disables. |
| `preview_lambda_policy_statements` | list(object) | `[]` | Data-tier IAM statements for the shared preview Lambda execution role. |
| `tags` | map(string) | `{}` | Tags for taggable resources. |

## Outputs

`preview_bucket`, `preview_bucket_arn`, `cloudfront_distribution_id`,
`cloudfront_distribution_arn`, `preview_domain`,
`preview_lambda_exec_role_arn`, `preview_lambda_exec_role_name`, and
`ci_policy_statements` — the least-privilege statements the CI role needs
(S3 sync scoped to the preview bucket, invalidation scoped to the preview
distribution, Lambda lifecycle scoped to `<name_prefix>-preview-pr-*`, and
`iam:PassRole` scoped to the shared execution role), shaped for
`github-oidc-role`'s `policy_statements` input.
