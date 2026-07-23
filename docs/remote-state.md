# Remote Terraform state

Terraform state records what's deployed. It must survive laptop loss, be lockable
so two applies can't race, and never be committed to git (it can contain
secrets). This toolkit stores it in an S3 bucket with a DynamoDB lock table.

## One-time bootstrap

The backend that stores state cannot itself be managed by that state, so create
it with plain AWS CLI, not Terraform:

```bash
./scripts/bootstrap-state.sh my-tfstate-bucket us-east-1 terraform-locks
```

[`bootstrap-state.sh`](../scripts/bootstrap-state.sh) is idempotent and gives the
bucket:

- **Blocked public access** (all four settings).
- **Versioning** — the real recovery mechanism; roll back a corrupted or
  truncated state to a prior object version.
- **Default encryption** (AES256, bucket keys on).
- **A TLS-only bucket policy** (denies `aws:SecureTransport = false`).
- **A 90-day noncurrent-version lifecycle** so it doesn't grow forever.
- **A `PAY_PER_REQUEST` DynamoDB lock table** (`LockID` hash key).

## Wiring it up

### Direct backend block (single environment / CodePipeline stacks)

```hcl
terraform {
  backend "s3" {
    bucket         = "my-tfstate-bucket"
    key            = "myapp/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

### Profile-driven toggle (deploy.sh pattern)

A backend block can't take variables, so [`deploy.sh`](../scripts/deploy.sh)
**generates `infra/backend.tf`** (gitignored) based on whether the active profile
has a `backend.hcl`:

- `backend.hcl` present → remote S3 state (`terraform init -backend-config=…`).
- absent → local state file inside the profile directory.

This lets the same repo run with throwaway local state for a demo and real remote
state for an actual deployment, chosen entirely by the profile.

The script also refuses to start from empty remote state while a non-empty local
state file still exists — that mismatch would orphan every deployed resource. It
prints the exact `terraform init -migrate-state` command to reconcile.

## Terraform ≥ 1.10 note

Terraform 1.10+ can lock with an S3 object (`use_lockfile = true`) and drop the
DynamoDB table entirely. The bootstrap still creates the table for compatibility
with older versions; remove it if your whole fleet is on ≥ 1.10.
