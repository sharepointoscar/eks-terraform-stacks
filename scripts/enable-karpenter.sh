#!/bin/bash
################################################################################
# Karpenter Integration Helper Script
# Helps enable/disable Karpenter for Terraform Stacks deployments
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# File paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPONENTS_FILE="$PROJECT_ROOT/components.tfcomponent.hcl"
DEPLOYMENTS_FILE="$PROJECT_ROOT/deployments.tfdeploy.hcl"
EKS_MAIN_FILE="$PROJECT_ROOT/modules/eks/main.tf"
VPC_MAIN_FILE="$PROJECT_ROOT/modules/vpc/main.tf"
EKS_OUTPUTS_FILE="$PROJECT_ROOT/modules/eks/outputs.tf"
DOCS_FILE="$PROJECT_ROOT/docs/karpenter-advanced-exercise.md"

# Deployments
DEPLOYMENTS=("use1" "usw2" "euc1")

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Karpenter Integration Helper${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_prerequisites() {
    local missing=0

    echo -e "\n${BLUE}Checking prerequisites...${NC}\n"

    # Check if files exist
    if [[ -f "$COMPONENTS_FILE" ]]; then
        print_success "components.tfcomponent.hcl found"
    else
        print_error "components.tfcomponent.hcl not found"
        missing=1
    fi

    if [[ -f "$DEPLOYMENTS_FILE" ]]; then
        print_success "deployments.tfdeploy.hcl found"
    else
        print_error "deployments.tfdeploy.hcl not found"
        missing=1
    fi

    if [[ -d "$PROJECT_ROOT/modules/karpenter" ]]; then
        print_success "Karpenter module found"
    else
        print_error "Karpenter module not found at modules/karpenter/"
        missing=1
    fi

    # Check for kubectl
    if command -v kubectl &> /dev/null; then
        print_success "kubectl installed"
    else
        print_warning "kubectl not installed (required for verification)"
    fi

    # Check for AWS CLI
    if command -v aws &> /dev/null; then
        print_success "AWS CLI installed"
    else
        print_warning "AWS CLI not installed (required for cleanup)"
    fi

    if [[ $missing -eq 1 ]]; then
        print_error "\nMissing prerequisites. Please ensure all files exist."
        return 1
    fi

    return 0
}

################################################################################
# Status Functions
################################################################################

check_karpenter_status() {
    echo -e "\n${BLUE}Current Karpenter Status:${NC}\n"

    # Check if Karpenter component exists in components file
    if grep -q 'component "karpenter"' "$COMPONENTS_FILE" 2>/dev/null; then
        print_success "Karpenter component is configured in components.tfcomponent.hcl"
    else
        print_warning "Karpenter component NOT configured in components.tfcomponent.hcl"
    fi

    # Check EKS module for Karpenter labels
    if grep -q 'karpenter.sh/controller' "$EKS_MAIN_FILE" 2>/dev/null; then
        print_success "EKS module has Karpenter controller labels"
    else
        print_warning "EKS module missing Karpenter controller labels"
    fi

    # Check EKS module for Karpenter discovery tags
    if grep -q 'karpenter.sh/discovery' "$EKS_MAIN_FILE" 2>/dev/null; then
        print_success "EKS module has Karpenter discovery tags"
    else
        print_warning "EKS module missing Karpenter discovery tags"
    fi

    # Check VPC module for Karpenter subnet tags
    if grep -q 'karpenter.sh/discovery' "$VPC_MAIN_FILE" 2>/dev/null; then
        print_success "VPC module has Karpenter subnet tags"
    else
        print_warning "VPC module missing Karpenter subnet tags"
    fi

    echo ""
}

################################################################################
# Modification Functions
################################################################################

show_manual_steps() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Manual Steps Required${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

    echo -e "Please follow the step-by-step guide in:"
    echo -e "${GREEN}  $DOCS_FILE${NC}\n"

    echo -e "Summary of changes needed:\n"

    echo -e "${YELLOW}1. Update modules/eks/main.tf:${NC}"
    echo -e "   - Add 'karpenter.sh/controller' label to node group"
    echo -e "   - Add 'karpenter.sh/discovery' tag to cluster\n"

    echo -e "${YELLOW}2. Update modules/vpc/main.tf:${NC}"
    echo -e "   - Add 'karpenter.sh/discovery' tag to private subnets\n"

    echo -e "${YELLOW}3. Update modules/eks/outputs.tf:${NC}"
    echo -e "   - Add 'node_iam_role_arn' output\n"

    echo -e "${YELLOW}4. Update components.tfcomponent.hcl:${NC}"
    echo -e "   - Add kubectl provider"
    echo -e "   - Add aws.virginia provider"
    echo -e "   - Add Karpenter component\n"

    echo -e "${YELLOW}5. Commit and push changes:${NC}"
    echo -e "   git add ."
    echo -e "   git commit -m 'feat: Add Karpenter as optional component'"
    echo -e "   git push\n"

    read -p "Press Enter to continue..."
}

cleanup_karpenter_nodes() {
    echo -e "\n${BLUE}Karpenter Node Cleanup${NC}\n"

    echo -e "Before destroying infrastructure, you must remove Karpenter-provisioned nodes.\n"

    echo -e "${YELLOW}For each cluster, run these commands:${NC}\n"

    for deployment in "${DEPLOYMENTS[@]}"; do
        case $deployment in
            use1) region="us-east-1"; cluster="eks-use1" ;;
            usw2) region="us-west-2"; cluster="eks-usw2" ;;
            euc1) region="eu-central-1"; cluster="eks-euc1" ;;
        esac

        echo -e "${GREEN}# $deployment ($region)${NC}"
        echo -e "aws eks update-kubeconfig --region $region --name $cluster"
        echo -e "kubectl delete nodepools --all"
        echo -e "kubectl delete ec2nodeclasses --all"
        echo -e "# Wait for nodes to terminate"
        echo -e "aws ec2 describe-instances --region $region \\"
        echo -e "  --filters \"Name=tag:karpenter.sh/discovery,Values=$cluster\" \\"
        echo -e "  --query 'Reservations[].Instances[].State.Name'\n"
    done

    read -p "Press Enter to continue..."
}

