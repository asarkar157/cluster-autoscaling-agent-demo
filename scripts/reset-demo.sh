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
echo "to their vulnerable state, archive old findings, regenerate"
echo "GuardDuty sample findings, and trigger Security Hub re-scan."
echo ""

# Re-apply Terraform to restore intentionally vulnerable resources.
# Aiden's remediations (SG rule removal, S3 block public access, etc.)
# show up as drift -- terraform apply reverts them to the "broken" state.
# The terraform_data.trigger_config_evaluation resource automatically
# triggers AWS Config re-evaluation, so Security Hub findings reappear
# within 1-3 minutes.
echo "[1/4] Restoring misconfigured resources via Terraform..."
terraform -chdir="$TERRAFORM_DIR" apply -auto-approve

REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw region)
DETECTOR_ID=$(terraform -chdir="$TERRAFORM_DIR" output -raw guardduty_detector_id)

echo ""
echo "[2/4] Archiving old GuardDuty findings in Security Hub..."
OLD_FINDINGS=$(aws securityhub get-findings --region "$REGION" \
  --filters '{
    "RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}],
    "ProductName":[{"Value":"GuardDuty","Comparison":"EQUALS"}],
    "WorkflowStatus":[{"Value":"RESOLVED","Comparison":"EQUALS"}]
  }' \
  --query 'Findings[].{Id:Id,ProductArn:ProductArn}' \
  --output json 2>/dev/null || echo "[]")

FINDING_COUNT=$(echo "$OLD_FINDINGS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [ "$FINDING_COUNT" -gt 0 ]; then
  IDENTIFIERS=$(echo "$OLD_FINDINGS" | python3 -c "
import sys, json
findings = json.load(sys.stdin)
ids = [{'Id': f['Id'], 'ProductArn': f['ProductArn']} for f in findings]
print(json.dumps(ids))
")
  aws securityhub batch-update-findings --region "$REGION" \
    --finding-identifiers "$IDENTIFIERS" \
    --record-state "ARCHIVED" 2>/dev/null || true
  echo "  Archived $FINDING_COUNT old GuardDuty findings."
else
  echo "  No old GuardDuty findings to archive."
fi

echo ""
echo "[3/4] Generating fresh GuardDuty sample findings..."
aws guardduty create-sample-findings \
  --detector-id "$DETECTOR_ID" \
  --finding-types \
    "Recon:EC2/PortProbeUnprotectedPort" \
    "UnauthorizedAccess:EC2/SSHBruteForce" \
    "UnauthorizedAccess:EC2/RDPBruteForce" \
    "UnauthorizedAccess:EC2/MaliciousIPCaller.Custom" \
    "UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS" \
    "CryptoCurrency:EC2/BitcoinTool.B!DNS" \
    "Policy:S3/BucketBlockPublicAccessDisabled" \
    "Exfiltration:S3/AnomalousBehavior" \
  --region "$REGION"
echo "  Generated 8 sample GuardDuty findings."

echo ""
echo "[4/4] Verifying vulnerable state..."

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
echo "Compliance findings should reappear in Security Hub within 1-3 minutes."
echo "GuardDuty sample findings should appear in Security Hub within 1-5 minutes."
echo ""
echo "Run ./scripts/check-findings.sh to monitor."
