terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # archive is a local provider (no API calls) used by the lambda module
    # to zip handler.py at plan time and track source_code_hash changes.
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.7"
    }
  }

  # For the mock setup we keep state local. In a real multi-person project
  # you'd point this at an S3 backend (ironically, one you'd also manage
  # with Terraform, created once by hand or via `terraform { backend = "local" }`
  # bootstrapping).
  backend "local" {
    path = "terraform.tfstate"
  }
}

# ----------------------------------------------------------------------------
# LOCALSTACK MODE (default)
# Every AWS API call is redirected to the LocalStack container on
# localhost:4566. access_key/secret_key are dummy values — LocalStack
# doesn't check them, but the AWS provider insists they be non-empty.
#
# To point this at REAL AWS instead:
#   1. Delete the `endpoints {}` block and the four `skip_*` / `s3_use_path_style` lines
#      from both provider blocks below.
#   2. Replace access_key/secret_key with a real credentials chain
#      (env vars, ~/.aws/credentials, or an assumed role) — never hardcode them.
# ----------------------------------------------------------------------------

provider "aws" {
  region                      = var.primary_region
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    cloudwatch = "http://localhost:4566"
    ec2        = "http://localhost:4566"
    iam        = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    logs       = "http://localhost:4566"
    rds        = "http://localhost:4566"
    s3         = "http://localhost:4566"
    sts        = "http://localhost:4566"
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    cloudwatch = "http://localhost:4566"
    ec2        = "http://localhost:4566"
    iam        = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    logs       = "http://localhost:4566"
    rds        = "http://localhost:4566"
    s3         = "http://localhost:4566"
    sts        = "http://localhost:4566"
  }
}

provider "archive" {}

# Grafana runs as a Docker container alongside LocalStack.
# `make up` starts both; Terraform talks to Grafana's HTTP API on port 3000.
provider "grafana" {
  url  = "http://localhost:3000"
  auth = "admin:admin"
}

