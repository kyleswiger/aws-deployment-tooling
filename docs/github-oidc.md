# Keyless CI with GitHub OIDC

GitHub Actions can prove its identity to AWS using a short-lived OIDC token, then
assume an IAM role via `sts:AssumeRoleWithWebIdentity`. No long-lived AWS access
keys are ever stored as repo secrets — the only secret is the role ARN, which is
useless without also being the trusted repo/branch.

## How it works

1. A workflow with `permissions: id-token: write` requests an OIDC token from
   GitHub. The token's `sub` claim encodes the repo and ref
   (`repo:owner/repo:ref:refs/heads/main`, `repo:owner/repo:pull_request`, or
   `repo:owner/repo:environment:prod`).
2. `aws-actions/configure-aws-credentials` exchanges that token for temporary AWS
   credentials by assuming the role.
3. The role's trust policy only allows `sub` values you listed, so only the
   intended workflows on the intended refs can assume it.

## Set it up

Use the [`github-oidc-role`](../terraform-modules/github-oidc-role) module:

```hcl
module "ci_role" {
  source      = "github.com/kyleswiger/aws-deployment-tooling//terraform-modules/github-oidc-role"
  name_prefix = "myapp-dev"
  github_repo = "kyleswiger/myapp"

  policy_statements = [
    { sid = "DeploySite", actions = ["s3:PutObject","s3:DeleteObject","s3:ListBucket","s3:GetObject"],
      resources = [module.site.site_bucket_arn, "${module.site.site_bucket_arn}/*"] },
    { sid = "Invalidate", actions = ["cloudfront:CreateInvalidation"],
      resources = [module.site.cloudfront_distribution_arn] },
    { sid = "PushImage", actions = ["ecr:GetAuthorizationToken"], resources = ["*"] },
    { sid = "PushImageRepo", actions = ["ecr:BatchCheckLayerAvailability","ecr:PutImage","ecr:InitiateLayerUpload","ecr:UploadLayerPart","ecr:CompleteLayerUpload","ecr:BatchGetImage","ecr:GetDownloadUrlForLayer"],
      resources = [module.api_lambda.ecr_repository_arn] },
    { sid = "UpdateLambda", actions = ["lambda:UpdateFunctionCode","lambda:GetFunction"],
      resources = [module.api_lambda.function_arn] },
  ]
}
```

Save `module.ci_role.role_arn` as the `AWS_GITHUB_ACTIONS_ROLE_ARN` repo secret,
then in every workflow:

```yaml
permissions:
  id-token: write
  contents: read
steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_GITHUB_ACTIONS_ROLE_ARN }}
      aws-region: us-east-1
```

## Gotchas

- **One OIDC provider per account.** `token.actions.githubusercontent.com` can
  only be registered once. If it already exists, set
  `create_oidc_provider = false` and the module looks it up.
- **`id-token: write` is mandatory.** Without it the token request fails and the
  role assumption never happens.
- **Scope tightly for prod.** The default trust (main + any PR) is fine for a dev
  role. For production, restrict `subject_claims` to a GitHub Environment so only
  a gated, reviewed deploy can assume the role.
- **ECR `GetAuthorizationToken` needs `Resource = "*"`.** It's an account-level
  action; the repo-scoped push actions go on the repo ARN.

Consumed by all three workflow templates in
the `kyleswiger/aws-reusable-workflows` repository.
