#!/bin/bash
# =============================================================================
# Cleanup — Remove everything
# =============================================================================

set -euo pipefail

echo "🧹 Cleaning up OpenTelemetry Learning Lab..."

echo "Removing demo apps..."
kubectl delete namespace demo --ignore-not-found

echo "Removing observability stack..."
helm uninstall grafana -n observability 2>/dev/null || true
helm uninstall prometheus -n observability 2>/dev/null || true
helm uninstall otel-collector -n observability 2>/dev/null || true
kubectl delete namespace observability --ignore-not-found

echo "Removing Kyverno..."
helm uninstall kyverno -n kyverno 2>/dev/null || true
kubectl delete namespace kyverno --ignore-not-found

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "To delete the cluster entirely:"
echo "  minikube delete --profile otel-lab"
