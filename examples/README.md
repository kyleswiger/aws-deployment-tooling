# Examples

Three complete, end-to-end stacks that wire the [`terraform-modules`](../terraform-modules)
together the way a real project would. Each is a self-contained Terraform root
you can `init` / `plan` against your own account.

| Example | Backend packaging | Deploy driver | Use when |
|---|---|---|---|
| [`lightweight-zip-stack`](lightweight-zip-stack) | `lambda-zip` | profile-driven [`deploy.sh`](../scripts/deploy.sh) | Small Node/Python handler, one service, solo or small team. |
| [`container-cicd-stack`](container-cicd-stack) | `lambda-container` | change-aware [CI](../docs/change-aware-ci.md) + GitHub OIDC | Native/heavy deps, multiple services, PR previews. |
| [`ecs-fargate-stack`](ecs-fargate-stack) | `ecs-fargate-service` | GitHub OIDC → ECR push + `ecs update-service` | WebSockets, persistent BEAM/JVM, long-lived connections. |

The two Lambda stacks provision the same spine — a private-S3/CloudFront SPA, a Cognito
JWT user pool, and an API Gateway v2 → Lambda backend. They differ only on the
axis the [methodology](../docs/methodology.md) calls out: how the Lambda is
packaged and shipped. The ECS stack instead provisions an ALB-backed Fargate
service, ECR repository, and GitHub OIDC deploy role; it does not create a SPA,
Cognito user pool, API Gateway, or Lambda.

## Running an example

```bash
cd examples/lightweight-zip-stack
cp terraform.tfvars.example terraform.tfvars   # then edit
terraform init
terraform plan
```

The two Lambda roots pin the AWS provider to **us-east-1** on purpose: CloudFront requires
its ACM certificate in that region, and the `static-site` module creates the
cert with the root's default provider. Deploy the SPA bucket/distribution from
us-east-1; you can host data-plane resources elsewhere with additional
`provider` aliases if you need to. The ECS example also defaults to us-east-1,
but its ALB certificate is regional, so that example can use another region.

## What the examples deliberately leave out

- **Remote state backend.** Each root ships a commented `backend "s3"` block.
  Run [`scripts/bootstrap-state.sh`](../scripts/bootstrap-state.sh) once, then
  uncomment and fill it. Left commented so `terraform init` works with zero
  setup while you're evaluating.
- **The data store.** These examples stop at the application backend — DynamoDB tables, RDS,
  etc. are app-specific. Grant the Lambda or ECS task access via its `policy_statements`
  input (shown in the container example).
- **Real application code.** `lightweight-zip-stack` points `zip_path` at a
  placeholder; `container-cicd-stack` lets CI own the image (see the
  `lifecycle { ignore_changes }` note in its README). `ecs-fargate-stack` needs
  a real container image and an explicit CI handoff to adopt Terraform
  task-template changes; see its [ownership notes](ecs-fargate-stack#task-definition-handoff).
