# HTTP API (API Gateway v2) with a Cognito JWT authorizer in front of a single
# proxy-integrated Lambda. Cheaper and lower-latency than a REST API; the JWT
# authorizer validates Cognito access/ID tokens at the edge with no authorizer
# Lambda to run or pay for.

resource "aws_apigatewayv2_api" "main" {
  name          = var.name_prefix
  protocol_type = "HTTP"
  tags          = var.tags

  cors_configuration {
    allow_origins = compact(var.cors_allow_origins)
    allow_methods = var.cors_allow_methods
    allow_headers = var.cors_allow_headers
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito"

  jwt_configuration {
    audience = [var.cognito_audience]
    issuer   = var.cognito_issuer
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arn
  payload_format_version = "2.0"
}

# Explicit methods only — see var.route_methods for why OPTIONS is excluded.
resource "aws_apigatewayv2_route" "proxy" {
  for_each           = toset(var.route_methods)
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "${each.key} /{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
  tags        = var.tags
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
