# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is
A **toolkit, not an application**. Nothing here is deployed from this repo — the Terraform modules, scripts, and examples are copied or sourced into other projects. Files carry `<PLACEHOLDER>` tokens and `ADAPT:` comments marking where a consuming project fills in its own names. 

## Master Plan Context
As part of our decoupling strategy:
1. **GitHub Actions** have been abstracted out to `kyleswiger/aws-reusable-workflows`.
2. This repository serves strictly as the **Public Source of Truth for Terraform Modules** (e.g. `lambda-container`, `http-api-cognito`).
3. External private projects (like `sportscard-intelligence` or `jackscabin-mgmt`) source these modules via remote references.

## Verification commands
There is no build or test suite. Changes are verified with:

```bash
terraform fmt -check -recursive          # run from repo root; must pass clean
bash -n scripts/*.sh                     # shell syntax check

# Validate a single module or example (offline, no credentials needed):
cd terraform-modules/static-site && terraform init -backend=false && terraform validate

# Plan a full example against a real account:
cd examples/lightweight-zip-stack && cp terraform.tfvars.example terraform.tfvars \
  && terraform init && terraform plan
```

The repo has **no `.gitignore`** (`templates/gitignore.template` is for consumer projects), so `terraform init` leaves untracked `.terraform/` and `.terraform.lock.hcl` behind — delete them after validating.
