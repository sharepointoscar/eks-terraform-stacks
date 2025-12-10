################################################################################
# HCP Terraform Variable Set Setup
# Provider version constraints
################################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.71"
    }
  }
}
