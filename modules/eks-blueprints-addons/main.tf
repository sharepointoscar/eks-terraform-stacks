################################################################################
# EKS Blueprints Addons Module
# Uses aws-ia/eks-blueprints-addons/aws for addon management
# Reference: https://github.com/aws-ia/terraform-aws-eks-blueprints-addons
################################################################################

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16"

  cluster_name      = var.cluster_name
  cluster_endpoint  = var.cluster_endpoint
  cluster_version   = var.cluster_version
  oidc_provider_arn = var.oidc_provider_arn

  #---------------------------------------------------------------------------
  # AWS Load Balancer Controller
  # https://kubernetes-sigs.github.io/aws-load-balancer-controller/
  #---------------------------------------------------------------------------
  enable_aws_load_balancer_controller = var.enable_aws_load_balancer_controller

  #---------------------------------------------------------------------------
  # ArgoCD - GitOps Continuous Delivery
  # https://argo-cd.readthedocs.io/
  #---------------------------------------------------------------------------
  enable_argocd = var.enable_argocd

  #---------------------------------------------------------------------------
  # Karpenter - Node Autoscaling
  # https://karpenter.sh/
  #---------------------------------------------------------------------------
  enable_karpenter = var.enable_karpenter

  tags = var.tags
}
