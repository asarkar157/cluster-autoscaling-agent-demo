#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"
K8S_DIR="$ROOT_DIR/kubernetes"

DUMMY_CLUSTERS=("inventory-svc")

echo "============================================"
echo "  Observability Demo - First-Time Setup"
echo "============================================"
echo ""

# -------------------------------------------------------------------
# 1. Terraform: provision VPC + EKS clusters + node groups
# -------------------------------------------------------------------
echo "[1/9] Initializing Terraform..."
terraform -chdir="$TERRAFORM_DIR" init

echo ""
echo "[2/9] Applying Terraform configuration..."
terraform -chdir="$TERRAFORM_DIR" apply -auto-approve

echo ""
echo "[3/9] Configuring kubectl for main cluster (observability-demo)..."
CLUSTER_NAME=$(terraform -chdir="$TERRAFORM_DIR" output -raw cluster_name)
REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw region)
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

echo ""
echo "[4/9] Installing metrics-server via Helm (main cluster)..."
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
helm repo update
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args[0]="--kubelet-preferred-address-types=InternalIP" \
  --wait --timeout 120s

echo ""
echo "[5/9] Deploying Kubernetes workloads (main cluster)..."
kubectl apply -f "$K8S_DIR/namespace.yaml"
kubectl apply -f "$K8S_DIR/demo-app/"
kubectl apply -f "$K8S_DIR/stress/stress-deployment.yaml"

echo ""
echo "Waiting for main cluster pods to be ready..."
kubectl wait --for=condition=ready pod -l app=demo-app -n demo --timeout=120s
kubectl wait --for=condition=ready pod -l app=stress-ng -n demo --timeout=120s

# -------------------------------------------------------------------
# 6. Configure and deploy workloads on payments-api (scale-down demo)
# -------------------------------------------------------------------
echo ""
echo "[6/9] Setting up payments-api cluster (scale-down demo)..."
aws eks update-kubeconfig --region "$REGION" --name "payments-api" --alias "payments-api"

echo "  -> Installing metrics-server on payments-api..."
helm upgrade --install metrics-server metrics-server/metrics-server \
  --kube-context "payments-api" \
  --namespace kube-system \
  --set args[0]="--kubelet-preferred-address-types=InternalIP" \
  --wait --timeout 120s

echo "  -> Deploying payments workloads..."
kubectl --context "payments-api" apply -f "$K8S_DIR/payments-workload/"

echo "  -> Waiting for payments pods to be ready..."
kubectl --context "payments-api" wait --for=condition=ready pod \
  -l app=payments-app -n payments --timeout=120s
kubectl --context "payments-api" wait --for=condition=ready pod \
  -l app=payments-worker -n payments --timeout=120s

# -------------------------------------------------------------------
# 7. Configure and deploy workloads on dummy cluster (inventory-svc)
# -------------------------------------------------------------------
echo ""
echo "[7/9] Setting up dummy baseline cluster (inventory-svc)..."
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
# 8. Switch context back to the main cluster
# -------------------------------------------------------------------
echo ""
echo "[8/9] Switching kubectl context back to main cluster..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
kubectl config use-context "arn:aws:eks:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}"

# -------------------------------------------------------------------
# 9. Summary
# -------------------------------------------------------------------
echo ""
echo "[9/9] Verifying cluster status..."
echo ""
echo "============================================"
echo "  Setup Complete"
echo "============================================"
echo ""
echo "Scale-up cluster:  $CLUSTER_NAME (small-pool: 2x t3.medium)"
echo "Scale-down cluster: payments-api (small-pool: 2x t3.medium + large-pool: 2x t3.xlarge)"
echo "Dummy cluster:     inventory-svc (1x t3.small)"
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/demo/initialize-demo.sh to stage both demo scenarios"
echo "  2. Aiden will detect overutilization on $CLUSTER_NAME and scale up"
echo "  3. Aiden will detect underutilization on payments-api and remove the large-pool"
