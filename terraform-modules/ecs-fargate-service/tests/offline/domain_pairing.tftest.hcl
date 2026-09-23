# Terraform >= 1.11. All runs are mock-provider plans: no credentials or AWS calls.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix = "domain-pairing-test"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
}

# Supply the computed DNS-validation collection at plan time, so for_each can
# be evaluated without issuing a certificate.
override_resource {
  target          = aws_acm_certificate.this
  override_during = plan
  values = {
    arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000001"
    domain_validation_options = [{
      domain_name           = "app.example.com"
      resource_record_name  = "_validation.app.example.com"
      resource_record_type  = "CNAME"
      resource_record_value = "_validation.acm-validations.aws."
    }]
  }
}

run "both_empty_uses_http" {
  command = plan

  assert {
    condition     = length(aws_acm_certificate.this) == 0 && length(aws_lb_listener.https) == 0 && length(aws_route53_record.alias) == 0
    error_message = "No domain should create no certificate, HTTPS listener, or aliases."
  }

  assert {
    condition     = one(aws_lb_listener.http.default_action).type == "forward"
    error_message = "No domain should forward HTTP directly to the app."
  }
}

run "both_set_uses_https" {
  command = plan

  variables {
    custom_domain  = "app.example.com"
    hosted_zone_id = "Z0123456789ABCDEF"
  }

  assert {
    condition     = length(aws_acm_certificate.this) == 1 && length(aws_lb_listener.https) == 1 && length(aws_route53_record.alias) == 2
    error_message = "A complete domain pair should create TLS and DNS resources."
  }

  assert {
    condition     = one(aws_lb_listener.http.default_action).type == "redirect" && output.url == "https://app.example.com"
    error_message = "A complete domain pair should redirect HTTP and expose an HTTPS URL."
  }
}

run "domain_without_zone_is_rejected" {
  command = plan

  variables {
    custom_domain = "app.example.com"
  }

  expect_failures = [aws_lb.this]
}

run "publishes_task_template_for_ci" {
  command = plan

  variables {
    create_ecr_repository = false
    image_repository_url  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/app"
    cpu                   = 512
    memory                = 1024
    command               = ["bin/app", "start"]
    environment           = { APP_MODE = "production" }
    secrets               = { APP_SECRET = "arn:aws:ssm:us-east-1:123456789012:parameter/app/secret" }
  }

  override_resource {
    target          = aws_ecs_cluster.this
    override_during = plan
    values = {
      arn = "arn:aws:ecs:us-east-1:123456789012:cluster/domain-pairing-test"
      id  = "arn:aws:ecs:us-east-1:123456789012:cluster/domain-pairing-test"
    }
  }

  override_resource {
    target          = aws_ecs_task_definition.this
    override_during = plan
    values = {
      arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/domain-pairing-test:7"
    }
  }

  assert {
    condition     = output.task_definition_arn == "arn:aws:ecs:us-east-1:123456789012:task-definition/domain-pairing-test:7"
    error_message = "CI must receive the Terraform template's exact revision ARN."
  }

  assert {
    condition     = aws_ecs_task_definition.this.cpu == "512" && aws_ecs_task_definition.this.memory == "1024"
    error_message = "The published template must carry the requested task resources."
  }

  assert {
    condition = (
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment[0].value == "production" &&
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].secrets[0].valueFrom == var.secrets.APP_SECRET &&
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].command[0] == "bin/app"
    )
    error_message = "The Terraform template must carry environment, secret references, and command for explicit CI adoption."
  }
}

run "zone_without_domain_is_rejected" {
  command = plan

  variables {
    hosted_zone_id = "Z0123456789ABCDEF"
  }

  expect_failures = [aws_lb.this]
}
