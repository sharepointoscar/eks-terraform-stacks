# Multi-Region EKS with Terraform Stacks

This repository demonstrates deploying Amazon EKS clusters across three AWS regions using **Terraform Stacks**, following the [AWS EKS Blueprints](https://github.com/aws-ia/terraform-aws-eks-blueprints) patterns.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Single Terraform Stack                                   │
│                     (eks-multi-region)                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Components (defined in components.tfcomponent.hcl):                        │
│                                                                             │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐         │
│  │   component     │    │   component     │    │   component     │         │
│  │     "vpc"       │───▶│     "eks"       │───▶│    "addons"     │         │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘         │
│         │                      │                      │                     │
│         ▼                      ▼                      ▼                     │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐         │
│  │  modules/vpc    │    │  modules/eks    │    │ modules/eks-    │         │
│  │                 │    │                 │    │ blueprints-     │         │
│  │ terraform-aws-  │    │ terraform-aws-  │    │ addons          │         │
│  │ modules/vpc/aws │    │ modules/eks/aws │    │                 │         │
│  └─────────────────┘    └─────────────────┘    │ aws-ia/eks-     │         │
│                                                │ blueprints-     │         │
│                                                │ addons/aws      │         │
│                                                └─────────────────┘         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

Deployments (defined in deployments.tfdeploy.hcl):
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  us-east-1   │  │  us-west-2   │  │ eu-central-1 │
│  eks-use1    │  │  eks-usw2    │  │  eks-euc1    │
│ 10.0.0.0/16  │  │ 10.1.0.0/16  │  │ 10.2.0.0/16  │
└──────────────┘  └──────────────┘  └──────────────┘
```

## Components

This stack contains three components that are deployed together:

| Component | Module | Purpose |
|-----------|--------|---------|
| `vpc` | `terraform-aws-modules/vpc/aws` | VPC with public/private subnets, Karpenter discovery tags |
| `eks` | `terraform-aws-modules/eks/aws` | EKS cluster + managed node group for Karpenter controller |
| `addons` | `aws-ia/eks-blueprints-addons/aws` | Karpenter + AWS Load Balancer Controller |

### Addons Deployed

- **[Karpenter](https://karpenter.sh/)** - Kubernetes node autoscaler for dynamic EC2 provisioning
- **[AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)** - Manages ALB/NLB for Kubernetes services

## Prerequisites

- [Terraform CLI](https://www.terraform.io/downloads.html) >= 1.14
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [HCP Terraform](https://app.terraform.io/) account with Stacks enabled

> **Note:** Terraform Stacks can only be deployed remotely via HCP Terraform. Local deployment is not supported. See [Terraform Stacks Documentation](https://developer.hashicorp.com/terraform/cloud-docs/stacks/create).

## Quick Start

```bash
# Clone the repository
git clone <repository-url>
cd eks-terraform-stacks
```

## AWS Authentication Setup

Terraform Stacks runs remotely in HCP Terraform and requires OIDC-based authentication to access your AWS account. Run the provided setup script to create the necessary IAM role and trust policy.

### Option 1: Use the Setup Script (Recommended)

```bash
# Run the setup script with your HCP Terraform details
./scripts/setup-aws-oidc.sh <HCP_ORG> <HCP_PROJECT> <STACK_NAME>

# Example:
./scripts/setup-aws-oidc.sh my-org my-project eks-multi-region
```

The script will:
1. Create an OIDC Identity Provider for HCP Terraform (if not exists)
2. Create an IAM role with the appropriate trust policy
3. Attach AdministratorAccess policy
4. Output the Role ARN to use in HCP Terraform

### Option 2: Manual Setup

If you prefer to create the IAM role manually:

1. **Create OIDC Identity Provider** in AWS IAM for `app.terraform.io`
2. **Create IAM Role** with this trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/app.terraform.io"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "app.terraform.io:aud": "aws.workload.identity"
        },
        "StringLike": {
          "app.terraform.io:sub": "organization:<HCP_ORG>:project:<PROJECT>:stack:<STACK>:*"
        }
      }
    }
  ]
}
```

3. **Attach permissions** (AdministratorAccess for workshop, or least-privilege for production)

### Configure the Role ARN in HCP Terraform

After creating the IAM role, set the `aws_role_arn` variable in HCP Terraform to the Role ARN output by the script.

## Deployment

This project uses **Terraform Stacks**, which deploys remotely via HCP Terraform.

### Option 1: HCP Terraform UI

1. **Create a Stack** in [HCP Terraform](https://app.terraform.io/)
2. **Connect this repository** as the source
3. **Configure deployments** for each region (use1, usw2, euc1)
4. **Plan and Apply** through the HCP Terraform UI

### Option 2: Terraform CLI Workflow

Use the Terraform CLI to manage Stacks remotely in HCP Terraform:

```bash
# 1. Authenticate with HCP Terraform
terraform login

# 2. Initialize the stack (downloads module dependencies)
terraform stacks init

# 3. Create the stack
terraform stacks create \
  -organization-name <YOUR_ORG> \
  -project-name <YOUR_PROJECT> \
  -stack-name eks-multi-region

# 4. Upload the configuration
terraform stacks configuration upload \
  -organization-name <YOUR_ORG> \
  -project-name <YOUR_PROJECT> \
  -stack-name eks-multi-region

# 5. Monitor deployment status
terraform stacks configuration watch \
  -organization-name <YOUR_ORG> \
  -project-name <YOUR_PROJECT>
```

For detailed instructions, see [Create Stacks with CLI](https://developer.hashicorp.com/terraform/cloud-docs/stacks/create#terraform-cli-workflow).

### Configure kubectl

After deployment, configure kubectl to access your cluster:

```bash
# For us-east-1
aws eks --region us-east-1 update-kubeconfig --name eks-use1

# For us-west-2
aws eks --region us-west-2 update-kubeconfig --name eks-usw2

# For eu-central-1
aws eks --region eu-central-1 update-kubeconfig --name eks-euc1
```

### Verify Deployment

```bash
# Check nodes
kubectl get nodes

# Check Karpenter
kubectl get pods -n karpenter

# Check AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

## Teardown

**IMPORTANT:** Karpenter-provisioned EC2 instances exist outside Terraform's management and must be removed first.

```bash
# 1. Remove Karpenter-provisioned nodes (for each cluster)
kubectl delete nodepools --all
kubectl delete ec2nodeclasses --all

# Wait for nodes to terminate
kubectl get nodes -w
```

### Destroy Stack

Destroy the stack through HCP Terraform UI or CLI. The stack will destroy all components (addons, eks, vpc) in the correct dependency order.

## Project Structure

```
.
├── .terraform-version           # Required Terraform version for Stacks
├── components.tfcomponent.hcl   # Stack component definitions (vpc, eks, addons)
├── deployments.tfdeploy.hcl     # Multi-region deployment configurations
├── README.md
├── scripts/
│   └── setup-aws-oidc.sh        # Script to create AWS IAM role for OIDC auth
└── modules/
    ├── vpc/                     # VPC module (terraform-aws-modules/vpc/aws)
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── eks/                     # EKS module (terraform-aws-modules/eks/aws)
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── eks-blueprints-addons/   # Addons module (aws-ia/eks-blueprints-addons/aws)
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── providers.tf
```

## References

- [AWS EKS Blueprints for Terraform](https://github.com/aws-ia/terraform-aws-eks-blueprints)
- [EKS Blueprints Addons](https://github.com/aws-ia/terraform-aws-eks-blueprints-addons)
- [EKS Blueprints Getting Started](https://aws-ia.github.io/terraform-aws-eks-blueprints/getting-started/)
- [Karpenter Pattern](https://aws-ia.github.io/terraform-aws-eks-blueprints/patterns/karpenter/)
- [Terraform Stacks Documentation](https://developer.hashicorp.com/terraform/language/stacks)
- [Create Stacks with CLI](https://developer.hashicorp.com/terraform/cloud-docs/stacks/create#terraform-cli-workflow)
- [terraform-aws-modules/eks](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [terraform-aws-modules/vpc](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest)
