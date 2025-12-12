#!/bin/bash
################################################################################
# Karpenter Deployment Script
# Deploys Karpenter using the dedicated modules/karpenter module
#
# This script handles a two-phase deployment:
#   Phase 1: EKS prerequisites (labels, taints, security group tags, providers)
#   Phase 2: Karpenter component deployment
#
# Prerequisites:
#   - Git configured with push access to the repository
#   - HCP Terraform configured for the repository
#   - EKS cluster deployed in us-west-2 (eks-usw2)
#
# Usage:
#   ./scripts/deploy-karpenter.sh [OPTIONS]
#
# Options:
#   --dry-run         Show changes without applying them
#   --skip-push       Make changes but don't commit/push
#   --disable         Remove Karpenter instead of deploying
#   --no-pause        Skip interactive pauses (fully automated)
#   --help            Show this help message
################################################################################

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPONENTS_FILE="$PROJECT_ROOT/components.tfcomponent.hcl"
EKS_MAIN_FILE="$PROJECT_ROOT/modules/eks/main.tf"
EKS_OUTPUTS_FILE="$PROJECT_ROOT/modules/eks/outputs.tf"

# Cluster configuration
CLUSTER_NAME="${CLUSTER_NAME:-eks-usw2}"
REGION="${REGION:-us-west-2}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Options
DRY_RUN=false
SKIP_PUSH=false
DISABLE_MODE=false
NO_PAUSE=false

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

print_phase() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
}

print_step() {
    echo -e "${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

show_help() {
    head -25 "$0" | tail -20
    exit 0
}

wait_for_user() {
    if [ "$NO_PAUSE" = true ]; then
        print_info "Skipping pause (--no-pause flag set)"
        return 0
    fi

    echo ""
    echo -e "${GREEN}Press Enter when ready to continue...${NC}"
    read -r
}

################################################################################
# Parse Arguments
################################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-push)
            SKIP_PUSH=true
            shift
            ;;
        --disable)
            DISABLE_MODE=true
            shift
            ;;
        --no-pause)
            NO_PAUSE=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

################################################################################
# Check Functions
################################################################################

check_karpenter_component_exists() {
    grep -q 'component "karpenter"' "$COMPONENTS_FILE" 2>/dev/null
}

check_kubectl_provider_exists() {
    grep -q 'provider "kubectl"' "$COMPONENTS_FILE" 2>/dev/null
}

check_virginia_provider_exists() {
    grep -q 'provider "aws" "virginia"' "$COMPONENTS_FILE" 2>/dev/null
}

check_eks_karpenter_labels() {
    grep -q '"karpenter.sh/controller"' "$EKS_MAIN_FILE" 2>/dev/null
}

check_eks_node_iam_output() {
    grep -q 'output "node_iam_role_arn"' "$EKS_OUTPUTS_FILE" 2>/dev/null
}

################################################################################
# DISABLE MODE
################################################################################

