#!/usr/bin/env bash
################################################################################
# Cleanup Orphaned AWS Resources
#
# This script removes orphaned AWS resources that may remain after a failed
# or incomplete Terraform Stacks destroy operation.
#
# Resources cleaned:
# - CloudWatch Log Groups (/aws/eks/<cluster>/cluster)
# - KMS Aliases (alias/eks/<cluster>)
# - EKS Clusters (if still exist)
# - EKS Node Groups (if still exist)
#
# Usage:
#   bash scripts/cleanup-orphaned-resources.sh
#
# Requirements:
#   - Bash 4.0+ (macOS users: brew install bash)
#   - AWS CLI configured with appropriate credentials
################################################################################

# Ensure we're running with bash 4+
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "Error: This script requires Bash 4.0 or higher."
    echo "Your version: ${BASH_VERSION}"
    echo ""
    echo "On macOS, install newer bash with: brew install bash"
    echo "Then run: /opt/homebrew/bin/bash scripts/cleanup-orphaned-resources.sh"
    exit 1
fi

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Cluster configurations (cluster_name:region)
CLUSTER_LIST=(
    "eks-use1:us-east-1"
    "eks-usw2:us-west-2"
    "eks-euc1:eu-central-1"
)

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Cleanup Orphaned AWS Resources${NC}"
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

print_section() {
    echo -e "\n${YELLOW}─────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}  $1${NC}"
    echo -e "${YELLOW}─────────────────────────────────────────────────────────────────${NC}\n"
}

################################################################################
# Cleanup Functions
################################################################################

cleanup_cloudwatch_logs() {
    local cluster=$1
    local region=$2
    local log_group="/aws/eks/${cluster}/cluster"

    echo -n "  CloudWatch Log Group: ${log_group}... "

    if aws logs describe-log-groups \
        --log-group-name-prefix "$log_group" \
        --region "$region" \
        --query 'logGroups[0].logGroupName' \
        --output text 2>/dev/null | grep -q "$log_group"; then

        if aws logs delete-log-group \
            --log-group-name "$log_group" \
            --region "$region" 2>/dev/null; then
            echo -e "${GREEN}deleted${NC}"
            return 0
        else
            echo -e "${RED}failed to delete${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}not found (skipped)${NC}"
        return 0
    fi
}

cleanup_kms_alias() {
    local cluster=$1
    local region=$2
    local alias_name="alias/eks/${cluster}"

    echo -n "  KMS Alias: ${alias_name}... "

    if aws kms describe-key \
        --key-id "$alias_name" \
        --region "$region" 2>/dev/null | grep -q "KeyId"; then

        if aws kms delete-alias \
            --alias-name "$alias_name" \
            --region "$region" 2>/dev/null; then
            echo -e "${GREEN}deleted${NC}"
            return 0
        else
            echo -e "${RED}failed to delete${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}not found (skipped)${NC}"
        return 0
    fi
}

cleanup_eks_nodegroups() {
    local cluster=$1
    local region=$2

    echo -n "  EKS Node Groups for ${cluster}... "

    # Check if cluster exists first
    if ! aws eks describe-cluster \
        --name "$cluster" \
        --region "$region" 2>/dev/null | grep -q "clusterName"; then
        echo -e "${YELLOW}cluster not found (skipped)${NC}"
        return 0
    fi

    # Get node groups
    local nodegroups
    nodegroups=$(aws eks list-nodegroups \
        --cluster-name "$cluster" \
        --region "$region" \
        --query 'nodegroups[]' \
        --output text 2>/dev/null)

    if [[ -z "$nodegroups" ]]; then
        echo -e "${YELLOW}none found${NC}"
        return 0
    fi

    echo ""
    for ng in $nodegroups; do
        echo -n "    Deleting node group: ${ng}... "
        if aws eks delete-nodegroup \
            --cluster-name "$cluster" \
            --nodegroup-name "$ng" \
            --region "$region" 2>/dev/null; then
            echo -e "${GREEN}initiated${NC}"
        else
            echo -e "${RED}failed${NC}"
        fi
    done

    # Wait for node groups to delete
    echo -n "    Waiting for node groups to delete... "
    local max_wait=600  # 10 minutes
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        local remaining
        remaining=$(aws eks list-nodegroups \
            --cluster-name "$cluster" \
            --region "$region" \
            --query 'nodegroups[]' \
            --output text 2>/dev/null)

        if [[ -z "$remaining" ]]; then
            echo -e "${GREEN}done${NC}"
            return 0
        fi

        sleep 15
        waited=$((waited + 15))
        echo -n "."
    done

    echo -e "${YELLOW}timeout (continuing)${NC}"
    return 0
}

