#!/usr/bin/env bash
set -euo pipefail

INTERVAL=${1:-5}

echo "============================================"
echo "  Observability Demo - Utilization Monitor"
echo "  Refreshing every ${INTERVAL}s (Ctrl+C to stop)"
echo "============================================"
echo ""

while true; do
  clear
  echo "============================================"
  echo "  Node & Pod Utilization  $(date '+%H:%M:%S')"
  echo "============================================"

  echo ""
  echo "--- Nodes ---"
  kubectl top nodes 2>/dev/null || echo "(waiting for metrics-server...)"

  echo ""
  echo "--- Node Details ---"
  kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.conditions[-1].type,\
INSTANCE-TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
POOL:.metadata.labels.pool,\
AGE:.metadata.creationTimestamp

  echo ""
  echo "--- Pods (demo namespace) ---"
  kubectl top pods -n demo 2>/dev/null || echo "(waiting for metrics-server...)"

  echo ""
  echo "--- Pod Status ---"
  kubectl get pods -n demo -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
NODE:.spec.nodeName,\
CPU-REQ:.spec.containers[0].resources.requests.cpu,\
MEM-REQ:.spec.containers[0].resources.requests.memory

  sleep "$INTERVAL"
done
