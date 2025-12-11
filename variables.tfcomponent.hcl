################################################################################
# Terraform Stacks - Component Variables
# All input variables for the EKS multi-region stack components
# Reference: https://developer.hashicorp.com/terraform/language/stacks
################################################################################

#-------------------------------------------------------------------------------
# AWS Authentication (OIDC)
# These are provided by HCP Terraform for secure AWS access
#-------------------------------------------------------------------------------

variable "region" {
  type        = string
  description = "AWS region for deployment"
}

variable "role_arn" {
  type        = string
  ephemeral   = true
  description = "ARN of the IAM role for HCP Terraform to assume via OIDC"
}

variable "identity_token" {
  type        = string
  ephemeral   = true
  description = "OIDC identity token from HCP Terraform"
}

#-------------------------------------------------------------------------------
# EKS Cluster Configuration
#-------------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster (also used for VPC naming)"
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster"
  default     = "1.31"
}

#-------------------------------------------------------------------------------
# VPC Configuration
#-------------------------------------------------------------------------------

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "List of availability zones for the VPC subnets"
}

#-------------------------------------------------------------------------------
# Resource Tags
#-------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}

#-------------------------------------------------------------------------------
# EKS Cluster Access
# UPDATE THIS with your IAM ARN to get kubectl access to the clusters
# Get your ARN: aws sts get-caller-identity --query 'Arn' --output text
#-------------------------------------------------------------------------------

variable "admin_principal_arn" {
  type        = string
  description = "ARN of IAM user/role for kubectl access to EKS clusters"
  default     = "arn:aws:iam::865855451418:role/aws_oscar.medina_test-developer"
}
