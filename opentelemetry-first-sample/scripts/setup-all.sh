#!/bin/bash
# =============================================================================
# OpenTelemetry Learning Lab — Full Stack Setup
# =============================================================================
# Deploys: OTel Collector + Jaeger + Prometheus + Grafana + Demo Apps
# Prerequisites: kind or minikube cluster running, helm, kubectl
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔭 OpenTelemetry Learning Lab — Setup Starting..."
echo "=================================================="

# --- Add all Helm repos and update once ---
echo ""
echo "📦 Adding Helm repositories..."
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

# --- Step 1: Create namespaces ---
echo ""
echo "📁 Step 1/6: Creating namespaces..."
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -

# --- Step 2: Deploy Jaeger ---
echo ""
echo "🔍 Step 2/6: Deploying Jaeger (trace backend)..."
kubectl apply -f "$REPO_DIR/01-quick-start/jaeger-all-in-one.yaml"

# --- Step 3: Deploy OTel Collector ---
echo ""
echo "📡 Step 3/6: Deploying OpenTelemetry Collector..."
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  -n observability \
  -f "$REPO_DIR/02-collector-pipeline/otel-collector-advanced-values.yaml" \
  --wait --timeout 120s

# --- Step 4: Deploy Prometheus + Grafana (kube-prometheus-stack) ---
echo ""
echo "📊 Step 4/6: Deploying Prometheus + Grafana (kube-prometheus-stack)..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n observability \
  -f "$REPO_DIR/02-collector-pipeline/kube-prometheus-stack-values.yaml" \
  --wait --timeout 300s

# --- Step 5 placeholder (merged into step 4) ---
echo ""
echo "📈 Step 5/6: Grafana included in kube-prometheus-stack ✓"

# --- Step 6: Deploy Demo Apps ---
echo ""
echo "🚀 Step 6/6: Deploying demo microservices..."

# Install OpenTelemetry Operator (required for Instrumentation CRD)
echo "  Installing OpenTelemetry Operator..."
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
  -n observability \
  --set "manager.collectorImage.repository=otel/opentelemetry-collector-contrib" \
  --set admissionWebhooks.certManager.enabled=false \
  --set admissionWebhooks.autoGenerateCert.enabled=true \
  --wait --timeout 120s

# Wait for Instrumentation CRD to be available
echo "  Waiting for Instrumentation CRD..."
kubectl wait --for condition=established crd/instrumentations.opentelemetry.io --timeout=60s

# Apply the Instrumentation resource (tells the Operator how to inject the SDK)
echo "  Applying Instrumentation resource..."
kubectl apply -f "$REPO_DIR/03-auto-instrumentation/instrumentation.yaml"

# --- Wait for everything ---
echo ""
echo "⏳ Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod -l app=jaeger -n observability --timeout=120s 2>/dev/null || true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=opentelemetry-collector -n observability --timeout=120s 2>/dev/null || true

# --- Summary ---
echo ""
echo "=================================================="
echo "✅ OpenTelemetry Learning Lab is READY!"
echo "=================================================="
echo ""
echo "🔍 Access the dashboards:"
echo "   Jaeger:      kubectl port-forward svc/jaeger-query -n observability 16686:16686"
echo "   Prometheus:  kubectl port-forward svc/kube-prometheus-stack-prometheus -n observability 9090:9090"
echo "   Grafana:     kubectl port-forward svc/kube-prometheus-stack-grafana -n observability 3000:80 (admin/admin)"
echo ""
echo "📚 Next steps — follow the README modules in order:"
echo "   Step 5: kubectl apply -f 03-auto-instrumentation/instrumentation.yaml"
echo "   Step 6: kubectl apply -f 04-distributed-tracing-demo/order-service.yaml"
echo "           kubectl apply -f 04-distributed-tracing-demo/payment-service.yaml"
echo "           kubectl apply -f 04-distributed-tracing-demo/inventory-service.yaml"
echo ""
echo "📚 Start learning: Follow the modules in order (01 → 06)"
echo ""
