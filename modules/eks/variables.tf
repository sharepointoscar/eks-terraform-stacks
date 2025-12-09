################################################################################
# EKS Module Variables
################################################################################

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "karpenter_node_instance_types" {
  description = "Instance types for the Karpenter controller node group"
  type        = list(string)
  default     = ["m5.large"]
}

variable "karpenter_node_min_size" {
  description = "Minimum size of the Karpenter controller node group"
  type        = number
  default     = 2
}

variable "karpenter_node_max_size" {
  description = "Maximum size of the Karpenter controller node group"
  type        = number
  default     = 3
}

variable "karpenter_node_desired_size" {
  description = "Desired size of the Karpenter controller node group"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
