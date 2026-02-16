#!/usr/bin/env bash
set -euo pipefail

REPLICAS=${1:-8}

echo "============================================"
echo "  Observability Demo - Load Up"
echo "============================================"
echo ""
echo "Scaling stress-ng deployment to $REPLICAS replicas..."
echo "This will saturate the small-pool nodes (2x t3.medium)."
echo ""

kubectl scale deployment stress-ng --replicas="$REPLICAS" -n demo

echo "Waiting 30 seconds for pods to schedule (or go Pending)..."
sleep 30

echo ""
echo "--- Node Utilization ---"
kubectl top nodes 2>/dev/null || echo "(metrics-server may need a moment to collect data)"

echo ""
echo "--- Pod Status ---"
kubectl get pods -n demo -o wide

PENDING=$(kubectl get pods -n demo --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$PENDING" -gt 0 ]; then
  echo ""
  echo "WARNING: $PENDING pod(s) are in Pending state -- not enough resources!"
fi

echo ""
echo "============================================"
echo "  Nodes are now overutilized."
echo "  Aiden will detect this on its next scan"
echo "  and create a larger node group."
echo "============================================"
