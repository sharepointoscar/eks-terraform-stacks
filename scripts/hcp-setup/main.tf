################################################################################
# HCP Terraform Variable Set Setup
# Creates the variable set required for the EKS Terraform Stack
################################################################################

#-------------------------------------------------------------------------------
# Provider Configuration
# Authentication via TFE_TOKEN environment variable
# Get a token from: https://app.terraform.io/app/settings/tokens
#-------------------------------------------------------------------------------

provider "tfe" {
  # hostname defaults to app.terraform.io
  # token is read from TFE_TOKEN environment variable
}

#-------------------------------------------------------------------------------
# Data Sources
#-------------------------------------------------------------------------------

data "tfe_project" "stack_project" {
  name         = var.tfc_project_name
  organization = var.tfc_organization
}

#-------------------------------------------------------------------------------
# Variable Set
#-------------------------------------------------------------------------------

resource "tfe_variable_set" "eks_stacks_config" {
  name         = var.variable_set_name
  description  = "Configuration variables for the EKS multi-region Terraform Stack"
  organization = var.tfc_organization
}

#-------------------------------------------------------------------------------
# Variables within the Variable Set
#-------------------------------------------------------------------------------

resource "tfe_variable" "aws_role_arn" {
  key             = "aws_role_arn"
  value           = var.aws_role_arn
  category        = "terraform"
  description     = "ARN of the IAM role for HCP Terraform OIDC authentication"
  variable_set_id = tfe_variable_set.eks_stacks_config.id
}

resource "tfe_variable" "admin_principal_arn" {
  key             = "admin_principal_arn"
  value           = var.admin_principal_arn
  category        = "terraform"
  description     = "ARN of IAM user/role for kubectl access to EKS clusters"
  variable_set_id = tfe_variable_set.eks_stacks_config.id
}

#-------------------------------------------------------------------------------
# Assign Variable Set to Project
#-------------------------------------------------------------------------------

resource "tfe_project_variable_set" "assign_to_project" {
  project_id      = data.tfe_project.stack_project.id
  variable_set_id = tfe_variable_set.eks_stacks_config.id
}
