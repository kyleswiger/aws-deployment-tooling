# Preview substrate: the once-per-site, slow-to-create infrastructure that
# makes per-PR preview environments a fast-path deploy (an `aws s3 sync` plus a
# Lambda create/update — no Terraform, no CloudFront changes, no DNS per PR).
#
#   - Private S3 bucket holding every preview under previews/pr-<N>/
#   - One CloudFront distribution aliased to *.<preview_domain>, with a
#     viewer-request function that maps pr-<N>.<preview_domain> onto the
#     matching S3 prefix (and rewrites extensionless URIs to that prefix's
#     index.html for SPA routing)
#   - Wildcard ACM certificate + wildcard Route 53 alias
#   - A shared execution role for the per-PR backend Lambdas
#   - `ci_policy_statements` output shaped for the github-oidc-role module, so
#     CI can deploy previews with least privilege
#
# ACM certificates for CloudFront MUST live in us-east-1; configure this
# module's aws provider accordingly (see README). Per-PR Lambdas must be
# created in the same region as this module.

data "aws_caller_identity" "current" {}

locals {
  wildcard_domain = "*.${var.preview_domain}"
  # Region is wildcarded to avoid the deprecated aws_region .name / newer-only
  # .region split across provider versions; account + name pattern still scope it.
  lambda_arn_match = "arn:aws:lambda:*:${data.aws_caller_identity.current.account_id}:function:${var.name_prefix}-preview-pr-*"
}

# --------------------------------------------------------------------------- #
# Preview bucket
# --------------------------------------------------------------------------- #
resource "aws_s3_bucket" "previews" {
  bucket_prefix = "${var.name_prefix}-previews-"
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "previews" {
  bucket                  = aws_s3_bucket.previews.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "previews" {
  count  = var.expire_previews_after_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.previews.id

  rule {
    id     = "expire-stale-previews"
    status = "Enabled"
    filter {
      prefix = "previews/"
    }
    expiration {
      days = var.expire_previews_after_days
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 3
    }
  }
}

# --------------------------------------------------------------------------- #
# CloudFront: one distribution for every preview, routed by Host header
# --------------------------------------------------------------------------- #
resource "aws_cloudfront_origin_access_control" "previews" {
  name                              = "${var.name_prefix}-previews"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Maps pr-<N>.<preview_domain> onto s3://<bucket>/previews/pr-<N>/. Runs at
# viewer-request, so the rewritten URI is also the cache key — previews never
# share cached objects. Extensionless URIs become the preview's own index.html,
# which is the SPA fallback custom_error_response can't do per-prefix.
resource "aws_cloudfront_function" "preview_router" {
  name    = "${var.name_prefix}-preview-router"
  runtime = "cloudfront-js-2.0"
  publish = true
  comment = "Route pr-<N>.${var.preview_domain} to its S3 prefix"
  code    = <<-EOF
    function handler(event) {
      var request = event.request;
      var host = request.headers.host ? request.headers.host.value : "";
      var suffix = ".${var.preview_domain}";

      if (host.endsWith(suffix)) {
        var sub = host.slice(0, -suffix.length);
        if (/^[a-z0-9][a-z0-9-]{0,62}$/.test(sub)) {
          var uri = request.uri;
          var last = uri.split("/").pop();
          if (!last.includes(".")) {
            uri = "/index.html";
          }
          request.uri = "/previews/" + sub + uri;
        }
      }
      return request;
    }
  EOF
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "previews" {
  enabled     = true
  price_class = var.price_class
  aliases     = [local.wildcard_domain]
  comment     = "${var.name_prefix} PR previews"
  tags        = var.tags

  origin {
    domain_name              = aws_s3_bucket.previews.bucket_regional_domain_name
    origin_id                = "s3-previews"
    origin_access_control_id = aws_cloudfront_origin_access_control.previews.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-previews"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.preview_router.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Reference the validation resource (not the cert directly) so CloudFront
    # only ever attaches a cert that has reached ISSUED.
    acm_certificate_arn      = aws_acm_certificate_validation.previews.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

data "aws_iam_policy_document" "previews_bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.previews.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.previews.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "previews" {
  bucket = aws_s3_bucket.previews.id
  policy = data.aws_iam_policy_document.previews_bucket.json
}

# --------------------------------------------------------------------------- #
# Wildcard certificate + DNS
# --------------------------------------------------------------------------- #
resource "aws_acm_certificate" "previews" {
  domain_name       = local.wildcard_domain
  validation_method = "DNS"
  tags              = var.tags
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.previews.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "previews" {
  certificate_arn         = aws_acm_certificate.previews.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_route53_record" "previews" {
  zone_id = var.hosted_zone_id
  name    = local.wildcard_domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.previews.domain_name
    zone_id                = aws_cloudfront_distribution.previews.hosted_zone_id
    evaluate_target_health = false
  }
}

# --------------------------------------------------------------------------- #
# Shared execution role for per-PR preview Lambdas. CI passes this role to
# every <name_prefix>-preview-pr-<N> function it creates — CI itself never
# needs iam:CreateRole.
# --------------------------------------------------------------------------- #
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "preview_lambda_exec" {
  name               = "${var.name_prefix}-preview-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "preview_lambda_logs" {
  role       = aws_iam_role.preview_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "preview_lambda_data" {
  count = length(var.preview_lambda_policy_statements) > 0 ? 1 : 0

  dynamic "statement" {
    for_each = var.preview_lambda_policy_statements
    content {
      sid       = statement.value.sid
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "preview_lambda_data" {
  count  = length(var.preview_lambda_policy_statements) > 0 ? 1 : 0
  name   = "${var.name_prefix}-preview-lambda-data"
  role   = aws_iam_role.preview_lambda_exec.id
  policy = data.aws_iam_policy_document.preview_lambda_data[0].json
}
