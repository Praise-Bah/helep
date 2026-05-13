#!/usr/bin/env bash
# Install kube-prometheus-stack (Prometheus + Grafana + AlertManager) in the monitoring namespace.
# Run after the helep namespace and services are deployed.

set -euo pipefail

NAMESPACE="monitoring"
RELEASE="kube-prometheus-stack"

echo "==> Creating monitoring namespace..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

echo "==> Adding prometheus-community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "==> Installing kube-prometheus-stack..."
helm upgrade --install ${RELEASE} prometheus-community/kube-prometheus-stack \
  --namespace ${NAMESPACE} \
  --values prometheus/prometheus-values.yaml \
  --wait \
  --timeout 10m

echo "==> Importing HELEP dashboard into Grafana..."
kubectl create configmap helep-dashboard \
  --from-file=helep-dashboard.json=grafana/helep-dashboard.json \
  --namespace ${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap helep-dashboard \
  grafana_dashboard=1 \
  --namespace ${NAMESPACE} \
  --overwrite

echo ""
echo "Done! Access Grafana at: http://localhost:32000"
echo "  Username: admin"
echo "  Password: helep-admin"
echo ""
echo "Prometheus: kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring"
