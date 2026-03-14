# Troubleshooting Guide

---

## Time drift — OTel Collector drops spans / Prometheus "out of order samples"

**Symptom:** Jaeger shows no traces despite traffic being generated. Prometheus UI shows `Error: out of order samples`. Grafana dashboards are empty despite the stack running correctly.

**Root cause:** WSL2, the Minikube VM, and Windows have independent clocks. WSL2 clock drifts after the host sleeps or resumes, causing the OTel Collector to drop spans with future timestamps and Prometheus to reject metrics.

**Fix:** Sync all three clocks in order:

1. **Sync Windows** (Settings → Time & Language → Date & Time → Sync now)

2. **Sync WSL2:**
   ```bash
   sudo date -s "$(curl -sI google.com | grep -i '^date:' | cut -d' ' -f2-)"
   ```

3. **Sync Minikube VM:**
   ```bash
   minikube ssh -p otel-lab "sudo date -s '$(date -u)'"
   ```

4. **Restart the observability stack** to clear stale state:
   ```bash
   kubectl rollout restart deployment/otel-collector-opentelemetry-collector -n observability
   kubectl rollout restart deployment/jaeger -n observability
   kubectl rollout restart statefulset/prometheus-kube-prometheus-stack-prometheus -n observability
   ```

5. **Restart port-forwards** (pods have changed, old tunnels are broken):
   ```bash
   pkill -f "kubectl port-forward" 2>/dev/null || true
   kubectl port-forward svc/jaeger-query -n observability 16686:16686 &
   kubectl port-forward svc/kube-prometheus-stack-prometheus -n observability 9090:9090 &
   kubectl port-forward svc/kube-prometheus-stack-grafana -n observability 3000:80 &
   ```

> **Note:** This sync is needed each time WSL2 resumes from a Windows sleep/hibernate. It is not persistent.

---

## OTel Collector — CrashLoopBackOff on startup

**Symptom:** `kubectl get pods -n observability` shows the Collector in `CrashLoopBackOff`.

**Diagnosis:**
```bash
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector --tail=30
```

**Common causes and fixes:**

- `listen tcp :8888: bind: address already in use` → Port conflict in telemetry config. Ensure `service.telemetry.metrics.level: none` is set in `otel-collector-advanced-values.yaml` and redeploy:
  ```bash
  helm upgrade otel-collector open-telemetry/opentelemetry-collector \
    -n observability \
    -f 02-collector-pipeline/otel-collector-advanced-values.yaml
  ```

- `connection refused` to Jaeger → Jaeger is not yet ready. Wait 30s and restart the Collector:
  ```bash
  kubectl rollout restart deployment/otel-collector-opentelemetry-collector -n observability
  ```

---

## Instrumentation CRD not found

**Symptom:**
```
error: no matches for kind "Instrumentation" in version "opentelemetry.io/v1alpha1"
ensure CRDs are installed first
```

**Root cause:** The OpenTelemetry Operator is not installed. It provides the `Instrumentation` CRD.

**Fix:**
```bash
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
  -n observability \
  --set "manager.collectorImage.repository=otel/opentelemetry-collector-contrib" \
  --set admissionWebhooks.certManager.enabled=false \
  --set admissionWebhooks.autoGenerateCert.enabled=true \
  --wait --timeout 120s

kubectl wait --for condition=established crd/instrumentations.opentelemetry.io --timeout=60s
kubectl apply -f 03-auto-instrumentation/instrumentation.yaml
```

---

## Jaeger — no traces visible

**Symptom:** Jaeger UI at `http://localhost:16686` shows no services or traces.

**Diagnosis:**
```bash
# Check the Collector is receiving spans
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector --tail=50 | grep -i trace

# Check demo pods have the OTel annotation
kubectl get pods -n demo -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations}{"\n"}{end}'
```

**Common fixes:**

- Demo pods missing inject annotation → Verify your deployment has:
  ```yaml
  annotations:
    instrumentation.opentelemetry.io/inject-python: "true"
  ```
- Jaeger pod not ready → `kubectl rollout restart deployment/jaeger -n observability`
- Clock drift → See the **Time drift** section above.

---

## Grafana — empty dashboards

**Symptom:** Grafana loads but all panels show "No data".

**Diagnosis:**
```bash
# Verify Prometheus is scraping the OTel Collector
kubectl port-forward svc/kube-prometheus-stack-prometheus -n observability 9090:9090 &
# Open http://localhost:9090/targets and check otel-collector-metrics
```

**Common fixes:**

- Prometheus not scraping Collector → Check `kube-prometheus-stack-values.yaml` has the correct `additionalScrapeConfigs` target (`otel-collector-opentelemetry-collector.observability.svc.cluster.local:8889`)
- Clock drift → See the **Time drift** section above.
