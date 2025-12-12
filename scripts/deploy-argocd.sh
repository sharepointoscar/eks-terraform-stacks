#!/bin/bash
################################################################################
# ArgoCD Addon Deployment Script
# Enables ArgoCD in the EKS Blueprints Addons module and triggers deployment
#
# This script:
#   1. Adds enable_argocd variable to the addons module (if not exists)
#   2. Enables ArgoCD in the addons module configuration
#   3. Commits and pushes changes to trigger HCP Terraform
#
# Prerequisites:
#   - Git configured with push access to the repository
#   - HCP Terraform configured for the repository
#
# Usage:
#   ./scripts/deploy-argocd.sh [OPTIONS]
#
# Options:
#   --dry-run         Show changes without applying them
#   --skip-push       Make changes but don't commit/push
#   --disable         Disable ArgoCD instead of enabling
#   --cleanup-crds    Also delete ArgoCD CRDs (use with --disable)
#   --help            Show this help message
################################################################################

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ADDONS_DIR="$PROJECT_ROOT/modules/eks-blueprints-addons"
VARIABLES_FILE="$ADDONS_DIR/variables.tf"
MAIN_FILE="$ADDONS_DIR/main.tf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Options
DRY_RUN=false
SKIP_PUSH=false
DISABLE_MODE=false
CLEANUP_CRDS=false

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

print_step() {
    echo -e "\n${YELLOW}▶ $1${NC}"
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
    head -30 "$0" | tail -25
    exit 0
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
        --cleanup-crds)
            CLEANUP_CRDS=true
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
# Main Script
################################################################################

if [ "$DISABLE_MODE" = true ]; then
    print_header "DISABLING ArgoCD Addon"
else
    print_header "DEPLOYING ArgoCD Addon"
fi

if [ "$DRY_RUN" = true ]; then
    print_warn "DRY RUN MODE - No changes will be made"
fi

# Change to project root
cd "$PROJECT_ROOT"

################################################################################
# Step 1: Check if ArgoCD variable exists
################################################################################

print_step "Step 1: Checking ArgoCD variable in variables.tf"

if grep -q "enable_argocd" "$VARIABLES_FILE" 2>/dev/null; then
    print_success "ArgoCD variable already exists in variables.tf"
    VARIABLE_EXISTS=true
else
    print_info "ArgoCD variable not found - will add it"
    VARIABLE_EXISTS=false
fi

################################################################################
# Step 2: Add ArgoCD variable if needed
################################################################################

if [ "$VARIABLE_EXISTS" = false ]; then
    print_step "Step 2: Adding enable_argocd variable to variables.tf"

    if [ "$DISABLE_MODE" = true ]; then
        DEFAULT_VALUE="false"
    else
        DEFAULT_VALUE="true"
    fi

    VARIABLE_BLOCK="
variable \"enable_argocd\" {
  description = \"Enable ArgoCD addon for GitOps\"
  type        = bool
  default     = $DEFAULT_VALUE
}"

    if [ "$DRY_RUN" = true ]; then
        print_info "Would add the following to variables.tf:"
        echo "$VARIABLE_BLOCK"
    else
        echo "$VARIABLE_BLOCK" >> "$VARIABLES_FILE"
        print_success "Added enable_argocd variable to variables.tf"
    fi
else
    print_step "Step 2: Skipping variable addition (already exists)"
fi

################################################################################
# Step 3: Check if ArgoCD is enabled in main.tf
################################################################################

print_step "Step 3: Checking ArgoCD configuration in main.tf"

if grep -q "enable_argocd" "$MAIN_FILE" 2>/dev/null; then
    print_success "ArgoCD configuration already exists in main.tf"
    CONFIG_EXISTS=true
else
    print_info "ArgoCD configuration not found - will add it"
    CONFIG_EXISTS=false
fi

################################################################################
# Step 4: Add/Update ArgoCD configuration in main.tf
################################################################################

if [ "$CONFIG_EXISTS" = false ]; then
    print_step "Step 4: Adding ArgoCD configuration to main.tf"

    if [ "$DRY_RUN" = true ]; then
        print_info "Would add 'enable_argocd = var.enable_argocd' to main.tf"
    else
        # Insert ArgoCD configuration after the load balancer controller line
        sed -i.bak '/enable_aws_load_balancer_controller/a\
\
  #---------------------------------------------------------------------------\
  # ArgoCD - GitOps Continuous Delivery\
  # https://argo-cd.readthedocs.io/\
  #---------------------------------------------------------------------------\
  enable_argocd = var.enable_argocd
' "$MAIN_FILE"
        rm -f "$MAIN_FILE.bak"
        print_success "Added ArgoCD configuration to main.tf"
    fi
else
    print_step "Step 4: ArgoCD configuration already exists in main.tf"
fi

################################################################################
# Step 5: Set enable_argocd default value
################################################################################

print_step "Step 5: Setting enable_argocd default value"

if [ "$DISABLE_MODE" = true ]; then
    TARGET_VALUE="false"
else
    TARGET_VALUE="true"
fi

if [ "$DRY_RUN" = true ]; then
    print_info "Would set enable_argocd default to: $TARGET_VALUE"
