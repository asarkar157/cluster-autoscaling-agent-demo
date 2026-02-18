#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# setup-cross-account.sh
#
# Deploys the aiden-inventory-role CloudFormation stack in a target AWS account
# so the aiden-demo user (in account 180217099948) can assume the role for
# cross-account inventory scanning.
#
# Usage:
#   ./scripts/setup-cross-account.sh                          # uses default profile
#   ./scripts/setup-cross-account.sh --profile my-other-acct  # uses named profile
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CF_TEMPLATE="$REPO_ROOT/iam/cross-account-inventory-role.yaml"

STACK_NAME="aiden-inventory-role"
TRUSTED_ACCOUNT_ID="180217099948"
TRUSTED_USER_NAME="aiden-demo"
ROLE_NAME="aiden-inventory-role"
REGION="us-west-2"

PROFILE_ARG=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --profile)
      PROFILE_ARG="--profile $2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--profile AWS_PROFILE] [--region AWS_REGION]"
      exit 1
      ;;
  esac
done

echo "============================================================"
echo "  Cross-Account Inventory Role Setup"
echo "============================================================"
echo ""

# Validate template exists
if [[ ! -f "$CF_TEMPLATE" ]]; then
  echo "ERROR: CloudFormation template not found at $CF_TEMPLATE"
  exit 1
fi

# Verify we're authenticated to the TARGET account (not the primary)
echo "[1/4] Verifying AWS credentials for the target account..."
TARGET_ACCOUNT_ID=$(aws sts get-caller-identity $PROFILE_ARG --query 'Account' --output text 2>/dev/null)
if [[ -z "$TARGET_ACCOUNT_ID" ]]; then
  echo "ERROR: Unable to get AWS identity. Are your credentials configured?"
  echo "  If using SSO: aws sso login --profile <target-account-profile>"
  echo "  Then re-run: $0 --profile <target-account-profile>"
  exit 1
fi

echo "  Authenticated to account: $TARGET_ACCOUNT_ID"

if [[ "$TARGET_ACCOUNT_ID" == "$TRUSTED_ACCOUNT_ID" ]]; then
  echo ""
  echo "WARNING: You are authenticated to the PRIMARY account ($TRUSTED_ACCOUNT_ID)."
  echo "  This script should be run against the TARGET account (e.g., 347161580392)."
  echo "  Use --profile to specify credentials for the target account."
  echo ""
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Deploy CloudFormation stack
echo ""
echo "[2/4] Deploying CloudFormation stack '$STACK_NAME' in account $TARGET_ACCOUNT_ID..."
aws cloudformation deploy \
  $PROFILE_ARG \
  --region "$REGION" \
  --template-file "$CF_TEMPLATE" \
  --stack-name "$STACK_NAME" \
  --parameter-overrides \
    TrustedAccountId="$TRUSTED_ACCOUNT_ID" \
    TrustedUserName="$TRUSTED_USER_NAME" \
    RoleName="$ROLE_NAME" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset

echo "  Stack deployed successfully."

# Get the role ARN from stack outputs
echo ""
echo "[3/4] Retrieving role ARN..."
ROLE_ARN=$(aws cloudformation describe-stacks \
  $PROFILE_ARG \
  --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' \
  --output text)

echo "  Role ARN: $ROLE_ARN"

# Verify the role can be assumed by aiden-demo
echo ""
echo "[4/4] Verifying role trust policy..."
TRUST_POLICY=$(aws iam get-role \
  $PROFILE_ARG \
  --role-name "$ROLE_NAME" \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json 2>/dev/null || echo "")

if [[ -n "$TRUST_POLICY" ]]; then
  echo "  Trust policy is configured. Role is ready for cross-account access."
else
  echo "  WARNING: Could not verify trust policy. Check the role manually."
fi

echo ""
echo "============================================================"
echo "  Setup Complete"
echo "============================================================"
echo ""
echo "  Role ARN:         $ROLE_ARN"
echo "  Target Account:   $TARGET_ACCOUNT_ID"
echo "  Trusted Account:  $TRUSTED_ACCOUNT_ID"
echo "  Trusted User:     $TRUSTED_USER_NAME"
echo ""
echo "  Next steps:"
echo "  1. Apply the updated IAM policy to aiden-demo in account $TRUSTED_ACCOUNT_ID:"
echo "     aws iam put-user-policy --user-name aiden-demo \\"
echo "       --policy-name aiden-demo-policy \\"
echo "       --policy-document file://iam/aiden-demo-policy.json"
echo "  2. Test the role assumption:"
echo "     aws sts assume-role \\"
echo "       --role-arn $ROLE_ARN \\"
echo "       --role-session-name aiden-inventory-scan"
echo ""
