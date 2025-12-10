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
| `vpc` | `terraform-aws-modules/vpc/aws` | VPC with public/private subnets |
| `eks` | `terraform-aws-modules/eks/aws` | EKS cluster + managed node group |
| `addons` | `aws-ia/eks-blueprints-addons/aws` | AWS Load Balancer Controller |
| `karpenter` | `terraform-aws-modules/eks//modules/karpenter` | **Optional** - Kubernetes node autoscaler |

### Addons Deployed

- **[AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)** - Manages ALB/NLB for Kubernetes services

### Optional: Karpenter (Advanced Exercise)

- **[Karpenter](https://karpenter.sh/)** - Kubernetes node autoscaler for dynamic EC2 provisioning
- See [Karpenter Advanced Exercise](docs/karpenter-advanced-exercise.md) for step-by-step instructions

## Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [HCP Terraform](https://app.terraform.io/) account with Stacks enabled

> **Note:** Terraform Stacks can only be deployed remotely via HCP Terraform. Local deployment is not supported. See [Terraform Stacks Documentation](https://developer.hashicorp.com/terraform/cloud-docs/stacks/create).

---

## Getting Started

Follow these steps in order to deploy the multi-region EKS clusters.

### Step 1: Clone the Repository

```bash
git clone https://github.com/sharepointoscar/eks-terraform-stacks.git
cd eks-terraform-stacks
```

### Step 2: Create AWS IAM Role for OIDC Authentication

Terraform Stacks runs remotely in HCP Terraform and requires OIDC-based authentication to access your AWS account.

```bash
# Run the setup script with your HCP Terraform organization name
./scripts/setup-aws-oidc.sh <YOUR_HCP_ORG_NAME>

# Example:
./scripts/setup-aws-oidc.sh my-terraform-org
```

**Save the Role ARN** from the output - you'll need it in the next step.

<details>
<summary>Manual Setup (Alternative)</summary>

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
          "app.terraform.io:sub": "organization:<HCP_ORG>:*"
        }
      }
    }
  ]
}
```

3. **Attach permissions** (AdministratorAccess for workshop, or least-privilege for production)
</details>

### Step 3: Get Your IAM ARN for kubectl Access

Run this command to get your IAM user/role ARN:

```bash
aws sts get-caller-identity --query 'Arn' --output text
```

**Save this ARN** - you'll need it in the next step.

### Step 4: Create Variable Set in HCP Terraform

The Stack uses a variable set to store configuration. You can create it automatically using Terraform or manually via the UI.

> **Prerequisite:** Create a Project in HCP Terraform first. Go to [HCP Terraform](https://app.terraform.io/) > **Projects** > **New Project**. Note the project name for the next step.

The variable set configures two critical values:
- **`aws_role_arn`** - Allows HCP Terraform to provision AWS resources via OIDC
- **`admin_principal_arn`** - Grants your IAM user/role `kubectl` access to the EKS clusters after deployment

#### Option A: Automated Setup (Recommended)

Use the provided Terraform configuration to create the variable set:

```bash
# Navigate to the HCP setup directory
cd scripts/hcp-setup

# Copy the example tfvars file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values:
# - tfc_organization: Your HCP Terraform organization name
# - tfc_project_name: The project where your Stack will be created (must exist)
# - aws_role_arn: From Step 2 output
# - admin_principal_arn: From Step 3

# Set your HCP Terraform API token
export TFE_TOKEN="your-api-token"
# Get a token from: https://app.terraform.io/app/settings/tokens

# Initialize and apply
terraform init
terraform apply