else
    # Update the default value in variables.tf
    if grep -q 'variable "enable_argocd"' "$VARIABLES_FILE" 2>/dev/null; then
        # Use sed to update the default value
        # This handles multi-line variable blocks
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' '/variable "enable_argocd"/,/^}/ s/default *= *\(true\|false\)/default     = '"$TARGET_VALUE"'/' "$VARIABLES_FILE"
        else
            # Linux
            sed -i '/variable "enable_argocd"/,/^}/ s/default *= *\(true\|false\)/default     = '"$TARGET_VALUE"'/' "$VARIABLES_FILE"
        fi
        print_success "Set enable_argocd default to: $TARGET_VALUE"
    fi
fi

################################################################################
# Step 6: Show changes
################################################################################

print_step "Step 6: Reviewing changes"

echo ""
echo "Changes to be committed:"
git --no-pager diff --stat modules/eks-blueprints-addons/ 2>/dev/null || true
echo ""
git --no-pager diff modules/eks-blueprints-addons/ 2>/dev/null || true

################################################################################
# Step 7: Commit and Push
################################################################################

if [ "$DRY_RUN" = true ]; then
    print_step "Step 7: Skipping commit/push (dry run)"
    print_info "Run without --dry-run to apply changes"
elif [ "$SKIP_PUSH" = true ]; then
    print_step "Step 7: Skipping commit/push (--skip-push flag)"
    print_info "Changes made to files. Commit and push manually when ready."
else
    print_step "Step 7: Committing and pushing changes"

    # Check if there are changes to commit
    if git --no-pager diff --quiet modules/eks-blueprints-addons/ 2>/dev/null; then
        print_warn "No changes to commit"
    else
        if [ "$DISABLE_MODE" = true ]; then
            COMMIT_MSG="chore: Disable ArgoCD addon"
        else
            COMMIT_MSG="feat: Enable ArgoCD addon for GitOps"
        fi

        git add modules/eks-blueprints-addons/
        git commit -m "$COMMIT_MSG"
        git push

        print_success "Changes committed and pushed"
    fi
fi

################################################################################
# Summary
################################################################################

print_header "SUMMARY"

if [ "$DRY_RUN" = true ]; then
    echo ""
    print_warn "DRY RUN - No changes were made"
    echo ""
    print_info "To apply changes, run:"
    echo "    ./scripts/deploy-argocd.sh"
elif [ "$SKIP_PUSH" = true ]; then
    echo ""
    print_success "Changes made to local files"
    echo ""
    print_info "To complete deployment:"
    echo "    1. Review changes: git diff modules/eks-blueprints-addons/"
    echo "    2. Commit: git add modules/eks-blueprints-addons/ && git commit -m 'feat: Enable ArgoCD'"
    echo "    3. Push: git push"
    echo "    4. Approve in HCP Terraform UI"
else
    echo ""
    if [ "$DISABLE_MODE" = true ]; then
        print_success "ArgoCD disable request pushed to repository"
        echo ""
        print_info "Next steps:"
        echo "    1. Go to HCP Terraform: https://app.terraform.io/"
        echo "    2. Navigate to your Stack"
        echo "    3. Review and approve the plan"
        echo "    4. Wait for deployment to complete (~5 minutes)"
        echo ""
        print_warn "Note: ArgoCD CRDs are kept by default to preserve data."
        print_info "After HCP Terraform applies, clean up CRDs and namespace with:"
        echo "    kubectl delete crd applications.argoproj.io"
        echo "    kubectl delete crd applicationsets.argoproj.io"
        echo "    kubectl delete crd appprojects.argoproj.io"
        echo "    kubectl delete namespace argocd"
        echo ""
        print_info "Or run this script again with --cleanup-crds to clean up now:"
        echo "    ./scripts/deploy-argocd.sh --disable --cleanup-crds"
    else
        print_success "ArgoCD enable request pushed to repository"
        echo ""
        print_info "Next steps:"
        echo "    1. Go to HCP Terraform: https://app.terraform.io/"
        echo "    2. Navigate to your Stack"
        echo "    3. Review and approve the plan"
        echo "    4. Wait for deployment to complete (~5 minutes)"
        echo ""
        print_info "After deployment, test with:"
        echo "    ./scripts/test-argocd.sh"
    fi
fi

################################################################################
# CRD Cleanup (if requested)
################################################################################

if [ "$CLEANUP_CRDS" = true ] && [ "$DISABLE_MODE" = true ]; then
    print_header "CLEANING UP ArgoCD CRDs"

    if [ "$DRY_RUN" = true ]; then
        print_info "Would delete the following CRDs:"
        echo "    - applications.argoproj.io"
        echo "    - applicationsets.argoproj.io"
        echo "    - appprojects.argoproj.io"
        print_info "Would delete namespace: argocd"
    else
        print_step "Deleting ArgoCD CRDs..."

        # Delete CRDs (ignore errors if they don't exist)
        kubectl delete crd applications.argoproj.io 2>/dev/null && print_success "Deleted CRD: applications.argoproj.io" || print_warn "CRD applications.argoproj.io not found"
        kubectl delete crd applicationsets.argoproj.io 2>/dev/null && print_success "Deleted CRD: applicationsets.argoproj.io" || print_warn "CRD applicationsets.argoproj.io not found"
        kubectl delete crd appprojects.argoproj.io 2>/dev/null && print_success "Deleted CRD: appprojects.argoproj.io" || print_warn "CRD appprojects.argoproj.io not found"

        print_step "Deleting ArgoCD namespace..."
        kubectl delete namespace argocd 2>/dev/null && print_success "Deleted namespace: argocd" || print_warn "Namespace argocd not found"

        print_success "ArgoCD cleanup complete"
    fi
fi

echo ""
