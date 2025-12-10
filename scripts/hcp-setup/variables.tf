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

variable "admin_principal_arn" {
  type        = string
  description = "ARN of IAM user/role for kubectl access to EKS clusters"

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:(user|role|assumed-role)/.+", var.admin_principal_arn))
    error_message = "admin_principal_arn must be a valid IAM user or role ARN"
  }
}

variable "variable_set_name" {
  type        = string
  description = "Name of the variable set to create"
  default     = "eks-stacks-config"
}
