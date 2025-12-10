################################################################################
# EKS Deployment (Single Region for Testing)
# Deploys the complete stack (VPC + EKS + Addons) to one AWS region
################################################################################

#-------------------------------------------------------------------------------
# OIDC Authentication for AWS
# HCP Terraform uses this token to assume the AWS IAM role
#-------------------------------------------------------------------------------

identity_token "aws" {
  audience = ["aws.workload.identity"]
}

################################################################################
# Variable Set Configuration
# Created by scripts/hcp-setup - contains aws_role_arn for OIDC authentication
# See README.md Step 4 for setup instructions
################################################################################

store "varset" "config" {
  name     = "eks-stacks-config"
  category = "terraform"
}

# #-------------------------------------------------------------------------------
# # US East (N. Virginia) - us-east-1 (Commented out for single-region testing)
# #-------------------------------------------------------------------------------
#
# deployment "use1" {
#   destroy = false
#
#   inputs = {
#     region          = "us-east-1"
#     cluster_name    = "eks-use1"
#     cluster_version = "1.30"
#     vpc_cidr        = "10.0.0.0/16"
#     azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
#     tags = {
#       Environment = "workshop"
#       Region      = "us-east-1"
#       ManagedBy   = "terraform-stacks"
#     }
#
#     # OIDC authentication
#     role_arn       = store.varset.config.aws_role_arn
#     identity_token = identity_token.aws.jwt
#   }
# }

#-------------------------------------------------------------------------------
# US West (Oregon) - us-west-2
#-------------------------------------------------------------------------------

deployment "usw2" {
  destroy = false

  inputs = {
    region          = "us-west-2"
    cluster_name    = "eks-usw2"
    cluster_version = "1.30"
    vpc_cidr        = "10.1.0.0/16"
    azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
    tags = {
      Environment = "workshop"
      Region      = "us-west-2"
      ManagedBy   = "terraform-stacks"
    }

    # OIDC authentication
    role_arn       = store.varset.config.aws_role_arn
    identity_token = identity_token.aws.jwt
  }
}

# #-------------------------------------------------------------------------------
# # EU (Frankfurt) - eu-central-1 (Commented out for single-region testing)
# #-------------------------------------------------------------------------------
#
# deployment "euc1" {
#   destroy = false
#
#   inputs = {
#     region          = "eu-central-1"
#     cluster_name    = "eks-euc1"
#     cluster_version = "1.30"
#     vpc_cidr        = "10.2.0.0/16"
#     azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
#     tags = {
#       Environment = "workshop"
#       Region      = "eu-central-1"
#       ManagedBy   = "terraform-stacks"
#     }
#
#     # OIDC authentication
#     role_arn       = store.varset.config.aws_role_arn
#     identity_token = identity_token.aws.jwt
#   }
# }
