#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# send-security-alert.sh
#
# Reads real resource IDs from Terraform outputs and POSTs a synthesized
# security alert payload to Aiden's webhook endpoint. Aiden receives the
# findings with real resource IDs and can execute actual remediations.
#
# Usage:
#   ./scripts/send-security-alert.sh
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$ROOT_DIR/terraform"

WEBHOOK_URL="https://aiden.stackgen.com/api/v1/tasks/6414e304-36d5-4fe7-a661-f1473ed21158/webhook"

echo "============================================"
echo "  Security Alert — Webhook Sender"
echo "============================================"
echo ""

echo "[1/3] Reading resource IDs from Terraform outputs..."

REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw region 2>/dev/null || echo "us-west-2")
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
SG_ID=$(terraform -chdir="$TERRAFORM_DIR" output -raw vulnerable_sg_id)
BUCKET_PUBLIC=$(terraform -chdir="$TERRAFORM_DIR" output -raw vulnerable_bucket)
BUCKET_NOENCRYPT=$(terraform -chdir="$TERRAFORM_DIR" output -raw vulnerable_bucket_noencrypt)
EBS_ID=$(terraform -chdir="$TERRAFORM_DIR" output -raw vulnerable_ebs_id)
IAM_ROLE=$(terraform -chdir="$TERRAFORM_DIR" output -raw vulnerable_iam_role)
INSTANCE_1=$(terraform -chdir="$TERRAFORM_DIR" output -raw vulnerable_instance_1_id)
INSTANCE_2=$(terraform -chdir="$TERRAFORM_DIR" output -raw vulnerable_instance_2_id)
INSTANCE_2_IP=$(terraform -chdir="$TERRAFORM_DIR" output -raw vulnerable_instance_2_public_ip)

echo "  Region:              $REGION"
echo "  Account:             $ACCOUNT_ID"
echo "  Security Group:      $SG_ID"
echo "  S3 Bucket (public):  $BUCKET_PUBLIC"
echo "  S3 Bucket (no enc):  $BUCKET_NOENCRYPT"
echo "  EBS Volume:          $EBS_ID"
echo "  IAM Role:            $IAM_ROLE"
echo "  EC2 Instance 1:      $INSTANCE_1"
echo "  EC2 Instance 2:      $INSTANCE_2 ($INSTANCE_2_IP)"
echo ""

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "[2/3] Constructing alert payload..."

