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
  #   key            = "container-cicd-stack/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "myapp-tfstate-locks"
  #   encrypt        = true
  # }
}

# us-east-1 is required for CloudFront's ACM certificate (created by static-site
# with this default provider).
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
      Example   = "container-cicd-stack"
    }
  }
}
