#!/usr/bin/env bash
set -euo pipefail

# Show active Security Hub findings for demo resources.
# Can be run in a loop with: watch -n 30 ./scripts/check-findings.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$ROOT_DIR/terraform"

REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw region 2>/dev/null || echo "us-west-2")

echo "============================================"
echo "  Security Hub Findings  $(date '+%H:%M:%S')"
echo "============================================"
echo ""

echo "--- FAILED Compliance Findings (demo resources) ---"
echo ""

aws securityhub get-findings --region "$REGION" \
  --filters '{
    "RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}],
    "ComplianceStatus":[{"Value":"FAILED","Comparison":"EQUALS"}],
    "ResourceTags":[{"Key":"Purpose","Value":"security-demo","Comparison":"EQUALS"}]
  }' \
  --query 'Findings[].{Title:Title,Severity:Severity.Label,Resource:Resources[0].Id,Status:Workflow.Status}' \
  --output table 2>/dev/null || echo "(No compliance findings yet)"

echo ""
echo "--- GuardDuty Threat Findings ---"
echo ""

aws securityhub get-findings --region "$REGION" \
  --filters '{
    "RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}],
    "ProductName":[{"Value":"GuardDuty","Comparison":"EQUALS"}],
    "WorkflowStatus":[{"Value":"NEW","Comparison":"EQUALS"}]
  }' \
  --query 'Findings[].{Type:Types[0],Severity:Severity.Label,Resource:Resources[0].Id,Status:Workflow.Status}' \
  --output table 2>/dev/null || echo "(No GuardDuty findings yet)"

echo ""
echo "--- Summary ---"

COMPLIANCE_COUNT=$(aws securityhub get-findings --region "$REGION" \
  --filters '{
    "RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}],
    "ComplianceStatus":[{"Value":"FAILED","Comparison":"EQUALS"}],
    "ResourceTags":[{"Key":"Purpose","Value":"security-demo","Comparison":"EQUALS"}]
  }' \
  --query 'length(Findings)' \
  --output text 2>/dev/null || echo "0")

GUARDDUTY_COUNT=$(aws securityhub get-findings --region "$REGION" \
  --filters '{
    "RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}],
    "ProductName":[{"Value":"GuardDuty","Comparison":"EQUALS"}],
    "WorkflowStatus":[{"Value":"NEW","Comparison":"EQUALS"}]
  }' \
  --query 'length(Findings)' \
  --output text 2>/dev/null || echo "0")

echo "Compliance findings:  $COMPLIANCE_COUNT"
echo "GuardDuty findings:   $GUARDDUTY_COUNT"
echo ""
echo "Security Hub console:"
echo "  https://${REGION}.console.aws.amazon.com/securityhub/home?region=${REGION}#/findings"
echo "GuardDuty console:"
echo "  https://${REGION}.console.aws.amazon.com/guardduty/home?region=${REGION}#/findings"
