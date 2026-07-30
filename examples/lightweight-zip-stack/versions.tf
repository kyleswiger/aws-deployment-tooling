terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Remote state — bootstrap once with scripts/bootstrap-state.sh, then
  # uncomment and fill in. Left commented so `terraform init` works with no
  # prior setup while evaluating.
  #
  # backend "s3" {
  #   bucket         = "myapp-tfstate"
  #   key            = "lightweight-zip-stack/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "myapp-tfstate-locks"
  #   encrypt        = true
  # }
}

# us-east-1 is required: CloudFront's ACM certificate must live there, and the
# static-site module creates that cert with this default provider.
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
      Example   = "lightweight-zip-stack"
    }
  }
}
