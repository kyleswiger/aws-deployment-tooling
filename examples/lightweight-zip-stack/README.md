# Example: lightweight zip-Lambda stack

The smallest complete deployment this toolkit supports: a static SPA, a Cognito
user pool, and one zip-packaged API Lambda behind API Gateway v2 — shipped by
the profile-driven [`deploy.sh`](../../scripts/deploy.sh). Reach for this when
the backend is a single small Node/Python handler and a solo or small team owns
the deploys.

```
Route53 ─► CloudFront ─► S3 (private, OAC)         module.site
browser ─► Cognito JWT ─► API Gateway v2 ─► Lambda module.auth / module.api / module.api_lambda
```

## Modules used

| Module | Role |
|---|---|
| [`static-site`](../../terraform-modules/static-site) | Private S3 + CloudFront (OAC), optional ACM + Route53 alias. |
| [`cognito-user-pool`](../../terraform-modules/cognito-user-pool) | Invite-only pool + SPA client; callback/logout URLs wired to the site. |
| [`lambda-zip`](../../terraform-modules/lambda-zip) | Zip-packaged Lambda + role + logs. |
| [`http-api-cognito`](../../terraform-modules/http-api-cognito) | API Gateway v2 + Cognito JWT authorizer → the Lambda. |

## Run it

```bash
cp terraform.tfvars.example terraform.tfvars   # then edit
terraform init
terraform plan
terraform apply
```

Then wire the outputs into your frontend build (`api_url`, `user_pool_id`,
`user_pool_client_id`, `cognito_issuer`) and deploy the SPA:

```bash
# from your app repo, after copying scripts/deploy.sh + a profile dir:
./deploy.sh --profile ../myapp-profile
```

`deploy.sh` rebuilds the backend zip, runs `terraform apply`, `s3 sync`s the
built frontend with immutable-asset / no-cache-HTML headers, and invalidates
`/index.html`.

## Notes

- **`zip_path` must resolve at plan time.** Terraform hashes the file to detect
  changes. A stub `placeholder/api.zip` ships with this example so `plan` works
  immediately; point `api_zip_path` at your real build once you have one. In
  steady state `deploy.sh` builds it for you.
- **Custom domain is optional.** Leave `custom_domain`/`hosted_zone_id` empty to
  serve from the CloudFront domain. Set both to get an ACM cert (created here in
  us-east-1) and a Route53 alias.
- **No CI role.** This path deploys from your workstation. For keyless GitHub
  Actions deploys, see [`../container-cicd-stack`](../container-cicd-stack) and
  [`docs/github-oidc.md`](../../docs/github-oidc.md).
- **Adding a data store.** Create your table/db in this root and grant the
  Lambda access via the `policy_statements` input on `module.api_lambda` — see
  the container example for the pattern.
