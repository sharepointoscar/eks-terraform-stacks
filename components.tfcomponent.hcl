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
# Inherits kubernetes configuration when both providers are passed to a component
provider "helm" "main" {
  config {}
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
# Input Variables
#-------------------------------------------------------------------------------

variable "region" {
  type        = string
  description = "AWS region for deployment"
}

variable "role_arn" {
  type        = string
  description = "ARN of the IAM role for HCP Terraform to assume via OIDC"
}

variable "identity_token" {
  type        = string
  ephemeral   = true
  description = "OIDC identity token from HCP Terraform"
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster (also used for VPC naming)"
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster"
  default     = "1.30"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "List of availability zones"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
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
