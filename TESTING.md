# Workshop Testing Guide

This document describes how to test the workshop sub-modules (ArgoCD and Karpenter) using a branch-based testing strategy.

## Branch Strategy

| Branch | Purpose | State |
|--------|---------|-------|
| `main` | Clean workshop baseline | Core components only (vpc, eks, addons) |
| `argocd-test` | Test ArgoCD sub-module | Changes stay in branch, don't merge to main |
| `karpenter-test` | Test Karpenter sub-module | Changes stay in branch, don't merge to main |

## Main Branch Baseline

The `main` branch contains a clean baseline with:

### Components (`components.tfcomponent.hcl`)
- `component "vpc"` - VPC with public/private subnets
- `component "eks"` - EKS cluster with managed node group
- `component "addons"` - AWS Load Balancer Controller (ArgoCD disabled by default)
- **Karpenter is NOT declared** - the deploy script adds it when testing

### Deployments (`deployments.tfdeploy.hcl`)
- `deployment "usw2"` - `destroy = false` (active test cluster in us-west-2)
- `deployment "use1"` - `destroy = true` (declared but not deployed)
- `deployment "euc1"` - `destroy = true` (declared but not deployed)

### Key Principles
1. **Nothing commented out** - use `destroy = true` to disable deployments
2. **Karpenter component NOT in main** - `deploy-karpenter.sh` adds it when testing
3. **ArgoCD controlled via variable** - `enable_argocd = false` by default in addons module

---

## Testing ArgoCD

### Create Test Branch

```bash
git checkout main
git pull origin main
git checkout -b argocd-test
```

### Deploy ArgoCD

```bash
./scripts/deploy-argocd.sh
```

This script:
1. Sets `enable_argocd = true` in `modules/eks-blueprints-addons/variables.tf`
2. Commits and pushes the change
3. Triggers HCP Terraform deployment

**Wait for HCP Terraform to apply** (~5 minutes)

### Test ArgoCD

```bash
./scripts/test-argocd.sh
```

This script:
1. Verifies ArgoCD pods are running
2. Retrieves the admin password
3. Sets up port-forwarding to access the UI
4. Deploys a sample application

### Cleanup ArgoCD

```bash
./scripts/deploy-argocd.sh --disable --cleanup-crds
```

This script:
1. Sets `enable_argocd = false`
2. Commits and pushes the change
3. Deletes ArgoCD CRDs and namespace (with `--cleanup-crds` flag)

**Wait for HCP Terraform to destroy**

### Delete Test Branch

```bash
git checkout main
git branch -D argocd-test
```

---

## Testing Karpenter

### Create Test Branch

```bash
git checkout main
git pull origin main
git checkout -b karpenter-test
```

### Deploy Karpenter

```bash
./scripts/deploy-karpenter.sh
```

This script runs in two phases:

**Phase 1: EKS Prerequisites**
- Adds Karpenter labels/taints to EKS managed node group
- Adds security group discovery tags
- Commits and pushes changes

**Wait for HCP Terraform to apply Phase 1**

**Phase 2: Karpenter Component**
- Adds `component "karpenter"` to `components.tfcomponent.hcl`
- Commits and pushes changes

**Wait for HCP Terraform to apply Phase 2** (~10 minutes)

### Test Karpenter

```bash
./scripts/test-karpenter.sh
```

This script:
1. Verifies Karpenter pods are running
2. Checks NodePool and EC2NodeClass CRDs
3. Deploys a test workload (skiapp with 10 replicas)
4. Verifies Karpenter provisions new nodes
5. Tests scale-down and consolidation
6. Cleans up test resources

### Cleanup Karpenter

```bash
./scripts/deploy-karpenter.sh --disable
```

This script:
1. Replaces `component "karpenter"` with a `removed` block
2. Commits and pushes changes
3. Verifies Karpenter resources are removed from the cluster

**Wait for HCP Terraform to destroy**

### Delete Test Branch

```bash
git checkout main
git branch -D karpenter-test
```

---

## Script Options

### deploy-argocd.sh

```bash
./scripts/deploy-argocd.sh [OPTIONS]

Options:
  --dry-run         Show changes without applying them
  --skip-push       Make changes but don't commit/push
  --disable         Disable ArgoCD instead of enabling
  --cleanup-crds    Delete ArgoCD CRDs (use with --disable)
  --help            Show help message
```

### deploy-karpenter.sh

```bash
./scripts/deploy-karpenter.sh [OPTIONS]

Options:
  --dry-run         Show changes without applying them
  --skip-push       Make changes but don't commit/push
  --disable         Remove Karpenter instead of deploying
  --no-pause        Skip interactive pauses (fully automated)
  --help            Show help message
```

### test-argocd.sh

```bash
./scripts/test-argocd.sh [OPTIONS]

Options:
  --skip-cleanup    Preserve test resources after testing
  --no-pause        Skip interactive pauses
  --help            Show help message
```

### test-karpenter.sh

```bash
./scripts/test-karpenter.sh [OPTIONS]

Options:
  --skip-cleanup    Preserve test resources after testing
  --no-pause        Skip interactive pauses
  --help            Show help message
```

---

## Troubleshooting

### HCP Terraform Not Detecting Changes

If HCP Terraform doesn't detect your changes:
1. Ensure you pushed to the correct branch
2. Check that the HCP Terraform Stack is connected to the repository
3. Verify the branch is being tracked

### Karpenter Pods Crashing

If Karpenter pods are crashing:
1. Check the pod logs: `kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter`
2. Verify IRSA is configured correctly
3. Ensure the EKS OIDC provider is set up

### ArgoCD CRDs Not Deleted

If ArgoCD CRDs remain after disable:
```bash
kubectl delete crd applications.argoproj.io
kubectl delete crd applicationsets.argoproj.io
kubectl delete crd appprojects.argoproj.io
kubectl delete namespace argocd
```

### Orphaned AWS Resources

If you encounter orphaned resources (e.g., security groups from previous deployments):
```bash
./scripts/cleanup-orphaned-resources.sh
```

---

## Files Reference

| File | Purpose |
|------|---------|
| `components.tfcomponent.hcl` | Component declarations (vpc, eks, addons) |
| `deployments.tfdeploy.hcl` | Deployment configs with `destroy` flag per region |
| `modules/eks-blueprints-addons/variables.tf` | Contains `enable_argocd` variable |
| `modules/karpenter/` | Dedicated Karpenter module |
| `scripts/deploy-argocd.sh` | Enable/disable ArgoCD addon |
| `scripts/test-argocd.sh` | Test ArgoCD functionality |
| `scripts/deploy-karpenter.sh` | Enable/disable Karpenter component |
| `scripts/test-karpenter.sh` | Test Karpenter node autoscaling |
