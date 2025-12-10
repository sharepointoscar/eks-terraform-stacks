################################################################################
# Outputs
################################################################################

output "variable_set_id" {
  description = "ID of the created variable set"
  value       = tfe_variable_set.eks_stacks_config.id
}

output "variable_set_name" {
  description = "Name of the created variable set"
  value       = tfe_variable_set.eks_stacks_config.name
}

output "project_id" {
  description = "ID of the project the variable set is assigned to"
  value       = data.tfe_project.stack_project.id
}

output "next_steps" {
  description = "Instructions for next steps"
  value       = <<-EOT

    ============================================================================
    Variable Set Created Successfully!
    ============================================================================

    Variable Set: ${tfe_variable_set.eks_stacks_config.name}
    Variable Set ID: ${tfe_variable_set.eks_stacks_config.id}
    Assigned to Project: ${var.tfc_project_name}

    Variables configured:
      - aws_role_arn: ${var.aws_role_arn}
      - admin_principal_arn: ${var.admin_principal_arn}

    Next Steps:
    1. Go to HCP Terraform: https://app.terraform.io/
    2. Navigate to: ${var.tfc_organization} > ${var.tfc_project_name}
    3. Create a new Stack connected to this repository
    4. The Stack will automatically use the variable set

    ============================================================================
  EOT
}
