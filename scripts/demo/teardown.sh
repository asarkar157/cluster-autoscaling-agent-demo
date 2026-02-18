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

DUMMY_CLUSTERS=("inventory-svc")

echo "This will DESTROY all demo resources including:"
echo "  - Kubernetes workloads (demo + payments + workload namespaces)"
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

REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw region 2>/dev/null || echo "us-west-2")

echo ""
echo "[1/5] Removing Kubernetes workloads (main cluster — observability-demo)..."
kubectl delete -f "$K8S_DIR/stress/stress-deployment.yaml" --ignore-not-found=true 2>/dev/null || true
kubectl delete -f "$K8S_DIR/demo-app/" --ignore-not-found=true 2>/dev/null || true
kubectl delete -f "$K8S_DIR/namespace.yaml" --ignore-not-found=true 2>/dev/null || true

echo ""
echo "[2/5] Removing metrics-server (main cluster)..."
helm uninstall metrics-server --namespace kube-system 2>/dev/null || true

echo ""
echo "[3/5] Removing workloads from payments-api cluster..."
aws eks update-kubeconfig --region "$REGION" --name "payments-api" --alias "payments-api" 2>/dev/null || true
kubectl --context "payments-api" delete -f "$K8S_DIR/payments-workload/" --ignore-not-found=true 2>/dev/null || true
helm uninstall metrics-server --kube-context "payments-api" --namespace kube-system 2>/dev/null || true

echo ""
echo "[4/5] Removing workloads from dummy clusters..."
for CLUSTER in "${DUMMY_CLUSTERS[@]}"; do
  echo "  -> Cleaning up $CLUSTER..."
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" --alias "$CLUSTER" 2>/dev/null || true
  kubectl --context "$CLUSTER" delete -f "$K8S_DIR/dummy-workload/" --ignore-not-found=true 2>/dev/null || true
done

echo ""
echo "[5/5] Destroying Terraform infrastructure (all EKS clusters, VPC, GuardDuty, Security Hub, vulnerable resources)..."
terraform -chdir="$TERRAFORM_DIR" destroy -auto-approve

echo ""
echo "============================================"
echo "  Teardown Complete"
echo "============================================"
echo "All demo resources have been destroyed."
echo ""
echo "Note: GuardDuty retains finding data for 90 days after disabling."
echo "Security Hub findings may still appear in the console temporarily."
