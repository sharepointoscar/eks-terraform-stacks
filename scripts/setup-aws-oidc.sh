#!/bin/bash
#===============================================================================
# Setup AWS IAM Role for HCP Terraform Stacks OIDC Authentication
#
# This script creates:
# 1. OIDC Identity Provider for HCP Terraform (if not exists)
# 2. IAM Role with trust policy for the Stack
# 3. Attaches AdministratorAccess policy (for workshop purposes)
#
# Usage: ./setup-aws-oidc.sh <HCP_ORG> <HCP_PROJECT> <STACK_NAME>
# Example: ./setup-aws-oidc.sh my-org my-project eks-multi-region
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# Input validation
#-------------------------------------------------------------------------------
if [ $# -ne 3 ]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    echo ""
    echo "Usage: $0 <HCP_ORG> <HCP_PROJECT> <STACK_NAME>"
    echo ""
    echo "Arguments:"
    echo "  HCP_ORG      - Your HCP Terraform organization name"
    echo "  HCP_PROJECT  - Your HCP Terraform project name"
    echo "  STACK_NAME   - Your Terraform Stack name"
    echo ""
    echo "Example:"
    echo "  $0 my-org my-project eks-multi-region"
    exit 1
fi

HCP_ORG="$1"
HCP_PROJECT="$2"
STACK_NAME="$3"

#-------------------------------------------------------------------------------
# Get AWS Account ID
#-------------------------------------------------------------------------------
echo -e "${YELLOW}Fetching AWS Account ID...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Could not retrieve AWS Account ID. Check your AWS credentials.${NC}"
    exit 1
fi

echo -e "${GREEN}AWS Account ID: ${AWS_ACCOUNT_ID}${NC}"

#-------------------------------------------------------------------------------
# Variables
#-------------------------------------------------------------------------------
OIDC_PROVIDER="app.terraform.io"
OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
ROLE_NAME="hcp-terraform-stacks-role"
POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

#-------------------------------------------------------------------------------
# Create OIDC Identity Provider (if not exists)
#-------------------------------------------------------------------------------
echo -e "${YELLOW}Checking for existing OIDC provider...${NC}"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" > /dev/null 2>&1; then
    echo -e "${GREEN}OIDC provider already exists.${NC}"
else
    echo -e "${YELLOW}Creating OIDC Identity Provider for HCP Terraform...${NC}"

    # Get the thumbprint for app.terraform.io
    THUMBPRINT="9e99a48a9960b14926bb7f3b02e22da2b0ab7280"

    aws iam create-open-id-connect-provider \
        --url "https://${OIDC_PROVIDER}" \
        --client-id-list "aws.workload.identity" \
        --thumbprint-list "$THUMBPRINT" > /dev/null

    echo -e "${GREEN}OIDC provider created successfully.${NC}"
fi

#-------------------------------------------------------------------------------
# Create Trust Policy
#-------------------------------------------------------------------------------
echo -e "${YELLOW}Creating trust policy...${NC}"

TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "app.terraform.io:aud": "aws.workload.identity"
        },
        "StringLike": {
          "app.terraform.io:sub": "organization:${HCP_ORG}:project:${HCP_PROJECT}:stack:${STACK_NAME}:*"
        }
      }
    }
  ]
}
EOF
)

#-------------------------------------------------------------------------------
# Create or Update IAM Role
#-------------------------------------------------------------------------------
echo -e "${YELLOW}Checking for existing IAM role...${NC}"

if aws iam get-role --role-name "$ROLE_NAME" > /dev/null 2>&1; then
    echo -e "${YELLOW}Role exists. Updating trust policy...${NC}"
    aws iam update-assume-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-document "$TRUST_POLICY" > /dev/null
    echo -e "${GREEN}Trust policy updated.${NC}"
else
    echo -e "${YELLOW}Creating IAM role: ${ROLE_NAME}...${NC}"
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "IAM role for HCP Terraform Stacks OIDC authentication" > /dev/null
    echo -e "${GREEN}IAM role created.${NC}"
fi

#-------------------------------------------------------------------------------
# Attach AdministratorAccess Policy
#-------------------------------------------------------------------------------
echo -e "${YELLOW}Attaching AdministratorAccess policy...${NC}"

aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN" > /dev/null 2>&1 || true

echo -e "${GREEN}Policy attached.${NC}"

#-------------------------------------------------------------------------------
# Output
#-------------------------------------------------------------------------------
ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

echo ""
echo -e "${GREEN}===============================================================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}===============================================================================${NC}"
echo ""
echo -e "Role ARN (use this in HCP Terraform):"
echo -e "${YELLOW}${ROLE_ARN}${NC}"
echo ""
echo -e "Next steps:"
echo -e "1. In HCP Terraform, set the ${YELLOW}aws_role_arn${NC} variable to:"
echo -e "   ${ROLE_ARN}"
echo ""
echo -e "2. Run your Stack deployment"
echo ""
echo -e "${GREEN}===============================================================================${NC}"
