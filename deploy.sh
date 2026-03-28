#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy.sh — Full Minikube production-like deployment script
# Usage: ./deploy.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ─── Step 1: Check Minikube is running ───────────────────────────────────────
log "Checking Minikube status..."
minikube status || error "Minikube is not running. Run: minikube start"

# ─── Step 2: Enable required addons ──────────────────────────────────────────
log "Enabling Minikube addons..."
minikube addons enable ingress
minikube addons enable metrics-server
minikube addons enable ingress-dns

# ─── Step 3: Point Docker to Minikube's daemon ────────────────────────────────
log "Switching to Minikube Docker daemon..."
eval $(minikube docker-env)

# ─── Step 4: Build Docker image ──────────────────────────────────────────────
log "Building Docker image..."
docker build -t monitoring-app:1.0 -f docker/Dockerfile .
log "Image built successfully."

# ─── Step 5: Apply Kubernetes manifests (in order) ───────────────────────────
log "Applying Kubernetes manifests..."

kubectl apply -f k8s/namespace/namespace.yaml
log "  ✓ Namespace"

kubectl apply -f k8s/configmap/configmap.yaml
log "  ✓ ConfigMap"

kubectl apply -f k8s/secret/secret.yaml
log "  ✓ Secret"

kubectl apply -f k8s/rbac/rbac.yaml
log "  ✓ RBAC"

kubectl apply -f k8s/base/deployment.yaml
log "  ✓ Deployment"

kubectl apply -f k8s/base/service.yaml
log "  ✓ Service"

kubectl apply -f k8s/hpa/hpa.yaml
log "  ✓ HPA"

kubectl apply -f k8s/pdb/pdb.yaml
log "  ✓ PodDisruptionBudget"

kubectl apply -f k8s/network/networkpolicy.yaml
log "  ✓ NetworkPolicy"

# ─── Step 6: Wait for deployment rollout ─────────────────────────────────────
log "Waiting for deployment to roll out..."
kubectl rollout status deployment/monitoring-app -n monitoring-app --timeout=120s

# ─── Step 7: Install Prometheus stack via Helm ───────────────────────────────
log "Installing Prometheus + Grafana via Helm..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin123 \
  --wait

kubectl apply -f k8s/monitoring/monitoring.yaml
log "  ✓ ServiceMonitor + PrometheusRule"

# ─── Step 8: Print access URLs ───────────────────────────────────────────────
log "Deployment complete! Access URLs:"
echo ""
echo "  App:       $(minikube service monitoring-app-nodeport -n monitoring-app --url 2>/dev/null)"
echo "  Grafana:   $(minikube service monitoring-grafana -n monitoring --url 2>/dev/null)"
echo "  Prometheus:$(minikube service monitoring-kube-prometheus-prometheus -n monitoring --url 2>/dev/null)"
echo ""
log "Grafana credentials: admin / admin123"
echo ""
log "Pod status:"
kubectl get pods -n monitoring-app
