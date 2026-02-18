#!/usr/bin/env bash
set -euo pipefail

# Generate sample GuardDuty findings for the security remediation demo.
# These findings flow into Security Hub automatically within 1-5 minutes.
# Findings are labeled [SAMPLE] in the GuardDuty console.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"

REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw region 2>/dev/null || echo "us-west-2")
DETECTOR_ID=$(terraform -chdir="$TERRAFORM_DIR" output -raw guardduty_detector_id)

echo "============================================"
echo "  GuardDuty Sample Findings Generator"
echo "============================================"
echo ""
echo "Detector ID: $DETECTOR_ID"
echo "Region:      $REGION"
echo ""

FINDING_TYPES=(
  # EC2 — matches open SSH/RDP security group + public instances
  "Recon:EC2/PortProbeUnprotectedPort"
  "UnauthorizedAccess:EC2/SSHBruteForce"
  "UnauthorizedAccess:EC2/RDPBruteForce"
  "UnauthorizedAccess:EC2/MaliciousIPCaller.Custom"
  # EC2 — matches no IMDSv2 + admin role on public instance
  "UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS"
  "CryptoCurrency:EC2/BitcoinTool.B!DNS"
  # S3 — matches public bucket + unencrypted bucket
  "Policy:S3/BucketBlockPublicAccessDisabled"
  "Exfiltration:S3/AnomalousBehavior"
)

echo "Generating ${#FINDING_TYPES[@]} sample findings..."
echo ""

aws guardduty create-sample-findings \
  --detector-id "$DETECTOR_ID" \
  --finding-types "${FINDING_TYPES[@]}" \
  --region "$REGION"

echo "Sample findings generated successfully."
echo ""
echo "Finding types created:"
for ft in "${FINDING_TYPES[@]}"; do
  echo "  - $ft"
done

echo ""
echo "============================================"
echo "  Next Steps"
echo "============================================"
echo ""
echo "1. Findings appear in GuardDuty console immediately:"
echo "   https://${REGION}.console.aws.amazon.com/guardduty/home?region=${REGION}#/findings"
echo ""
echo "2. Findings flow to Security Hub within 1-5 minutes:"
echo "   https://${REGION}.console.aws.amazon.com/securityhub/home?region=${REGION}#/findings"
echo ""
echo "3. Run ./scripts/diagnostic/check-findings.sh to monitor Security Hub findings."
echo ""
echo "Note: Sample findings are labeled [SAMPLE] in the GuardDuty console."
