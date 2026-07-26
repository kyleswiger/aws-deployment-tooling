# Default branch protection

A single ruleset definition, shared across every project repo, that makes `main`
merge-only and requires both agentic reviewers to have run.

- Definition: [`templates/github-rulesets/default-branch-protection.json`](../templates/github-rulesets/default-branch-protection.json)
- Applier: [`scripts/apply-branch-ruleset.sh`](../scripts/apply-branch-ruleset.sh)

## Apply it

```bash
./scripts/apply-branch-ruleset.sh --dry-run kyleswiger/some-repo   # preview
./scripts/apply-branch-ruleset.sh kyleswiger/some-repo             # apply
```

The script matches an existing ruleset by name and updates it in place, so it is
safe to re-run — that is also how you roll a change to the JSON out to every
repo at once.

## What the ruleset enforces

Scope is `~DEFAULT_BRANCH`, so it follows the default branch rather than hard-coding `main`.

| Rule | Effect |
| --- | --- |
| `pull_request` | No direct pushes to the default branch. Every change arrives via PR. |
| `required_approving_review_count: 1` | A PR needs one approving review to merge. |
| `dismiss_stale_reviews_on_push` | New commits invalidate prior approvals. |
| `required_review_thread_resolution` | Every review thread must be resolved before merge. |
| `required_status_checks` | `claude-review` and `gemini-pr-review` must both be green. |
| `strict_required_status_checks_policy` | The branch must be up to date with the base before merging. |
| `deletion` | The default branch cannot be deleted. |
| `non_fast_forward` | No force-pushes. |
| `required_linear_history` | No merge commits — hence `allowed_merge_methods` is squash/rebase only. |

## The two required checks

**`claude-review`** is the job id in `.github/workflows/claude-code-review.yml`. It is
pinned to `integration_id: 15368` (the GitHub Actions app) so nothing else can
post a status under that name. If you rename the job, the check name changes and
the ruleset will wait forever on a check that never reports.

**`gemini-pr-review`** is a commit status posted by the
[gemini-pr-reviewer](https://github.com/kyleswiger/gemini-pr-reviewer) Lambda:
`pending` the moment the webhook is received, then `success` once the review is
posted (or `error` if the pipeline fails). It carries no `integration_id`
because the Lambda writes it with a PAT rather than a GitHub App.

It fails closed. If the Lambda never reports back, the status stays `pending` and
the PR stays unmergeable — which is the intended behaviour for a review gate.

### Prerequisites per repo

A repo cannot satisfy this ruleset unless it also has:

1. `.github/workflows/claude-code-review.yml` with the job id `claude-review`, plus
   the `CLAUDE_CODE_OAUTH_TOKEN` repo secret (GitHub secrets cannot be copied between
   repos — set it per repo with `gh secret set`).
2. A repo webhook on the `pull_request` event pointing at the gemini-pr-reviewer
   endpoint, signed with the shared HMAC secret.

Apply the ruleset **after** both are in place. Applying it first leaves open PRs
blocked on checks that have no producer.

## Who can bypass

The repository `admin` role is the only bypass actor, and its `bypass_mode` is
`pull_request` rather than `always`. The distinction matters:

- **Cannot** push directly to the default branch. The push rules bind the owner too.
- **Can** merge a PR that has not met the requirements — no approving review,
  or a red/pending check.

That is deliberate: on a personal account the owner is the sole admin and GitHub
does not allow self-approval, so without this the owner could never merge their
own PR. The trade-off is that bypass is ruleset-wide — there is no per-rule
bypass in GitHub rulesets, so merging by bypass skips the required checks along
with the approval. Use it when you mean to.

## Private repositories

GitHub returns `403 Upgrade to GitHub Pro` for rulesets on private repos on the
free plan, and classic branch protection is gated the same way. The script
detects this and reports the repo as SKIPPED rather than failing the whole run.

Until those repos are public or the account is on Pro, the fallback is a soft
guard — a `CODEOWNERS` file plus a workflow that flags commits pushed to the
default branch outside a PR. It makes a violation visible after the fact; it
cannot prevent one. Re-run this script against those repos the moment the plan
changes; no edits to the JSON are needed.
