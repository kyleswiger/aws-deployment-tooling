# Keyless CI: a GitHub Actions workflow assumes this role via OIDC
# (sts:AssumeRoleWithWebIdentity), so no long-lived AWS keys are stored as repo
# secrets. The trust policy is scoped to specific `sub` claims (repo + ref/PR).

locals {
  default_subject_claims = [
    "repo:${var.github_repo}:ref:refs/heads/main",
    "repo:${var.github_repo}:pull_request",
  ]
  subject_claims = var.subject_claims != null ? var.subject_claims : local.default_subject_claims
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's OIDC thumbprints. AWS now validates the OIDC cert chain against the
  # library of trusted CAs and largely ignores this list, but the API still
  # requires at least one value.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

resource "aws_iam_role" "github_actions" {
  name = "${var.name_prefix}-github-actions-role"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = local.provider_arn
        }
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.subject_claims
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ci" {
  count = length(var.policy_statements) > 0 ? 1 : 0
  name  = "${var.name_prefix}-github-actions-policy"
  role  = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for s in var.policy_statements : merge(
        s.sid != null ? { Sid = s.sid } : {},
        {
          Effect   = s.effect
          Action   = s.actions
          Resource = s.resources
        }
      )
    ]
  })
}
