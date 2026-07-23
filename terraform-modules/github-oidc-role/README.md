# `github-oidc-role` module

Keyless CI for GitHub Actions. Creates (or reuses) the GitHub OIDC provider and
an IAM role that workflows assume via `sts:AssumeRoleWithWebIdentity` — so there
are **no long-lived AWS access keys** stored as repo secrets. The only secret you
store is the role ARN.

## Usage

```hcl
module "ci_role" {
  source      = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/github-oidc-role"
  name_prefix = "myapp-dev"
  github_repo = "kyleswiger/myapp"

  # Only create the provider once per account.
  create_oidc_provider = true

  policy_statements = [
    {
      sid       = "DeploySite"
      actions   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetObject"]
      resources = [module.site.site_bucket_arn, "${module.site.site_bucket_arn}/*"]
    },
    {
      sid       = "Invalidate"
      actions   = ["cloudfront:CreateInvalidation"]
      resources = [module.site.cloudfront_distribution_arn]
    },
  ]
}

output "github_actions_role_arn" {
  value = module.ci_role.role_arn
}
```

Save the output as the `AWS_GITHUB_ACTIONS_ROLE_ARN` repo secret, then in the
workflow:

```yaml
permissions:
  id-token: write   # required to request the OIDC token
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_GITHUB_ACTIONS_ROLE_ARN }}
      aws-region: us-east-1
```

## Notes

- **One provider per account.** An AWS account may have only one OIDC provider
  per issuer URL. If `token.actions.githubusercontent.com` already exists, set
  `create_oidc_provider = false` and the module looks it up instead.
- **Scope the trust.** The default `subject_claims` trusts `main` pushes and any
  PR. For production, narrow to a GitHub Environment
  (`repo:owner/repo:environment:prod`) so only gated deploys can assume the role.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | string | — | Role name prefix. |
| `github_repo` | string | — | `owner/repo`. |
| `create_oidc_provider` | bool | `true` | Create vs. look up the OIDC provider. |
| `subject_claims` | list(string) | `null` → main + PR | Trusted `sub` claim patterns. |
| `policy_statements` | list(object) | `[]` | Inline permissions the CI role needs. |
| `tags` | map(string) | `{}` | Role tags. |

## Outputs

`role_arn`, `role_name`, `oidc_provider_arn`.
