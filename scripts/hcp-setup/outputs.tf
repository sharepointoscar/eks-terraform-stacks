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

    Variables configured in varset:
      - aws_role_arn: ${var.aws_role_arn}

    ============================================================================
    Next Steps
    ============================================================================

    1. Update variables.tfcomponent.hcl with your IAM ARN for kubectl access:
       - Get your ARN: aws sts get-caller-identity --query 'Arn' --output text
       - Edit variables.tfcomponent.hcl and update admin_principal_arn default

    2. Commit and push your changes to GitHub

    3. Go to HCP Terraform: https://app.terraform.io/
    4. Navigate to: ${var.tfc_organization} > ${var.tfc_project_name}
    5. Create a new Stack:
       - Click "New" > "Stack"
       - Connect to GitHub and select this repository
       - Name the stack (e.g., "eks-multi-region")

    6. Review and approve the plan to deploy the EKS clusters

    ============================================================================
  EOT
}