# Return to project root
cd ../..
```

#### Option B: Manual Setup (UI)

<details>
<summary>Click to expand manual instructions</summary>

1. Go to [HCP Terraform](https://app.terraform.io/)
2. Navigate to **Settings** (left sidebar) > **Variable sets**
3. Click **Create variable set**
4. Configure the variable set:
   - **Name:** `eks-stacks-config`
   - **Scope:** Select **Project** and choose your project
5. Add variables (click **Add variable** for each):

   | Key | Value | Category | Sensitive |
   |-----|-------|----------|-----------|
   | `aws_role_arn` | `arn:aws:iam::123456789012:role/hcp-terraform-stacks-role` | Terraform | No |
   | `admin_principal_arn` | `arn:aws:iam::123456789012:user/your-username` | Terraform | No |

   > Replace with your actual ARNs from Steps 2 and 3

6. Click **Create variable set**

</details>

### Step 5: Create and Deploy the Stack

1. Go to [HCP Terraform](https://app.terraform.io/)
2. Select your **Organization** and **Project**
3. Click **New** > **Stack**
4. Connect to **GitHub** and select this repository
5. Name the stack (e.g., `eks-multi-region`)
6. Click **Create Stack**

HCP Terraform will automatically:
- Detect the three deployments (use1, usw2, euc1)
- Create a plan for each deployment
- Wait for your approval before applying

7. Review the plan and click **Approve & Apply**

> **Deployment takes approximately 15-20 minutes** per region for the EKS clusters to be created.

### Step 6: Configure kubectl

After deployment completes, configure kubectl to access your clusters:

```bash
# US East (N. Virginia)
aws eks --region us-east-1 update-kubeconfig --name eks-use1

# US West (Oregon)
aws eks --region us-west-2 update-kubeconfig --name eks-usw2

# EU (Frankfurt)
aws eks --region eu-central-1 update-kubeconfig --name eks-euc1
```

### Step 7: Verify Deployment

```bash
# Check nodes
kubectl get nodes

# Check AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

---

## Teardown

### Destroy Stack

To destroy the infrastructure, set `destroy = true` in `deployments.tfdeploy.hcl` for each deployment:

```hcl
deployment "use1" {
  destroy = true
  # ...
}
```

Commit and push the changes. HCP Terraform will destroy all components (addons, eks, vpc) in the correct dependency order.

> **Note:** If you enabled Karpenter (advanced exercise), you must first remove Karpenter-provisioned nodes before destroying. See [Karpenter Cleanup](docs/karpenter-advanced-exercise.md#cleanup-before-destroy).

### Cleanup Orphaned Resources

If a destroy operation fails or is interrupted, some AWS resources may become orphaned (exist in AWS but not tracked in Terraform state). This can cause errors like `ResourceAlreadyExistsException` when re-deploying.

Run the cleanup script to remove orphaned resources:

```bash
# On macOS (requires Bash 4+)
# If you don't have Bash 4+, install it: brew install bash
/opt/homebrew/bin/bash scripts/cleanup-orphaned-resources.sh

# On Linux
bash scripts/cleanup-orphaned-resources.sh
```

The script cleans up the following resources across all three regions:
- EKS Node Groups
- EKS Clusters
- CloudWatch Log Groups (`/aws/eks/<cluster>/cluster`)
- KMS Aliases (`alias/eks/<cluster>`)

After cleanup completes, set `destroy = false` and re-deploy.

---

## Project Structure

```
.
├── components.tfcomponent.hcl   # Stack component definitions (vpc, eks, addons)
├── deployments.tfdeploy.hcl     # Multi-region deployment configurations
├── README.md
├── docs/
│   └── karpenter-advanced-exercise.md  # Optional Karpenter integration guide
├── scripts/
│   ├── setup-aws-oidc.sh        # Create AWS IAM role for OIDC auth
│   ├── hcp-setup/               # Terraform config for HCP variable set
│   ├── enable-karpenter.sh      # Helper for Karpenter integration
│   └── cleanup-orphaned-resources.sh  # Cleanup orphaned AWS resources
└── modules/
    ├── vpc/                     # VPC module
    ├── eks/                     # EKS module
    ├── eks-blueprints-addons/   # Addons module
    └── karpenter/               # Optional: Karpenter module
```

## References

- [Terraform Stacks Documentation](https://developer.hashicorp.com/terraform/language/stacks)
- [AWS EKS Blueprints for Terraform](https://github.com/aws-ia/terraform-aws-eks-blueprints)
- [EKS Blueprints Addons](https://github.com/aws-ia/terraform-aws-eks-blueprints-addons)
- [Karpenter Blueprints](https://github.com/aws-samples/karpenter-blueprints)
- [Karpenter Documentation](https://karpenter.sh/docs/)
- [terraform-aws-modules/eks](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [terraform-aws-modules/vpc](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest)
