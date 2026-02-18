#!/usr/bin/env bash
set -euo pipefail

REPLICAS=${1:-1}

echo "============================================"
echo "  Observability Demo - Load Down"
echo "============================================"
echo ""
echo "Scaling stress-ng deployment down to $REPLICAS replica(s)..."
echo ""

kubectl scale deployment stress-ng --replicas="$REPLICAS" -n demo

echo "Waiting 30 seconds for pods to terminate and metrics to settle..."
sleep 30

echo ""
echo "--- Node Utilization ---"
kubectl top nodes 2>/dev/null || echo "(metrics-server may need a moment to collect data)"

echo ""
echo "--- Pod Status ---"
kubectl get pods -n demo -o wide

echo ""
echo "============================================"
echo "  Utilization is now low."
echo "  Aiden will detect this on its next scan"
echo "  and reattach a smaller node pool, then"
echo "  deactivate the larger one."
echo "============================================"
