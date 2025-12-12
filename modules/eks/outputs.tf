################################################################################
# EKS Module Outputs
################################################################################

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "The Kubernetes version of the cluster"
  value       = module.eks.cluster_version
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider" {
  description = "OIDC Provider URL (without https://)"
  value       = module.eks.oidc_provider
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
}

output "cluster_token" {
  description = "Authentication token for the EKS cluster (short-lived)"
  value       = data.aws_eks_cluster_auth.this.token
  sensitive   = true
}

output "node_iam_role_arn" {
  description = "ARN of the EKS managed node group IAM role"
  value       = module.eks.eks_managed_node_groups["default"].iam_role_arn
}