if [ "$DISABLE_MODE" = true ]; then
    print_header "DISABLING Karpenter"

    if [ "$DRY_RUN" = true ]; then
        print_warn "DRY RUN MODE - No changes will be made"
    fi

    cd "$PROJECT_ROOT"

    # Check if Karpenter component exists (not already removed)
    if ! check_karpenter_component_exists; then
        # Check if already has a removed block
        if grep -q 'from.*=.*component.karpenter' "$COMPONENTS_FILE" 2>/dev/null; then
            print_warn "Karpenter already has a 'removed' block in components.tfcomponent.hcl"
            print_info "HCP Terraform should destroy the resources on next apply"
            exit 0
        fi
        print_warn "Karpenter component not found in components.tfcomponent.hcl"
        print_info "Nothing to disable"
        exit 0
    fi

    print_step "Replacing Karpenter component with 'removed' block..."
    print_info "Terraform Stacks requires a 'removed' block to properly destroy resources"

    if [ "$DRY_RUN" = false ]; then
        # Replace the Karpenter component block with a removed block
        # Use awk to find and replace the component section

        TEMP_FILE=$(mktemp)

        awk '
        BEGIN {
            in_karpenter = 0
            brace_count = 0
            printed_removed = 0
        }
        /^#-+$/ && !in_karpenter {
            # Store potential section start
            stored_line = $0
            getline next_line
            if (next_line ~ /Karpenter Component/) {
                # This is the Karpenter section header
                # Print modified header
                print "#-------------------------------------------------------------------------------"
                print "# Karpenter Component (REMOVED)"
                print "# This removed block ensures proper cleanup of Karpenter resources"
                print "#-------------------------------------------------------------------------------"
                print ""
                print "removed {"
                print "  source = \"./modules/karpenter\""
                print "  from   = component.karpenter"
                print ""
                print "  providers = {"
                print "    aws          = provider.aws.main"
                print "    aws.virginia = provider.aws.virginia"
                print "    helm         = provider.helm.main"
                print "    kubernetes   = provider.kubernetes.main"
                print "    kubectl      = provider.kubectl.main"
                print "  }"
                print "}"
                printed_removed = 1
                in_karpenter = 1
                next
            } else {
                # Not Karpenter section, print both lines
                print stored_line
                print next_line
                next
            }
        }
        in_karpenter {
            if (/^component "karpenter"/) {
                brace_count = 1
            } else if (/{/) {
                brace_count++
            } else if (/^}$/) {
                brace_count--
                if (brace_count == 0) {
                    in_karpenter = 0
                }
            }
            next
        }
        {
            print
        }
        ' "$COMPONENTS_FILE" > "$TEMP_FILE"

        mv "$TEMP_FILE" "$COMPONENTS_FILE"
        print_success "Karpenter component replaced with 'removed' block"
    else
        print_info "Would replace Karpenter component with 'removed' block"
    fi

    print_step "Removing Karpenter outputs..."

    if [ "$DRY_RUN" = false ]; then
        # Remove karpenter outputs
        sed -i.bak '/^output "karpenter_iam_role_arn"/,/^}/d' "$COMPONENTS_FILE"
        sed -i.bak '/^output "karpenter_node_iam_role_arn"/,/^}/d' "$COMPONENTS_FILE"
        rm -f "$COMPONENTS_FILE.bak"
        print_success "Karpenter outputs removed"
    else
        print_info "Would remove Karpenter outputs"
    fi

    print_step "Reviewing changes..."
    echo ""
    git --no-pager diff --stat 2>/dev/null || true
    echo ""
    git --no-pager diff "$COMPONENTS_FILE" 2>/dev/null | head -80
    echo ""

    if [ "$DRY_RUN" = true ]; then
        print_phase "DRY RUN COMPLETE"
        print_info "Run without --dry-run to apply changes"
        exit 0
    fi

    if [ "$SKIP_PUSH" = true ]; then
        print_phase "CHANGES MADE (skip-push)"
        print_info "Changes made to local files. Commit and push manually when ready."
        exit 0
    fi

    # Commit and push
    print_step "Committing changes..."
    git add "$COMPONENTS_FILE"
    git commit -m "chore: Disable Karpenter addon

