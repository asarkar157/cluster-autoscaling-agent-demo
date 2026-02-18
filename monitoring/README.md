# Monitoring (Optional)

These files provide an **optional** Prometheus + Grafana stack for visualizing EKS node metrics. They are **not used** by the main demo — Aiden reads metrics from CloudWatch Container Insights, not Prometheus.

## Files

- **`prometheus-values.yaml`** — Helm values for `kube-prometheus-stack` (Prometheus, Grafana, node-exporter, kube-state-metrics). Configured with low resource limits for demo use.
- **`grafana-dashboard.json`** — A Grafana dashboard showing node CPU and memory utilization panels.

## Installation

If you want a local Grafana UI alongside the demo:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f monitoring/prometheus-values.yaml
```

Grafana will be exposed via a LoadBalancer service. Default credentials: `admin` / `demo-password`.

## Why This Isn't Part of the Demo

The Aiden autoscaling skill uses **CloudWatch Container Insights** (`amazon-cloudwatch-observability` EKS add-on) to detect node overutilization. Prometheus/Grafana is redundant for that purpose. These files exist as a convenience if you want a visual dashboard during development or debugging.
