# Karpenter Advanced Exercise (Optional)

This advanced exercise adds [Karpenter](https://karpenter.sh/) to your EKS clusters using patterns from [Karpenter Blueprints](https://github.com/aws-samples/karpenter-blueprints).

## Overview

### What is Karpenter?

Karpenter is an open-source Kubernetes node autoscaler that:
- Provisions right-sized compute resources in response to pending pods
- Supports Spot instances for cost optimization
- Consolidates workloads to reduce cluster costs
- Responds to scheduling needs in seconds (vs minutes with Cluster Autoscaler)

### Why Use Karpenter?

| Feature | Karpenter | Cluster Autoscaler |
|---------|-----------|-------------------|
| Provisioning Speed | Seconds | Minutes |
| Instance Selection | Any instance type | Pre-defined node groups |
| Spot Support | Native | Limited |
| Consolidation | Automatic | Manual |
| Bin Packing | Optimized | Basic |

---

## Prerequisites

Before starting, ensure you have:

- [ ] EKS clusters deployed successfully via Terraform Stacks
- [ ] `kubectl` installed and configured
- [ ] AWS CLI configured with appropriate permissions
- [ ] Terraform Stacks deployed without errors

Verify your cluster is accessible:

```bash
# Configure kubectl for your cluster (replace region and cluster name)
aws eks update-kubeconfig --region us-east-1 --name eks-use1

# Verify connection
kubectl get nodes
```

---

## Step 1: Add Karpenter Module

The Karpenter module is already created at `modules/karpenter/`. Review the files:

```
modules/karpenter/
├── main.tf          # Karpenter Helm release + NodePool/EC2NodeClass
├── variables.tf     # Input variables
├── outputs.tf       # Module outputs
└── providers.tf     # Required providers
```

---

## Step 2: Update EKS Module for Karpenter

Modify `modules/eks/main.tf` to add Karpenter-specific labels and tags:

```hcl
  # Managed Node Group for Karpenter Controller
  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size

      # ADD: Label for Karpenter controller scheduling
      labels = {
        "karpenter.sh/controller" = "true"
      }
    }
  }

  # ADD: Tags for Karpenter node discovery
  tags = merge(var.tags, {
    "karpenter.sh/discovery" = var.cluster_name
  })
```

Also tag the subnets and security groups. In `modules/vpc/main.tf`, add:

```hcl
  # In private_subnet_tags:
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = var.name  # ADD THIS
  }
```

---

## Step 3: Add Karpenter Component

Add the following to `components.tfcomponent.hcl`:

### Add kubectl Provider

```hcl
# Add to required_providers block
required_providers {
  # ... existing providers ...
  kubectl = {
    source  = "alekc/kubectl"
    version = "~> 2.0"
  }
}

# Add provider configuration
provider "kubectl" "main" {
  config {
    host                   = component.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(component.eks.cluster_certificate_authority_data)
    token                  = component.eks.cluster_token
  }
}
```

### Add Virginia Provider (for ECR Public)

```hcl
# AWS provider for us-east-1 (required for ECR public authentication)
provider "aws" "virginia" {
  config {
    region = "us-east-1"

    assume_role_with_web_identity {
      role_arn           = var.role_arn
      web_identity_token = var.identity_token
    }
  }
}
```

### Add Karpenter Component

```hcl
#-------------------------------------------------------------------------------
# Karpenter Component (Optional - Advanced Exercise)
#-------------------------------------------------------------------------------

component "karpenter" {
  source = "./modules/karpenter"

  depends_on = [component.eks]

  providers = {
    aws          = provider.aws.main
    aws.virginia = provider.aws.virginia
    helm         = provider.helm.main
    kubernetes   = provider.kubernetes.main
    kubectl      = provider.kubectl.main
  }

  inputs = {
    cluster_name      = component.eks.cluster_name
    cluster_endpoint  = component.eks.cluster_endpoint
    cluster_version   = component.eks.cluster_version
    oidc_provider_arn = component.eks.oidc_provider_arn
    node_iam_role_arn = component.eks.node_iam_role_arn
    tags              = var.tags
  }
}
```

---

## Step 4: Add EKS Module Outputs

Add the following outputs to `modules/eks/outputs.tf`:

```hcl
output "node_iam_role_arn" {
  description = "ARN of the EKS managed node group IAM role"
  value       = module.eks.eks_managed_node_groups["default"].iam_role_arn
}

output "node_security_group_id" {
  description = "ID of the EKS node security group"
  value       = module.eks.node_security_group_id
}
```

---

## Step 5: Deploy

### Option A: Using Helper Script

```bash
# Run the helper script
./scripts/enable-karpenter.sh

# Select option 1 to enable for all deployments
# Or select option 2 to enable for a specific region
```

### Option B: Manual Deployment

1. Commit and push changes:

```bash
git add .
git commit -m "feat: Add Karpenter as optional component"
git push
```

2. HCP Terraform will automatically plan the changes. Review and apply.

---

## Step 6: Verify Karpenter Installation

```bash
# Check Karpenter pods
kubectl get pods -n karpenter

# Check NodePool
kubectl get nodepools

# Check EC2NodeClass
kubectl get ec2nodeclasses

# View Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

### Test Karpenter Scaling

Deploy a test workload:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
spec:
  replicas: 0
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      containers:
        - name: inflate
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
          resources:
            requests:
              cpu: 1
EOF
```

Scale up to trigger Karpenter:

```bash
kubectl scale deployment inflate --replicas=10
```

Watch Karpenter provision nodes:

```bash
kubectl get nodes -w
```

Clean up test:

```bash
kubectl delete deployment inflate
```

---

## Cleanup Before Destroy

**IMPORTANT**: Before setting `destroy = true`, you must remove Karpenter-provisioned nodes:

```bash
# Delete all NodePools (this will terminate Karpenter nodes)
kubectl delete nodepools --all

# Delete all EC2NodeClasses
kubectl delete ec2nodeclasses --all

# Wait for nodes to terminate (check AWS Console or):
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/discovery,Values=eks-use1" \
  --query 'Reservations[].Instances[].State.Name'

# Should return empty or all "terminated"
```

Then proceed with destroy:

```bash
# Edit deployments.tfdeploy.hcl to add:
# destroy = true
git add . && git commit -m "chore: Destroy infrastructure" && git push
```

---

## Troubleshooting

### Karpenter Pods Not Starting

**Symptom**: Karpenter pods stuck in Pending

**Cause**: Controller nodes don't have the required label

**Solution**: Verify node labels:
```bash
kubectl get nodes -l karpenter.sh/controller=true
```

If no nodes have this label, update the EKS module to add labels to the managed node group.

### NodePool Not Provisioning Nodes

**Symptom**: Pods pending but no new nodes created

**Cause**: Usually subnet or security group discovery issues

**Solution**:
```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter

# Verify tags on subnets
aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=eks-use1" \
  --query 'Subnets[].SubnetId'

# Verify tags on security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:karpenter.sh/discovery,Values=eks-use1" \
  --query 'SecurityGroups[].GroupId'
```

### Nodes Stuck in NotReady

**Symptom**: Karpenter nodes appear but stay NotReady

**Cause**: Usually IAM role issues

**Solution**:
```bash
# Check node IAM role
kubectl describe node <node-name> | grep ProviderID

# Verify instance profile has correct policies
aws iam list-attached-role-policies --role-name eks-use1-karpenter-node
```

### Spot Instance Issues

**Symptom**: Only on-demand instances provisioned

**Cause**: Spot capacity unavailable or blocked

**Solution**: Check NodePool allows spot:
```bash
kubectl get nodepool default -o yaml | grep -A5 capacity-type
```

---

## Reference Links

- [Karpenter Documentation](https://karpenter.sh/docs/)
- [Karpenter Blueprints](https://github.com/aws-samples/karpenter-blueprints)
- [EKS Best Practices - Karpenter](https://aws.github.io/aws-eks-best-practices/karpenter/)
- [terraform-aws-modules/eks Karpenter submodule](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master/modules/karpenter)
