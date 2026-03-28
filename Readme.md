# 🚀 Production-Ready Node.js on Kubernetes (Minikube)

A complete production-grade setup for a Node.js app on Kubernetes with monitoring, security, autoscaling, and CI/CD.

---

## 📁 Project Structure

```
.
├── app/
│   ├── app.js              # Node.js app (structured logging, metrics, graceful shutdown)
│   └── package.json
├── docker/
│   ├── Dockerfile          # Multi-stage, non-root, alpine
│   └── .dockerignore
├── k8s/
│   ├── namespace/          # Namespace isolation
│   ├── configmap/          # App configuration
│   ├── secret/             # Sensitive config (template)
│   ├── rbac/               # ServiceAccount + RBAC
│   ├── base/               # Deployment + Service
│   ├── hpa/                # HorizontalPodAutoscaler
│   ├── pdb/                # PodDisruptionBudget
│   ├── network/            # NetworkPolicy
│   ├── ingress/            # Ingress + cert-manager (TLS)
│   └── monitoring/         # ServiceMonitor + PrometheusRule + Grafana dashboard
├── .github/
│   └── workflows/
│       └── ci-cd.yaml      # GitHub Actions CI/CD pipeline
└── deploy.sh               # One-shot Minikube deploy script
```

---

## ⚡ Quick Start (Minikube)

### Prerequisites
- Minikube installed and running
- kubectl configured
- Helm 3 installed

```bash
# Start Minikube
minikube start --cpus=4 --memory=6g

# Deploy everything
chmod +x deploy.sh
./deploy.sh
```

---

## 📋 Phase-by-Phase Guide

### Phase 1 — Foundation

**1. Build the Docker image inside Minikube:**
```bash
eval $(minikube docker-env)
docker build -t monitoring-app:1.0 -f docker/Dockerfile .
```

**2. Apply base manifests:**
```bash
kubectl apply -f k8s/namespace/namespace.yaml
kubectl apply -f k8s/configmap/configmap.yaml
kubectl apply -f k8s/secret/secret.yaml
kubectl apply -f k8s/rbac/rbac.yaml
kubectl apply -f k8s/base/deployment.yaml
kubectl apply -f k8s/base/service.yaml
```

**3. Verify:**
```bash
kubectl get all -n monitoring-app
kubectl rollout status deployment/monitoring-app -n monitoring-app
```

**4. Access the app:**
```bash
minikube service monitoring-app-nodeport -n monitoring-app --url
```

---

### Phase 2 — Security

Security is already baked into the manifests. Verify it's working:

```bash
# Check pod is running as non-root
kubectl exec -n monitoring-app \
  $(kubectl get pod -n monitoring-app -l app=monitoring-app -o jsonpath='{.items[0].metadata.name}') \
  -- id

# Apply NetworkPolicies
kubectl apply -f k8s/network/networkpolicy.yaml

# Verify network policies
kubectl get networkpolicies -n monitoring-app
```

---

### Phase 3 — Traffic & Autoscaling

**Enable metrics-server for HPA:**
```bash
minikube addons enable metrics-server

# Apply HPA and PDB
kubectl apply -f k8s/hpa/hpa.yaml
kubectl apply -f k8s/pdb/pdb.yaml

# Watch HPA in action
kubectl get hpa -n monitoring-app --watch
```

**Enable Ingress (Minikube local access):**
```bash
minikube addons enable ingress

# Get Minikube IP
minikube ip

# Add to /etc/hosts (replace with actual minikube ip)
echo "$(minikube ip) monitoring-app.local" | sudo tee -a /etc/hosts

# Apply Ingress (edit host to monitoring-app.local for local testing)
kubectl apply -f k8s/ingress/ingress.yaml
```

---

### Phase 4 — Observability

**Install Prometheus + Grafana via Helm:**
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin123

# Apply ServiceMonitor and alerting rules
kubectl apply -f k8s/monitoring/monitoring.yaml
```

**Access dashboards:**
```bash
# Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# Open http://localhost:3000  (admin / admin123)

# Prometheus
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring
# Open http://localhost:9090
```

**Useful Prometheus queries:**
```promql
# Request rate
rate(http_requests_total[5m])

# p95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Error rate
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])
```

---

### Phase 5 — CI/CD (GitHub Actions)

**Setup:**
1. Push code to GitHub
2. Add secrets to GitHub repo settings:
   - `KUBECONFIG` — base64 encoded kubeconfig

```bash
# Encode your kubeconfig
cat ~/.kube/config | base64
```

3. On push to `main`, the pipeline will:
   - Run tests
   - Lint K8s manifests
   - Build & push Docker image to GHCR
   - Scan image with Trivy
   - Deploy to cluster

---

## 🛠️ Useful Commands

```bash
# Get all resources in namespace
kubectl get all -n monitoring-app

# Check pod logs (structured JSON)
kubectl logs -n monitoring-app -l app=monitoring-app -f

# Describe a pod (events, status)
kubectl describe pod -n monitoring-app -l app=monitoring-app

# Check HPA status
kubectl get hpa -n monitoring-app

# Check alerts
kubectl get prometheusrule -n monitoring-app

# Port-forward app directly
kubectl port-forward svc/monitoring-app 8080:80 -n monitoring-app

# Force rolling restart
kubectl rollout restart deployment/monitoring-app -n monitoring-app

# Check resource usage
kubectl top pods -n monitoring-app
kubectl top nodes
```

---

## 📊 Metrics Available

| Metric | Type | Description |
|---|---|---|
| `http_requests_total` | Counter | Total requests by method/route/status |
| `http_request_duration_seconds` | Histogram | Request latency (p50/p95/p99) |
| `http_active_requests` | Gauge | Currently in-flight requests |
| `process_cpu_seconds_total` | Counter | CPU usage |
| `process_resident_memory_bytes` | Gauge | Memory usage |
| `nodejs_eventloop_lag_seconds` | Gauge | Node.js event loop lag |

---

## 🔐 Security Checklist

- [x] Non-root container user (UID 1000)
- [x] Read-only root filesystem
- [x] All capabilities dropped
- [x] No privilege escalation
- [x] Dedicated ServiceAccount (no automount)
- [x] RBAC with least privilege
- [x] NetworkPolicy (default deny)
- [x] Secrets separate from ConfigMaps
- [ ] Sealed Secrets / Vault (for real prod)
- [ ] Image signing (Cosign)

---

## 🚨 Alerting Rules

| Alert | Condition | Severity |
|---|---|---|
| `AppPodDown` | Pod unreachable > 1 min | Critical |
| `HighErrorRate` | 5xx rate > 5% | Warning |
| `HighLatency` | p95 > 1 second | Warning |
| `HighMemoryUsage` | Memory > 85% of limit | Warning |
| `DeploymentUnavailable` | 0 available replicas | Critical |
