################################################################################
# EKS Blueprints Addons Module Outputs
################################################################################

output "aws_load_balancer_controller" {
  description = "Map of AWS Load Balancer Controller attributes"
  value       = try(module.eks_blueprints_addons.aws_load_balancer_controller, {})
}