open_documentation() {
    echo -e "\n${BLUE}Opening documentation...${NC}\n"

    if [[ -f "$DOCS_FILE" ]]; then
        # Try to open with default editor or viewer
        if command -v code &> /dev/null; then
            code "$DOCS_FILE"
            print_success "Opened in VS Code"
        elif command -v open &> /dev/null; then
            open "$DOCS_FILE"
            print_success "Opened with default application"
        else
            echo -e "\nDocumentation location:"
            echo -e "${GREEN}$DOCS_FILE${NC}\n"
            print_info "Use 'cat $DOCS_FILE' to view"
        fi
    else
        print_error "Documentation file not found"
    fi

    read -p "Press Enter to continue..."
}

################################################################################
# Main Menu
################################################################################

show_menu() {
    clear
    print_header

    echo -e "Select an option:\n"
    echo -e "  ${GREEN}1)${NC} View current Karpenter status"
    echo -e "  ${GREEN}2)${NC} Show manual integration steps"
    echo -e "  ${GREEN}3)${NC} Show cleanup steps (before destroy)"
    echo -e "  ${GREEN}4)${NC} Open documentation"
    echo -e "  ${GREEN}5)${NC} Check prerequisites"
    echo -e "  ${GREEN}6)${NC} Exit\n"
}

main() {
    while true; do
        show_menu
        read -p "Enter your choice [1-6]: " choice

        case $choice in
            1)
                check_karpenter_status
                read -p "Press Enter to continue..."
                ;;
            2)
                show_manual_steps
                ;;
            3)
                cleanup_karpenter_nodes
                ;;
            4)
                open_documentation
                ;;
            5)
                check_prerequisites
                read -p "Press Enter to continue..."
                ;;
            6)
                echo -e "\n${GREEN}Goodbye!${NC}\n"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please try again."
                sleep 1
                ;;
        esac
    done
}

# Run main function
main