Replaces Karpenter component with 'removed' block to trigger
proper HCP Terraform destroy of all Karpenter resources.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

    print_step "Pushing to trigger HCP Terraform..."
    git push
    print_success "Changes pushed"

    print_phase "WAITING FOR HCP TERRAFORM"
    echo ""
    print_info "HCP Terraform will destroy:"
    echo "    - NodePool and EC2NodeClass"
    echo "    - Karpenter Helm release"
    echo "    - IAM roles and policies"
    echo "    - SQS queue (if spot termination was enabled)"
    echo ""
    print_info "Please approve the plan in HCP Terraform UI:"
    echo "    https://app.terraform.io/"
    echo ""
    print_warn "After HCP Terraform completes the destroy, you can optionally"
    print_warn "remove the 'removed' block from components.tfcomponent.hcl"
    echo ""

    wait_for_user

    print_phase "VERIFYING KARPENTER REMOVAL"

    print_step "Updating kubeconfig for $CLUSTER_NAME..."
    aws eks --region "$REGION" update-kubeconfig --name "$CLUSTER_NAME" 2>/dev/null || {
        print_warn "Could not update kubeconfig automatically"
        print_info "Run: aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME"
    }

    print_step "Checking Karpenter namespace..."
    if kubectl get namespace karpenter 2>/dev/null; then
        print_warn "Karpenter namespace still exists"
        print_info "Deleting namespace..."
        kubectl delete namespace karpenter --timeout=60s 2>/dev/null || print_warn "Could not delete namespace"
    else
        print_success "Karpenter namespace removed"
    fi

    print_step "Checking Karpenter pods..."
    if kubectl get pods -n karpenter 2>/dev/null | grep -q "."; then
        print_warn "Karpenter pods still exist"
        kubectl get pods -n karpenter
    else
        print_success "No Karpenter pods found"
    fi

    print_step "Checking Karpenter Helm release..."
    if helm list -n karpenter 2>/dev/null | grep -q karpenter; then
        print_warn "Karpenter Helm release still exists"
        print_info "Uninstalling Helm release..."
        helm uninstall karpenter -n karpenter 2>/dev/null || print_warn "Could not uninstall Helm release"
    else
        print_success "No Karpenter Helm release found"
    fi

    print_step "Checking NodePool CRDs..."
    if kubectl get nodepools.karpenter.sh 2>/dev/null | grep -q "."; then
        print_warn "NodePools still exist"
        kubectl get nodepools.karpenter.sh
        print_info "Deleting NodePools..."
        kubectl delete nodepools.karpenter.sh --all 2>/dev/null || print_warn "Could not delete NodePools"
    else
        print_success "No NodePools found"
    fi

    print_step "Checking EC2NodeClass CRDs..."
    if kubectl get ec2nodeclasses.karpenter.k8s.aws 2>/dev/null | grep -q "."; then
        print_warn "EC2NodeClasses still exist"
        kubectl get ec2nodeclasses.karpenter.k8s.aws
        print_info "Deleting EC2NodeClasses..."
        kubectl delete ec2nodeclasses.karpenter.k8s.aws --all 2>/dev/null || print_warn "Could not delete EC2NodeClasses"
    else
        print_success "No EC2NodeClasses found"
    fi

    print_step "Checking Karpenter CRDs..."
    KARPENTER_CRDS=$(kubectl get crd 2>/dev/null | grep karpenter || true)
    if [ -n "$KARPENTER_CRDS" ]; then
        print_warn "Karpenter CRDs still exist:"
        echo "$KARPENTER_CRDS"
        print_info "Deleting Karpenter CRDs..."
        kubectl delete crd nodepools.karpenter.sh 2>/dev/null || true
        kubectl delete crd ec2nodeclasses.karpenter.k8s.aws 2>/dev/null || true
        kubectl delete crd nodeclaims.karpenter.sh 2>/dev/null || true
        print_success "Karpenter CRDs deleted"
    else
        print_success "No Karpenter CRDs found"
    fi

    print_phase "KARPENTER DISABLED"
    print_success "Karpenter resources have been destroyed"
    print_info "EKS labels/taints remain (harmless without Karpenter)"
    echo ""
    print_info "Optional: After destroy completes, remove the 'removed' block:"
    echo "    Edit components.tfcomponent.hcl and delete the Karpenter removed section"
    echo ""

    exit 0
fi

################################################################################
# ENABLE MODE
################################################################################

print_header "DEPLOYING Karpenter"

if [ "$DRY_RUN" = true ]; then
    print_warn "DRY RUN MODE - No changes will be made"
fi

cd "$PROJECT_ROOT"

# Check if there are uncommitted changes that need to be pushed
HAS_UNCOMMITTED_CHANGES=false
if ! git diff --quiet modules/eks/ components.tfcomponent.hcl 2>/dev/null; then
    HAS_UNCOMMITTED_CHANGES=true
fi

# Check if Karpenter is fully deployed and running
KARPENTER_RUNNING=false
if check_karpenter_component_exists && [ "$HAS_UNCOMMITTED_CHANGES" = false ]; then
    # Check if actually running in cluster
    aws eks --region "$REGION" update-kubeconfig --name "$CLUSTER_NAME" 2>/dev/null || true
    if kubectl get pods -n karpenter --no-headers 2>/dev/null | grep -q "Running"; then
        KARPENTER_RUNNING=true
    fi
fi

