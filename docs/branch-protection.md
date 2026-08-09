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

## Where it is applied

Seven repos are in scope for the agentic review gates. `kyleswiger` is a user
account, not an org, so there are no org-level rulesets or shared secrets —
every row below is configured per repo.

| Repo | Visibility | Claude | Gemini | Ruleset | Guard fallback |
| --- | --- | --- | --- | --- | --- |
| `aws-deployment-tooling` | public | yes | yes | applied | n/a |
| `cabin-management` | public | yes | yes | **not applied** | n/a |
| `gemini-pr-reviewer` | public | yes | yes | **not applied** | n/a |
| `cicd-automation` | private | yes | yes | 403 (needs Pro) | **missing** |
| `jackscabin-mgmt` | private | yes | yes | 403 (needs Pro) | yes |
| `sportscard-intelligence` | private | yes | yes | 403 (needs Pro) | yes (older) |
| `kswiger-dev` | private | yes | **pending** | 403 (needs Pro) | yes |

Three gaps are live as of the last survey:

- **`cabin-management` and `gemini-pr-reviewer` are public and eligible, but have
  no ruleset.** Nothing is blocking them — run the script against both.
- **`cicd-automation` is private with no `main-push-guard.yml`.** It has neither
  the ruleset (403) nor the fallback, so direct pushes to its `main` are
  currently invisible.
- **`kswiger-dev` has the workflows committed but no `CLAUDE_CODE_OAUTH_TOKEN`
  secret and no Gemini webhook yet**, so the Claude job fails at auth and no
  `gemini-pr-review` status is ever posted. Both are per-repo manual steps.

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
guard: `main-push-guard.yml` (from `kyleswiger/aws-reusable-workflows`),
which runs on every push to `main`, asks GitHub whether each pushed commit has an
associated PR, and opens an issue plus fails the run when one does not. It makes
a violation visible after the fact; it cannot prevent one.

Two variants of the guard are in circulation, and the difference matters. The
hardened one (currently in `jackscabin-mgmt` and `kswiger-dev`) additionally
handles the two cases where the original silently passes:

- **Force-push.** Rewinding `main` to an ancestor produces an empty `commits`
  array, so the per-commit loop finds nothing to object to and reports a clean
  bill of health for exactly the bypass the guard exists to catch. The hardened
  version treats `github.event.forced` as a finding in its own right.
- **The 20-commit payload cap.** The push event truncates `commits` at 20, so a
  larger push hides everything past the twentieth. The hardened version asks the
  compare API for the real range and falls back to the payload only if that 404s.

`sportscard-intelligence` still carries the original — worth backporting.

Pair it with a `.github/CODEOWNERS` file. Be aware that code owners is itself a
paid feature on private repos — on the free plan the file is inert and only
starts doing anything once the account is on Pro. It is worth committing now so
the repo is ready, but the workflow is what actually provides coverage today.

Once the plan changes, run `apply-branch-ruleset.sh` against those repos and
delete the guard workflow. No edits to the ruleset JSON are needed.
