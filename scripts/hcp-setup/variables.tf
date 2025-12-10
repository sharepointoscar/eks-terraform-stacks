################################################################################
# Input Variables
################################################################################

variable "tfc_organization" {
  type        = string
  description = "HCP Terraform organization name"
}

variable "tfc_project_name" {
  type        = string
  description = "HCP Terraform project name where the Stack will be created"
}

variable "aws_role_arn" {
  type        = string
  description = "ARN of the IAM role for OIDC authentication (from setup-aws-oidc.sh)"

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.aws_role_arn))
    error_message = "aws_role_arn must be a valid IAM role ARN (arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME)"
  }
}

variable "variable_set_name" {
  type        = string
  description = "Name of the variable set to create"
  default     = "eks-stacks-config"
}

# Note: admin_principal_arn is NOT configured here.
# Varset values are ephemeral in Terraform Stacks and cannot persist to state.
# admin_principal_arn must be set as a Stack input variable in HCP Terraform UI
# to grant your IAM role kubectl access to the EKS clusters.
