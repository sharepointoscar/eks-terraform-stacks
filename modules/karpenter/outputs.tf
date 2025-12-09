################################################################################
# Karpenter Module Outputs
################################################################################

output "iam_role_arn" {
  description = "ARN of the Karpenter controller IAM role"
  value       = module.karpenter.iam_role_arn
}

output "iam_role_name" {
  description = "Name of the Karpenter controller IAM role"
  value       = module.karpenter.iam_role_name
}

output "node_iam_role_arn" {
  description = "ARN of the Karpenter node IAM role"
  value       = module.karpenter.node_iam_role_arn
}

output "node_iam_role_name" {
  description = "Name of the Karpenter node IAM role"
  value       = module.karpenter.node_iam_role_name
}

output "queue_name" {
  description = "Name of the SQS queue for Karpenter interruption handling"
  value       = module.karpenter.queue_name
}

output "queue_arn" {
  description = "ARN of the SQS queue for Karpenter interruption handling"
  value       = module.karpenter.queue_arn
}

output "instance_profile_name" {
  description = "Name of the Karpenter node instance profile"
  value       = module.karpenter.instance_profile_name
}
