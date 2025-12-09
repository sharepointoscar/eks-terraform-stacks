################################################################################
# Karpenter Module Variables
# Based on: https://github.com/aws-samples/karpenter-blueprints
################################################################################

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for IRSA"
  type        = string
}

variable "node_iam_role_arn" {
  description = "ARN of the IAM role for EKS managed node group (Karpenter controller nodes)"
  type        = string
}

variable "karpenter_version" {
  description = "Version of Karpenter to install"
  type        = string
  default     = "1.5.0"
}

variable "karpenter_namespace" {
  description = "Kubernetes namespace to install Karpenter"
  type        = string
  default     = "karpenter"
}

variable "enable_spot_termination" {
  description = "Enable Spot instance termination handler via SQS"
  type        = bool
  default     = true
}

variable "node_instance_types" {
  description = "List of instance types for Karpenter NodePool"
  type        = list(string)
  default     = ["m5.large", "m5.xlarge", "m5.2xlarge", "c5.large", "c5.xlarge", "c5.2xlarge"]
}

variable "node_capacity_types" {
  description = "Capacity types for Karpenter NodePool (spot, on-demand)"
  type        = list(string)
  default     = ["spot", "on-demand"]
}

variable "node_architecture" {
  description = "CPU architectures for Karpenter NodePool"
  type        = list(string)
  default     = ["amd64"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
