#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$ROOT_DIR/terraform"

echo "============================================"
echo "  Observability Demo - Reset Security State"
echo "============================================"
echo ""
echo "This will restore all intentionally misconfigured resources"
echo "to their vulnerable state and trigger Security Hub re-scan."
echo ""

# Re-apply Terraform to restore intentionally vulnerable resources.
# Aiden's remediations (SG rule removal, S3 block public access, etc.)
# show up as drift -- terraform apply reverts them to the "broken" state.
# The terraform_data.trigger_config_evaluation resource automatically
# triggers AWS Config re-evaluation, so Security Hub findings reappear
# within 1-3 minutes.
echo "[1/2] Restoring misconfigured resources via Terraform..."
terraform -chdir="$TERRAFORM_DIR" apply -auto-approve

echo ""
echo "[2/2] Verifying vulnerable state..."

REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw region)
SG_ID=$(terraform -chdir="$TERRAFORM_DIR" output -raw vulnerable_sg_id)
BUCKET=$(terraform -chdir="$TERRAFORM_DIR" output -raw vulnerable_bucket)
EBS_ID=$(terraform -chdir="$TERRAFORM_DIR" output -raw vulnerable_ebs_id)
IAM_ROLE=$(terraform -chdir="$TERRAFORM_DIR" output -raw vulnerable_iam_role)

PASS=true

# Check SG has 0.0.0.0/0 ingress rule
SG_OPEN=$(aws ec2 describe-security-groups --group-ids "$SG_ID" --region "$REGION" \
  --query "SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp=='0.0.0.0/0']] | length(@)" \
  --output text 2>/dev/null || echo "0")
if [ "$SG_OPEN" -gt 0 ]; then
  echo "  [OK] Security group $SG_ID has 0.0.0.0/0 ingress rule"
else
  echo "  [WARN] Security group $SG_ID missing 0.0.0.0/0 rule"
  PASS=false
fi

# Check S3 Block Public Access is off
S3_BLOCK=$(aws s3api get-public-access-block --bucket "$BUCKET" --region "$REGION" \
  --query "PublicAccessBlockConfiguration.BlockPublicAcls" \
  --output text 2>/dev/null || echo "true")
if [ "$S3_BLOCK" = "False" ] || [ "$S3_BLOCK" = "false" ]; then
  echo "  [OK] S3 bucket $BUCKET has Block Public Access disabled"
else
  echo "  [WARN] S3 bucket $BUCKET still has Block Public Access enabled"
  PASS=false
fi

# Check EBS volume is unencrypted
EBS_ENC=$(aws ec2 describe-volumes --volume-ids "$EBS_ID" --region "$REGION" \
  --query "Volumes[0].Encrypted" \
  --output text 2>/dev/null || echo "true")
if [ "$EBS_ENC" = "False" ] || [ "$EBS_ENC" = "false" ]; then
  echo "  [OK] EBS volume $EBS_ID is unencrypted"
else
  echo "  [WARN] EBS volume $EBS_ID is encrypted"
  PASS=false
fi

# Check IAM role has AdministratorAccess
IAM_ADMIN=$(aws iam list-attached-role-policies --role-name "$IAM_ROLE" \
  --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AdministratorAccess'] | length(@)" \
  --output text 2>/dev/null || echo "0")
if [ "$IAM_ADMIN" -gt 0 ]; then
  echo "  [OK] IAM role $IAM_ROLE has AdministratorAccess attached"
else
  echo "  [WARN] IAM role $IAM_ROLE missing AdministratorAccess"
  PASS=false
fi

echo ""
if [ "$PASS" = true ]; then
  echo "============================================"
  echo "  Reset Complete - All resources vulnerable"
  echo "============================================"
else
  echo "============================================"
  echo "  Reset Complete - Some checks had warnings"
  echo "============================================"
fi

echo ""
echo "Config rule re-evaluation was triggered automatically."
echo "Findings should reappear in Security Hub within 1-3 minutes."
echo ""
echo "Run ./scripts/check-findings.sh to monitor."