cleanup_eks_cluster() {
    local cluster=$1
    local region=$2

    echo -n "  EKS Cluster: ${cluster}... "

    if aws eks describe-cluster \
        --name "$cluster" \
        --region "$region" 2>/dev/null | grep -q "clusterName"; then

        if aws eks delete-cluster \
            --name "$cluster" \
            --region "$region" 2>/dev/null; then
            echo -e "${GREEN}delete initiated${NC}"

            # Wait for cluster to delete
            echo -n "    Waiting for cluster to delete... "
            local max_wait=900  # 15 minutes
            local waited=0
            while [[ $waited -lt $max_wait ]]; do
                if ! aws eks describe-cluster \
                    --name "$cluster" \
                    --region "$region" 2>/dev/null | grep -q "clusterName"; then
                    echo -e "${GREEN}done${NC}"
                    return 0
                fi
                sleep 30
                waited=$((waited + 30))
                echo -n "."
            done
            echo -e "${YELLOW}timeout (continuing)${NC}"
            return 0
        else
            echo -e "${RED}failed to delete${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}not found (skipped)${NC}"
        return 0
    fi
}

cleanup_vpc_resources() {
    local cluster=$1
    local region=$2

    echo -n "  VPC resources tagged with ${cluster}... "

    # Find VPCs with the cluster tag
    local vpc_id
    vpc_id=$(aws ec2 describe-vpcs \
        --region "$region" \
        --filters "Name=tag:Name,Values=${cluster}*" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null)

    if [[ "$vpc_id" == "None" ]] || [[ -z "$vpc_id" ]]; then
        echo -e "${YELLOW}not found (skipped)${NC}"
        return 0
    fi

    echo -e "${YELLOW}found ${vpc_id}${NC}"
    print_warning "    VPC cleanup requires manual intervention or re-running destroy"
    print_info "    VPC ID: ${vpc_id} in ${region}"
    return 0
}

################################################################################
# Main
################################################################################

main() {
    print_header

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi

    local account_id
    account_id=$(aws sts get-caller-identity --query 'Account' --output text)
    print_info "AWS Account: ${account_id}"

    local errors=0

    for item in "${CLUSTER_LIST[@]}"; do
        cluster="${item%%:*}"
        region="${item##*:}"

        print_section "Cleaning up: ${cluster} (${region})"

        # Order matters: node groups -> cluster -> other resources
        cleanup_eks_nodegroups "$cluster" "$region" || ((errors++))
        cleanup_eks_cluster "$cluster" "$region" || ((errors++))
        cleanup_cloudwatch_logs "$cluster" "$region" || ((errors++))
        cleanup_kms_alias "$cluster" "$region" || ((errors++))
        cleanup_vpc_resources "$cluster" "$region" || ((errors++))
    done

    echo ""
    print_section "Summary"

    if [[ $errors -eq 0 ]]; then
        print_success "Cleanup completed successfully!"
        echo ""
        print_info "You can now re-deploy with 'destroy = false' in deployments.tfdeploy.hcl"
    else
        print_warning "Cleanup completed with ${errors} error(s)"
        echo ""
        print_info "Some resources may need manual cleanup in the AWS Console"
    fi

    echo ""
}

# Run main
main "$@"