PAYLOAD=$(cat <<EOF
{
  "source": "observability-demo-security-alert",
  "timestamp": "$TIMESTAMP",
  "account": "$ACCOUNT_ID",
  "region": "$REGION",
  "summary": "Security scan detected 8 vulnerabilities across EC2, S3, EBS, and IAM resources in account $ACCOUNT_ID (us-west-2). Immediate remediation required.",
  "findings": [
    {
      "id": "finding-001",
      "severity": "HIGH",
      "type": "EC2.18",
      "title": "Security group allows unrestricted SSH access",
      "description": "Security group $SG_ID has an inbound rule allowing SSH (port 22) from 0.0.0.0/0. This exposes instances to brute-force attacks from the internet.",
      "resource_type": "AWS::EC2::SecurityGroup",
      "resource_id": "$SG_ID",
      "remediation": "Revoke the 0.0.0.0/0 SSH ingress rule. If SSH is needed, restrict to the VPC CIDR (10.0.0.0/16)."
    },
    {
      "id": "finding-002",
      "severity": "CRITICAL",
      "type": "EC2.19",
      "title": "Security group allows unrestricted RDP access",
      "description": "Security group $SG_ID has an inbound rule allowing RDP (port 3389) from 0.0.0.0/0. This is a critical vulnerability exposing remote desktop access to the internet.",
      "resource_type": "AWS::EC2::SecurityGroup",
      "resource_id": "$SG_ID",
      "remediation": "Revoke the 0.0.0.0/0 RDP ingress rule immediately."
    },
    {
      "id": "finding-003",
      "severity": "HIGH",
      "type": "EC2.8",
      "title": "EC2 instance does not enforce IMDSv2",
      "description": "EC2 instance $INSTANCE_1 (demo-vulnerable-ssh-instance) has metadata service v1 enabled (http_tokens=optional). This allows SSRF attacks to steal instance credentials. The instance is also attached to security group $SG_ID with SSH open to the internet.",
      "resource_type": "AWS::EC2::Instance",
      "resource_id": "$INSTANCE_1",
      "remediation": "Enforce IMDSv2 by setting http_tokens to 'required' via modify-instance-metadata-options."
    },
    {
      "id": "finding-004",
      "severity": "HIGH",
      "type": "EC2.8",
      "title": "Public EC2 instance with admin role does not enforce IMDSv2",
      "description": "EC2 instance $INSTANCE_2 (demo-vulnerable-public-instance) at public IP $INSTANCE_2_IP has metadata service v1 enabled and is attached to IAM role $IAM_ROLE with AdministratorAccess. An SSRF attack could gain full AWS account access.",
      "resource_type": "AWS::EC2::Instance",
      "resource_id": "$INSTANCE_2",
      "remediation": "Enforce IMDSv2 by setting http_tokens to 'required' via modify-instance-metadata-options."
    },
    {
      "id": "finding-005",
      "severity": "HIGH",
      "type": "S3.1",
      "title": "S3 bucket has Block Public Access disabled",
      "description": "S3 bucket $BUCKET_PUBLIC has all four Block Public Access settings disabled. Objects in this bucket could be made publicly accessible.",
      "resource_type": "AWS::S3::Bucket",
      "resource_id": "$BUCKET_PUBLIC",
      "remediation": "Enable all four Block Public Access settings (BlockPublicAcls, IgnorePublicAcls, BlockPublicPolicy, RestrictPublicBuckets)."
    },
    {
      "id": "finding-006",
      "severity": "MEDIUM",
      "type": "S3.4",
      "title": "S3 bucket does not have default encryption enabled",
      "description": "S3 bucket $BUCKET_NOENCRYPT does not have server-side encryption configured. Data stored in this bucket is not encrypted at rest.",
      "resource_type": "AWS::S3::Bucket",
      "resource_id": "$BUCKET_NOENCRYPT",
      "remediation": "Enable default server-side encryption with SSE-S3 (AES-256)."
    },
    {
      "id": "finding-007",
      "severity": "MEDIUM",
      "type": "EC2.3",
      "title": "EBS volume is not encrypted at rest",
      "description": "EBS volume $EBS_ID is not encrypted. Data on this volume is stored in plaintext.",
      "resource_type": "AWS::EC2::Volume",
      "resource_id": "$EBS_ID",
      "remediation": "Create an encrypted snapshot, create a new encrypted volume from the snapshot, and delete the original unencrypted volume."
    },
    {
      "id": "finding-008",
      "severity": "HIGH",
      "type": "IAM.1",
      "title": "IAM role has full administrative privileges",
      "description": "IAM role $IAM_ROLE has the AdministratorAccess managed policy attached. This role is assumed by EC2 instances, granting them full control over the entire AWS account.",
      "resource_type": "AWS::IAM::Role",
      "resource_id": "$IAM_ROLE",
      "remediation": "Detach AdministratorAccess and attach a least-privilege policy such as AmazonEC2ReadOnlyAccess."
    }
  ]
}
EOF
)

echo "  Payload constructed with 8 findings."
echo ""

echo "[3/3] Sending alert to Aiden webhook..."
echo "  URL: $WEBHOOK_URL"
echo ""

HTTP_CODE=$(curl -s -o /tmp/webhook-response.txt -w "%{http_code}" \
  -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

echo "  HTTP Response Code: $HTTP_CODE"

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "  Alert sent successfully."
else
  echo "  WARNING: Unexpected response code. Response body:"
  cat /tmp/webhook-response.txt 2>/dev/null || true
  echo ""
fi

echo ""
echo "============================================"
echo "  Alert Summary"
echo "============================================"
echo ""
echo "  Findings sent: 8"
echo "  CRITICAL:  1 (RDP open to internet)"
echo "  HIGH:      5 (SSH open, IMDSv2 x2, S3 public, IAM admin)"
echo "  MEDIUM:    2 (S3 no encryption, EBS unencrypted)"
echo ""
echo "  Aiden should now process these findings and"
echo "  execute remediations against the real resources."
echo ""
