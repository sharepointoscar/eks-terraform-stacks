################################################################################
# EKS Module
# Uses terraform-aws-modules/eks/aws as recommended by EKS Blueprints
# Reference: https://aws-ia.github.io/terraform-aws-eks-blueprints/
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Network configuration
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Cluster access configuration
  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  # Additional cluster access entries
  access_entries = var.access_entries

  # EKS Managed Add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  # Managed Node Group for cluster workloads
  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
    }
  }

  tags = var.tags
}

################################################################################
# Cluster Authentication Token
# Required for kubernetes/helm providers in Terraform Stacks (remote execution)
################################################################################

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}
