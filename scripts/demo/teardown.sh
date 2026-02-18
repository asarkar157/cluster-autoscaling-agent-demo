#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"
K8S_DIR="$ROOT_DIR/kubernetes"

echo "============================================"
echo "  Observability Demo - Teardown"
echo "============================================"
echo ""

echo "This will DESTROY all demo resources including:"
echo "  - EKS clusters (observability-demo + payments-api + inventory-svc)"
echo "  - VPC and networking"
echo "  - GuardDuty detector"
echo "  - Security Hub account settings"
echo "  - Vulnerable demo resources (SG, S3, EBS, IAM, EC2)"
echo ""

read -rp "Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "[1/1] Destroying Terraform infrastructure (all EKS clusters, VPC, GuardDuty, Security Hub, vulnerable resources)..."
terraform -chdir="$TERRAFORM_DIR" destroy -auto-approve

echo ""
echo "============================================"
echo "  Teardown Complete"
echo "============================================"
echo "All demo resources have been destroyed."
echo ""
echo "Note: GuardDuty retains finding data for 90 days after disabling."
echo "Security Hub findings may still appear in the console temporarily."
