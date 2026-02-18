#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"
K8S_DIR="$ROOT_DIR/kubernetes"

DUMMY_CLUSTERS=("payments-api" "inventory-svc")

echo "============================================"
echo "  Observability Demo - Setup"
echo "============================================"
echo ""

# -------------------------------------------------------------------
# 1. Terraform: provision VPC + EKS clusters + node groups
# -------------------------------------------------------------------
echo "[1/7] Initializing Terraform..."
terraform -chdir="$TERRAFORM_DIR" init

echo ""
echo "[2/7] Applying Terraform configuration..."
terraform -chdir="$TERRAFORM_DIR" apply -auto-approve

echo ""
echo "[3/7] Configuring kubectl for main cluster..."
CLUSTER_NAME=$(terraform -chdir="$TERRAFORM_DIR" output -raw cluster_name)
REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw region)
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

echo ""
echo "[4/7] Installing metrics-server via Helm (main cluster)..."
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
helm repo update
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args[0]="--kubelet-preferred-address-types=InternalIP" \
  --wait --timeout 120s

echo ""
echo "[5/7] Deploying Kubernetes workloads (main cluster)..."
kubectl apply -f "$K8S_DIR/namespace.yaml"
kubectl apply -f "$K8S_DIR/demo-app/"
kubectl apply -f "$K8S_DIR/stress/stress-deployment.yaml"

echo ""
echo "Waiting for main cluster pods to be ready..."
kubectl wait --for=condition=ready pod -l app=demo-app -n demo --timeout=120s
kubectl wait --for=condition=ready pod -l app=stress-ng -n demo --timeout=120s

# -------------------------------------------------------------------
# 6. Configure and deploy workloads on dummy clusters
# -------------------------------------------------------------------
echo ""
echo "[6/7] Setting up dummy baseline clusters..."
for CLUSTER in "${DUMMY_CLUSTERS[@]}"; do
  echo ""
  echo "  -> Configuring kubectl for $CLUSTER..."
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" --alias "$CLUSTER"

  echo "  -> Deploying baseline workload to $CLUSTER..."
  kubectl --context "$CLUSTER" apply -f "$K8S_DIR/dummy-workload/"

  echo "  -> Waiting for baseline-load pod on $CLUSTER..."
  kubectl --context "$CLUSTER" wait --for=condition=ready pod \
    -l app=baseline-load -n workload --timeout=120s
done

# -------------------------------------------------------------------
# 7. Switch context back to the main cluster
# -------------------------------------------------------------------
echo ""
echo "[7/7] Switching kubectl context back to main cluster..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
kubectl config use-context "arn:aws:eks:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}"

echo ""
echo "============================================"
echo "  Setup Complete"
echo "============================================"
echo ""
echo "Main cluster:   $CLUSTER_NAME (t3.medium x2)"
echo "Dummy clusters: ${DUMMY_CLUSTERS[*]} (t3.small x1 each)"
echo ""
echo "Current node status (main cluster):"
kubectl get nodes -o wide
echo ""
echo "Current pod status (main cluster):"
kubectl get pods -n demo -o wide
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/diagnostic/check-utilization.sh to monitor node usage"
echo "  2. Run ./scripts/demo/load-up.sh to overutilize the nodes"
echo "  3. Aiden will detect the overutilization and scale up"
