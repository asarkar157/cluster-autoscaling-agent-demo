#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$ROOT_DIR/terraform"
K8S_DIR="$ROOT_DIR/kubernetes"

echo "============================================"
echo "  Observability Demo - Teardown"
echo "============================================"
echo ""

DUMMY_CLUSTERS=("payments-api" "inventory-svc")

echo "This will DESTROY all demo resources including:"
echo "  - Kubernetes workloads (demo + workload namespaces)"
echo "  - EKS clusters (main + dummy: ${DUMMY_CLUSTERS[*]})"
echo "  - VPC and networking"
echo "  - GuardDuty detector"
echo "  - Security Hub account settings"
echo "  - Vulnerable demo resources (SG, S3, EBS, IAM)"
echo ""

read -rp "Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw region 2>/dev/null || echo "us-west-2")

echo ""
echo "[1/4] Removing Kubernetes workloads (main cluster)..."
kubectl delete -f "$K8S_DIR/stress/stress-deployment.yaml" --ignore-not-found=true 2>/dev/null || true
kubectl delete -f "$K8S_DIR/demo-app/" --ignore-not-found=true 2>/dev/null || true
kubectl delete -f "$K8S_DIR/namespace.yaml" --ignore-not-found=true 2>/dev/null || true

echo ""
echo "[2/4] Removing metrics-server..."
helm uninstall metrics-server --namespace kube-system 2>/dev/null || true

echo ""
echo "[3/4] Removing workloads from dummy clusters..."
for CLUSTER in "${DUMMY_CLUSTERS[@]}"; do
  echo "  -> Cleaning up $CLUSTER..."
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" --alias "$CLUSTER" 2>/dev/null || true
  kubectl --context "$CLUSTER" delete -f "$K8S_DIR/dummy-workload/" --ignore-not-found=true 2>/dev/null || true
done

echo ""
echo "[4/4] Destroying Terraform infrastructure (all EKS clusters, VPC, GuardDuty, Security Hub, vulnerable resources)..."
terraform -chdir="$TERRAFORM_DIR" destroy -auto-approve

echo ""
echo "============================================"
echo "  Teardown Complete"
echo "============================================"
echo "All demo resources have been destroyed."
echo ""
echo "Note: GuardDuty retains finding data for 90 days after disabling."
echo "Security Hub findings may still appear in the console temporarily."
