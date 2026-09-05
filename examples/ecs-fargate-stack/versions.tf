terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Remote state — bootstrap once with scripts/bootstrap-state.sh, then
  # uncomment and fill in.
  #
  # backend "s3" {
  #   bucket         = "myapp-tfstate"
  #   key            = "ecs-fargate-stack/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "myapp-tfstate-locks"
  #   encrypt        = true
  # }
}

# Any region works: the ALB certificate is regional (no us-east-1 requirement,
# unlike CloudFront). us-east-1 is where this toolkit's default VPC lives.
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
      Example   = "ecs-fargate-stack"
    }
  }
}
