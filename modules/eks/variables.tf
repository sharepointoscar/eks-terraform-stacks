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

variable "node_instance_types" {
  description = "Instance types for the default node group"
  type        = list(string)
  default     = ["m5.large"]
}

variable "node_min_size" {
  description = "Minimum size of the default node group"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum size of the default node group"
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "Desired size of the default node group"
  type        = number
  default     = 2
}

variable "access_entries" {
  description = "Map of access entries to add to the cluster"
  type        = any
  default     = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