# If already deployed and running, just verify
if [ "$KARPENTER_RUNNING" = true ]; then
    print_info "Karpenter is already deployed and running"
    print_info "Verifying deployment..."

    print_phase "PHASE 3: Verifying Karpenter Deployment"

    print_step "Checking Karpenter pods..."
    print_success "Karpenter controller running"
    kubectl get pods -n karpenter

    print_step "Checking NodePool..."
    if kubectl get nodepools.karpenter.sh default 2>/dev/null; then
        print_success "NodePool 'default' exists"
    else
        print_warn "NodePool 'default' not found"
    fi

    print_step "Checking EC2NodeClass..."
    if kubectl get ec2nodeclasses.karpenter.k8s.aws default 2>/dev/null; then
        print_success "EC2NodeClass 'default' exists"
    else
        print_warn "EC2NodeClass 'default' not found"
    fi

    print_phase "VERIFICATION COMPLETE"
    print_info "Test with: ./scripts/test-karpenter.sh"
    exit 0
fi

# If we have uncommitted changes, we need to deploy them
if [ "$HAS_UNCOMMITTED_CHANGES" = true ]; then
    print_info "Found uncommitted changes - proceeding with deployment"
fi

################################################################################
# PHASE 1: EKS Prerequisites
################################################################################

print_phase "PHASE 1: Deploying EKS Prerequisites for Karpenter"

# Show what's configured
print_step "Checking EKS module configuration..."

if check_eks_karpenter_labels; then
    print_success "EKS module has Karpenter labels/taints configured"
else
    print_warn "EKS module missing Karpenter labels/taints"
fi

if check_eks_node_iam_output; then
    print_success "EKS module has node_iam_role_arn output"
else
    print_warn "EKS module missing node_iam_role_arn output"
fi

print_step "Checking provider configuration..."

if check_kubectl_provider_exists; then
    print_success "kubectl provider configured"
else
    print_warn "kubectl provider not configured"
fi

if check_virginia_provider_exists; then
    print_success "aws.virginia provider configured"
else
    print_warn "aws.virginia provider not configured"
fi

# Check for uncommitted changes in EKS module and eks-blueprints-addons
HAS_EKS_CHANGES=false
HAS_ADDONS_CHANGES=false

if ! git diff --quiet modules/eks/ 2>/dev/null; then
    HAS_EKS_CHANGES=true
fi

if ! git diff --quiet modules/eks-blueprints-addons/ 2>/dev/null; then
    HAS_ADDONS_CHANGES=true
fi

if [ "$HAS_EKS_CHANGES" = true ] || [ "$HAS_ADDONS_CHANGES" = true ]; then
    echo ""
    print_step "Reviewing Phase 1 changes..."
    echo ""
    echo "Changes to be committed:"
    git --no-pager diff --stat modules/eks/ modules/eks-blueprints-addons/ 2>/dev/null || true
    echo ""
    git --no-pager diff modules/eks/ modules/eks-blueprints-addons/ 2>/dev/null | head -100
    echo ""

    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN - Would commit these changes"
    elif [ "$SKIP_PUSH" = true ]; then
        print_info "SKIP PUSH - Changes not committed"
    else
        print_step "Committing Phase 1 changes..."
        git add modules/eks/ modules/eks-blueprints-addons/
        git commit -m "feat: Add EKS prerequisites for Karpenter

- Add karpenter.sh/controller label to managed node group
- Add CriticalAddonsOnly taint to managed node group
- Add karpenter.sh/discovery tag to node security group
- Add node_iam_role_arn output
- Remove Karpenter from eks-blueprints-addons (using dedicated module)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

        print_step "Pushing to trigger HCP Terraform..."
        git push
        print_success "Phase 1 pushed"

        print_phase "WAITING FOR HCP TERRAFORM"
        echo ""
        print_info "Phase 1 changes pushed. HCP Terraform will:"
        echo "    - Update EKS managed node group with labels/taints"
        echo "    - Add security group tags for Karpenter discovery"
        echo "    - Remove Karpenter config from eks-blueprints-addons"
        echo ""
        print_info "Please approve the plan in HCP Terraform UI:"
        echo "    https://app.terraform.io/"
        echo ""

        wait_for_user
    fi
else
    print_success "Phase 1 prerequisites already committed"
fi

################################################################################
# PHASE 2: Deploy Karpenter Component
################################################################################

