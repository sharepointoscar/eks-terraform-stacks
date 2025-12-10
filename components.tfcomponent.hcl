################################################################################
# Multi-Region EKS Stack with Terraform Stacks
# Deploys VPC, EKS, and Addons (Karpenter + AWS Load Balancer Controller)
# Reference: https://github.com/aws-ia/terraform-aws-eks-blueprints
################################################################################

#-------------------------------------------------------------------------------
# Required Providers
#-------------------------------------------------------------------------------

required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"
  }
  helm = {
    source  = "hashicorp/helm"
    version = "~> 2.11"
  }
  kubernetes = {
    source  = "hashicorp/kubernetes"
    version = "~> 2.25"
  }
  tls = {
    source  = "hashicorp/tls"
    version = "~> 4.0"
  }
  null = {
    source  = "hashicorp/null"
    version = "~> 3.0"
  }
  cloudinit = {
    source  = "hashicorp/cloudinit"
    version = "~> 2.0"
  }
  time = {
    source  = "hashicorp/time"
    version = "~> 0.9"
  }
  random = {
    source  = "hashicorp/random"
    version = "~> 3.0"
  }
}

#-------------------------------------------------------------------------------
# Provider Configurations
#-------------------------------------------------------------------------------

# Primary AWS provider for the deployment region
# Uses OIDC authentication for HCP Terraform
provider "aws" "main" {
  config {
    region = var.region

    assume_role_with_web_identity {
      role_arn           = var.role_arn
      web_identity_token = var.identity_token
    }
  }
}

# Kubernetes provider configuration
# Uses token-based auth (required for Terraform Stacks remote execution)
provider "kubernetes" "main" {
  config {
    host                   = component.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(component.eks.cluster_certificate_authority_data)
    token                  = component.eks.cluster_token
  }
}

# Helm provider configuration
# Must explicitly configure Kubernetes connection (Stacks doesn't inherit from kubernetes provider)
provider "helm" "main" {
  config {
    kubernetes {
      host                   = component.eks.cluster_endpoint
      cluster_ca_certificate = base64decode(component.eks.cluster_certificate_authority_data)
      token                  = component.eks.cluster_token
    }
  }
}

# TLS provider (required by EKS module)
provider "tls" "main" {
  config {}
}

# Null provider (required by EKS module)
provider "null" "main" {
  config {}
}

# Cloudinit provider (required by EKS module)
provider "cloudinit" "main" {
  config {}
}

# Time provider (required by EKS and addons modules)
provider "time" "main" {
  config {}
}

# Random provider (required by addons module)
provider "random" "main" {
  config {}
}

#-------------------------------------------------------------------------------
# VPC Component
#-------------------------------------------------------------------------------

component "vpc" {
  source = "./modules/vpc"

  providers = {
    aws = provider.aws.main
  }

  inputs = {
    name     = var.cluster_name
    vpc_cidr = var.vpc_cidr
    azs      = var.azs
    tags     = var.tags
  }
}

#-------------------------------------------------------------------------------
# EKS Component
#-------------------------------------------------------------------------------

component "eks" {
  source = "./modules/eks"

  depends_on = [component.vpc]

  providers = {
    aws       = provider.aws.main
    tls       = provider.tls.main
    null      = provider.null.main
    cloudinit = provider.cloudinit.main
    time      = provider.time.main
  }

  inputs = {
    cluster_name    = var.cluster_name
    cluster_version = var.cluster_version
    vpc_id          = component.vpc.vpc_id
    subnet_ids      = component.vpc.private_subnets
    admin_principal_arn = var.admin_principal_arn
    tags            = var.tags
  }
}

#-------------------------------------------------------------------------------
# EKS Blueprints Addons Component
#-------------------------------------------------------------------------------

component "addons" {
  source = "./modules/eks-blueprints-addons"

  depends_on = [component.eks]

  providers = {
    aws        = provider.aws.main
    helm       = provider.helm.main
    kubernetes = provider.kubernetes.main
    time       = provider.time.main
    random     = provider.random.main
  }

  inputs = {
    cluster_name      = component.eks.cluster_name
    cluster_endpoint  = component.eks.cluster_endpoint
    cluster_version   = component.eks.cluster_version
    oidc_provider_arn = component.eks.oidc_provider_arn
    tags              = var.tags
  }
}

#-------------------------------------------------------------------------------
# Outputs
#-------------------------------------------------------------------------------

output "vpc_id" {
  type        = string
  description = "The ID of the VPC"
  value       = component.vpc.vpc_id
}

output "cluster_name" {
  type        = string
  description = "The name of the EKS cluster"
  value       = component.eks.cluster_name
}

output "cluster_endpoint" {
  type        = string
  description = "Endpoint for the EKS cluster API server"
  value       = component.eks.cluster_endpoint
}

output "configure_kubectl" {
  type        = string
  description = "Command to configure kubectl"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${var.cluster_name}"
}
