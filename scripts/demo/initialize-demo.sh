#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"

K8S_DIR="$ROOT_DIR/kubernetes"

echo "============================================"
echo "  Observability Demo - Initialize"
echo "============================================"
echo ""
echo "This will:"
echo "  - Restore all intentionally misconfigured resources to vulnerable state"
echo "  - Archive old findings & regenerate GuardDuty samples"
echo "  - Stage EKS autoscaling demos (high load on observability-demo,"
echo "    low load on payments-api with oversized large-pool)"
echo ""

# Re-apply Terraform to restore intentionally vulnerable resources
# AND recreate the large-pool node group on payments-api if Aiden removed it.
echo "[1/6] Restoring infrastructure via Terraform..."
terraform -chdir="$TERRAFORM_DIR" apply -auto-approve

REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw region)
DETECTOR_ID=$(terraform -chdir="$TERRAFORM_DIR" output -raw guardduty_detector_id)

echo ""
echo "[2/6] Archiving old GuardDuty findings in Security Hub..."
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
echo "[3/6] Generating fresh GuardDuty sample findings..."
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
echo "[4/6] Verifying vulnerable state..."

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

# -------------------------------------------------------------------
# 5. Stage EKS scale-up demo: inject high load on observability-demo
# -------------------------------------------------------------------
echo ""
echo "[5/6] Staging EKS scale-up demo (observability-demo — high load)..."
CLUSTER_NAME=$(terraform -chdir="$TERRAFORM_DIR" output -raw cluster_name)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
kubectl config use-context "arn:aws:eks:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}"

CURRENT_REPLICAS=$(kubectl get deployment stress-ng -n demo -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
if [ "$CURRENT_REPLICAS" -lt 8 ]; then
  echo "  Scaling stress-ng to 8 replicas on $CLUSTER_NAME..."
  kubectl scale deployment stress-ng -n demo --replicas=8
  echo "  Waiting for stress-ng pods to be ready..."
  kubectl wait --for=condition=ready pod -l app=stress-ng -n demo --timeout=180s 2>/dev/null || true
  echo "  [OK] High load injected on $CLUSTER_NAME"
else
  echo "  [OK] stress-ng already at $CURRENT_REPLICAS replicas — skipping"
fi

# -------------------------------------------------------------------
# 6. Stage EKS scale-down demo: ensure low load on payments-api
# -------------------------------------------------------------------
echo ""
echo "[6/6] Staging EKS scale-down demo (payments-api — low load)..."
kubectl config use-context "payments-api" 2>/dev/null || \
  aws eks update-kubeconfig --region "$REGION" --name "payments-api" --alias "payments-api"
kubectl config use-context "payments-api"

kubectl --context "payments-api" apply -f "$K8S_DIR/payments-workload/" 2>/dev/null || true
WORKER_REPLICAS=$(kubectl --context "payments-api" get deployment payments-worker -n payments \
  -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
if [ "$WORKER_REPLICAS" -gt 1 ]; then
  echo "  Scaling payments-worker back to 1 replica..."
  kubectl --context "payments-api" scale deployment payments-worker -n payments --replicas=1
fi
echo "  [OK] payments-api has low workload with oversized large-pool"

kubectl config use-context "arn:aws:eks:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}"

echo ""
if [ "$PASS" = true ]; then
  echo "============================================"
  echo "  Initialization Complete"
  echo "============================================"
else
  echo "============================================"
  echo "  Initialization Complete (some warnings)"
  echo "============================================"
fi
echo ""
echo "EKS Autoscaling:"
echo "  - observability-demo: HIGH load (8x stress-ng) — Aiden should ADD a node group"
echo "  - payments-api: LOW load + oversized large-pool — Aiden should REMOVE the large-pool"
echo ""
echo "Security Remediation:"
echo "  - Config rule re-evaluation triggered automatically"
echo "  - Compliance findings should reappear in Security Hub within 1-3 minutes"
echo "  - GuardDuty sample findings should appear within 1-5 minutes"
echo ""
echo "Run ./scripts/diagnostic/check-findings.sh to monitor security findings."
echo "Run ./scripts/diagnostic/check-utilization.sh to monitor node CPU usage."
