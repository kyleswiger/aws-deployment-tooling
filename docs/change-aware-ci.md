# Change-aware CI/CD

A monorepo with a UI, one or more backends, and Terraform shouldn't rebuild and
redeploy everything on every commit. This pattern diffs the commit, decides which
components changed, and runs only the relevant work — with every skipped stage
logging why.

## The two scripts

### `detect-changes.sh`

Runs first. Picks a baseline commit (PR target branch, previous push commit, or
`HEAD~1`), diffs against it, and matches changed paths to component globs. It
writes `BUILD_UI`, `BUILD_API`, `BUILD_TERRAFORM`, … to `change-flags.env` and
exports them. Docs-only changes leave everything `false` so downstream stages skip
wholesale (`ANY_CODE_CHANGED=false`).

Baseline fallbacks are deliberate: if there's no usable git history (shallow
checkout, detached state), it forces a full build rather than deploying a partial
or wrong diff. Adapt the glob block to your repo's directory layout.

### `run-ci.sh <phase>`

Called once per CodeBuild phase (`install`, `prebuild`, `build`, `postbuild`).
Sources the flags and runs only what changed:

- **install** — start dockerd; `pip install` / `npm ci` only for changed components.
- **prebuild** — run the test gate; optional `terraform apply`; ECR login + cache pull.
- **build** — build changed images (SHA + `:latest` + `:cache` tags, BuildKit inline cache); build the UI.
- **postbuild** — push images; `lambda update-function-code`; `s3 sync` the UI with immutable-asset / no-cache-HTML headers; invalidate only `/index.html`.

## Image tagging strategy

Each build tags three ways:

- `:<commit-sha>` — immutable, the version the Lambda is pinned to (rollback target).
- `:latest` — moving pointer to the newest build.
- `:cache` — a `--cache-from` source so the next build reuses layers.

This gives layer caching *and* deterministic rollback from the same push.

## Why logic lives in scripts, not the buildspec

`buildspec.yml` is a thin four-line-per-phase shim that calls the scripts. That
keeps the real logic (a) unit-testable locally, (b) reusable from GitHub Actions
if you migrate off CodePipeline, and (c) readable in one place instead of scattered
across YAML.

## Wiring into CodePipeline

- Source stage: `OutputArtifactFormat = CODEBUILD_CLONE_REF` so CodeBuild gets a
  real git checkout (with history) — a plain ZIP artifact drops `.git` and breaks
  change detection.
- Build stage env: `git-credential-helper: yes` in the buildspec so git fetch
  works against the CodeStar connection.
- The CodeBuild project supplies component env vars (ECR URLs, bucket, distribution
  ID, Lambda names, `RUN_TERRAFORM_APPLY`) — keep that project's Terraform in your
  app repo; this toolkit ships the buildspec and scripts it drives.

## Custom runner image (optional)

To cut minutes off routine builds, bake Terraform and your Lambda dependencies
into a custom CodeBuild image
([`codebuild-runner.Dockerfile`](../templates/docker/codebuild-runner.Dockerfile)),
built by a **separate** CodeBuild project via
[`buildspec-codebuild-image.yml`](../templates/buildspec/buildspec-codebuild-image.yml).
Rebuild it only when the toolchain changes, not on every app build.

See [ephemeral-previews.md](ephemeral-previews.md) for the per-PR preview layer
that rides on top of this.
