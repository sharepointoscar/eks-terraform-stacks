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
  # Labels and taints support Karpenter controller placement
  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size

      # Label for Karpenter controller placement
      labels = {
        "karpenter.sh/controller" = "true"
      }

      # Taint to reserve nodes for critical addons
      taints = {
        CriticalAddonsOnly = {
          key    = "CriticalAddonsOnly"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # Add Karpenter discovery tag to node security group
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
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

################################################################################
# EKS Access Entry for Admin User
# Created as separate resource to support ephemeral values from Terraform Stacks
################################################################################

resource "aws_eks_access_entry" "admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = var.admin_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = var.admin_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
