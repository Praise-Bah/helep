#!/usr/bin/env bash
# Install Strimzi Operator and deploy Kafka cluster in the helep namespace.
# Run this AFTER: kubectl apply -f ../k8s/namespace.yaml

set -euo pipefail

STRIMZI_VERSION="0.40.0"
NAMESPACE="helep"

echo "==> Installing Strimzi Operator ${STRIMZI_VERSION} into namespace ${NAMESPACE}..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "https://strimzi.io/install/latest?namespace=${NAMESPACE}" -n ${NAMESPACE}

echo "==> Waiting for Strimzi operator to be ready..."
kubectl rollout status deployment/strimzi-cluster-operator -n ${NAMESPACE} --timeout=120s

echo "==> Deploying Kafka cluster..."
kubectl apply -f kafka-cluster.yaml -n ${NAMESPACE}

echo "==> Waiting for Kafka cluster to be ready (this may take 2-3 minutes)..."
kubectl wait kafka/helep-kafka --for=condition=Ready --timeout=300s -n ${NAMESPACE}

echo "==> Creating Kafka topics..."
kubectl apply -f kafka-topics.yaml -n ${NAMESPACE}

echo "==> Kafka bootstrap address:"
kubectl get kafka helep-kafka -n ${NAMESPACE} \
  -o jsonpath='{.status.listeners[?(@.name=="plain")].bootstrapServers}{"\n"}'

echo "Done! Kafka cluster is ready."
