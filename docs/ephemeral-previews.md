# Ephemeral PR preview environments

Every pull request gets its own frontend preview URL, backed by a single shared
dev backend. Full-stack isolation per PR would be slow and expensive; isolating
only the frontend is cheap and catches the vast majority of review-worthy changes.

## Architecture

```
  PR push ─► GitHub Actions (pr-preview.yml)
               ├─ lint + build UI (against dev API)
               ├─ pytest / unit tests
               ├─ Playwright smoke (+ optional backend e2e)
               └─ s3 sync ui/dist → s3://<dev-ui-bucket>/<safe-branch>/

  https://<safe-branch>.dev.example.com
     └─► CloudFront (function maps host → S3 prefix) ─► shared dev backend
```

- **Shared dev backend** — a persistent Terraform `dev` workspace/stack (API
  Lambda, data store, CloudFront router at `api.dev.example.com`).
- **Per-PR frontend** — [`pr-preview.yml`](../templates/github-workflows/pr-preview.yml)
  uploads the branch build to a per-branch S3 prefix on every push.
- **Routing** — a CloudFront function maps `<safe-branch>.dev.example.com` to the
  matching S3 prefix. (Keep this function in your app repo; it's project-specific.)
- **Cleanup** — [`pr-cleanup.yml`](../templates/github-workflows/pr-cleanup.yml)
  deletes the prefix when the PR closes.

## The three workflows

| Workflow | Trigger | Does |
|---|---|---|
| `pr-preview.yml` | PR opened/synchronized | Full CI gate + deploy branch UI to per-branch prefix, comment the URL. |
| `pr-cleanup.yml` | PR closed | Delete the branch's S3 prefix. |
| `deploy-dev-api.yml` | push to `main` (backend paths) or manual | Rebuild + `update-function-code` the shared dev backend Lambda. |

## Design choices that matter

- **A dev-backend outage must not red-X unrelated PRs.** The workflow health-checks
  the dev API and only *then* runs backend-dependent e2e; if it's unreachable, those
  specs are skipped with a warning, and lint/unit/smoke still gate the PR.
- **Build the UI once.** The `test` job uploads the built `ui/dist` as an artifact;
  the `preview` job downloads it instead of re-running `npm ci && npm run build`.
- **Feature-flag the deploy.** `ENABLE_EPHEMERAL_PREVIEW_DEPLOY` and
  `PLAYWRIGHT_E2E` repo variables let you land the workflow before the dev backend
  exists — CI still runs; the deploy no-ops until you flip the flag.
- **Safe branch names.** Branch names are lowercased and stripped to
  `[a-z0-9-]`, capped at 63 chars, so they're valid as both a DNS label and an S3
  prefix.

## One-time setup checklist

1. Deploy the shared dev backend (its own Terraform stack/workspace).
2. Create the dev UI bucket + the CloudFront host→prefix routing function.
3. Create the `github-oidc-role` and save its ARN as `AWS_GITHUB_ACTIONS_ROLE_ARN`.
4. Set repo variables `ENABLE_EPHEMERAL_PREVIEW_DEPLOY=true` and (optionally)
   `PLAYWRIGHT_E2E=true`.
5. Replace the `<DEV_API_URL>`, `<DEV_UI_BUCKET>`, `<PREVIEW_DOMAIN>`,
   `<NAME_PREFIX>`, `<API_REPO>` placeholders in the workflow templates.
