################################################################################
# Multi-Region EKS Deployments
# Deploys the complete stack (VPC + EKS + Addons) to three AWS regions
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
# Create a variable set in HCP Terraform named "eks-stacks-config" with:
#   - aws_role_arn: ARN of the IAM role for OIDC authentication
#   - admin_principal_arn: ARN of IAM user/role for kubectl access
# Then assign the variable set to this Stack's project
################################################################################

store "varset" "config" {
  name     = "eks-stacks-config"
  category = "terraform"
}

locals {
  # EKS access entries for kubectl access
  access_entries = {
    admin = {
      principal_arn = store.varset.config.admin_principal_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

#-------------------------------------------------------------------------------
# US East (N. Virginia) - us-east-1
#-------------------------------------------------------------------------------

deployment "use1" {
  destroy = true

  inputs = {
    region          = "us-east-1"
    cluster_name    = "eks-use1"
    cluster_version = "1.30"
    vpc_cidr        = "10.0.0.0/16"
    azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
    tags = {
      Environment = "workshop"
      Region      = "us-east-1"
      ManagedBy   = "terraform-stacks"
    }

    # OIDC authentication
    role_arn       = store.varset.config.aws_role_arn
    identity_token = identity_token.aws.jwt

    # EKS cluster access for kubectl
    access_entries = local.access_entries
  }
}

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

    # EKS cluster access for kubectl
    access_entries = local.access_entries
  }
}

#-------------------------------------------------------------------------------
# EU (Frankfurt) - eu-central-1
#-------------------------------------------------------------------------------

deployment "euc1" {
  destroy = true

  inputs = {
    region          = "eu-central-1"
    cluster_name    = "eks-euc1"
    cluster_version = "1.30"
    vpc_cidr        = "10.2.0.0/16"
    azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    tags = {
      Environment = "workshop"
      Region      = "eu-central-1"
      ManagedBy   = "terraform-stacks"
    }

    # OIDC authentication
    role_arn       = store.varset.config.aws_role_arn
    identity_token = identity_token.aws.jwt

    # EKS cluster access for kubectl
    access_entries = local.access_entries
  }
}
