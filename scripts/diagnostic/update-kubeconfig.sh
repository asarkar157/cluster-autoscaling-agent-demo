#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"

echo "Updating kubeconfig for all demo EKS clusters..."
echo ""

REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw region 2>/dev/null || echo "us-west-2")
CLUSTER_NAME=$(terraform -chdir="$TERRAFORM_DIR" output -raw cluster_name 2>/dev/null || echo "observability-demo")

echo "Region: $REGION"
echo ""

echo "  -> $CLUSTER_NAME (main cluster)..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

echo "  -> payments-api..."
aws eks update-kubeconfig --region "$REGION" --name "payments-api" --alias "payments-api"

echo "  -> inventory-svc..."
aws eks update-kubeconfig --region "$REGION" --name "inventory-svc" --alias "inventory-svc"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
kubectl config use-context "arn:aws:eks:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}"

echo ""
echo "Done. Current context set to $CLUSTER_NAME."
echo ""
echo "Available contexts:"
kubectl config get-contexts -o name