print_phase "PHASE 2: Deploying Karpenter Component"

# Show what's configured
print_step "Checking Karpenter component configuration..."

if check_karpenter_component_exists; then
    print_success "Karpenter component configured in components.tfcomponent.hcl"
else
    print_warn "Karpenter component not configured"
fi

# Check for uncommitted changes in components file
HAS_COMPONENTS_CHANGES=false
if ! git diff --quiet "$COMPONENTS_FILE" 2>/dev/null; then
    HAS_COMPONENTS_CHANGES=true
fi

if [ "$HAS_COMPONENTS_CHANGES" = true ]; then
    echo ""
    print_step "Reviewing Phase 2 changes..."
    echo ""
    echo "Changes to be committed:"
    git --no-pager diff --stat "$COMPONENTS_FILE" 2>/dev/null || true
    echo ""
    git --no-pager diff "$COMPONENTS_FILE" 2>/dev/null | head -150
    echo ""

    if [ "$DRY_RUN" = true ]; then
        print_info "DRY RUN - Would commit these changes"
        print_phase "DRY RUN COMPLETE"
        print_info "Run without --dry-run to apply changes"
        exit 0
    elif [ "$SKIP_PUSH" = true ]; then
        print_info "SKIP PUSH - Changes not committed"
        print_phase "CHANGES MADE (skip-push)"
        print_info "Changes made to local files. Commit and push manually when ready."
        exit 0
    else
        print_step "Committing Phase 2 changes..."
        git add "$COMPONENTS_FILE"
        git commit -m "feat: Deploy Karpenter component for node autoscaling

- Add kubectl and aws.virginia providers to stack
- Add Karpenter component using dedicated modules/karpenter
- Configure Karpenter with default NodePool and EC2NodeClass
- Enable spot termination handling via SQS
- Add Karpenter outputs

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

        print_step "Pushing to trigger HCP Terraform..."
        git push
        print_success "Phase 2 pushed"

        print_phase "WAITING FOR HCP TERRAFORM"
        echo ""
        print_info "Phase 2 changes pushed. HCP Terraform will:"
        echo "    - Create Karpenter IAM roles"
        echo "    - Deploy Karpenter Helm release"
        echo "    - Create default EC2NodeClass and NodePool"
        echo ""
        print_info "Please approve the plan in HCP Terraform UI:"
        echo "    https://app.terraform.io/"
        echo ""

        wait_for_user
    fi
else
    print_success "Phase 2 components already committed"
fi

################################################################################
# PHASE 3: Verification
################################################################################

print_phase "PHASE 3: Verifying Karpenter Deployment"

print_step "Updating kubeconfig for $CLUSTER_NAME..."
aws eks --region "$REGION" update-kubeconfig --name "$CLUSTER_NAME" 2>/dev/null || {
    print_warn "Could not update kubeconfig automatically"
    print_info "Run: aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME"
}

print_step "Checking Karpenter pods..."
sleep 5  # Give a moment for the deployment to start
if kubectl get pods -n karpenter --no-headers 2>/dev/null | grep -q "Running"; then
    print_success "Karpenter controller running"
    kubectl get pods -n karpenter
else
    print_warn "Karpenter pods not running yet"
    print_info "This is normal if HCP Terraform is still applying"
    kubectl get pods -n karpenter 2>/dev/null || print_info "Namespace 'karpenter' not found yet"
fi

print_step "Checking NodePool..."
if kubectl get nodepools.karpenter.sh default 2>/dev/null; then
    print_success "NodePool 'default' exists"
else
    print_warn "NodePool 'default' not found yet"
fi

print_step "Checking EC2NodeClass..."
if kubectl get ec2nodeclasses.karpenter.k8s.aws default 2>/dev/null; then
    print_success "EC2NodeClass 'default' exists"
else
    print_warn "EC2NodeClass 'default' not found yet"
fi

################################################################################
# Summary
################################################################################

print_phase "KARPENTER DEPLOYMENT COMPLETE"
print_success "Karpenter is now ready for use"
echo ""
print_info "Test with: ./scripts/test-karpenter.sh"
echo ""
print_info "To disable Karpenter later, run:"
echo "    ./scripts/deploy-karpenter.sh --disable"
echo ""
