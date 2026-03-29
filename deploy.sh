#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy.sh — Full Minikube production-like deployment script
# Usage: source .env && ./deploy.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Config — reads from env vars ────────────────────────────────────────────
GITHUB_USER="${GITHUB_USER:-yuvanedvin}"
GITHUB_PAT="${GITHUB_PAT:-}"
GITHUB_EMAIL="${GITHUB_EMAIL:-}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-yuvan@123}"
USE_GHCR="${USE_GHCR:-true}"
IMAGE="ghcr.io/${GITHUB_USER}/monitoring-app:latest"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ─── Validate required config ─────────────────────────────────────────────────
if [ "$USE_GHCR" = true ] && [ -n "$GITHUB_PAT" ]; then
  [ -z "$GITHUB_EMAIL" ] && error "GITHUB_EMAIL is not set in .env"
fi

# ─── Step 1: Check prerequisites ─────────────────────────────────────────────
log "Checking prerequisites..."
command -v minikube &>/dev/null || error "minikube not found. Please install minikube."
command -v kubectl  &>/dev/null || error "kubectl not found. Please install kubectl."
command -v helm     &>/dev/null || error "helm not found. Please install helm."

# ─── Step 2: Check Minikube is running ───────────────────────────────────────
log "Checking Minikube status..."
minikube status || error "Minikube is not running. Run: minikube start --cpus=4 --memory=6144"

# ─── Step 3: Enable required addons ──────────────────────────────────────────
log "Enabling Minikube addons..."
minikube addons enable ingress      2>/dev/null || warn "ingress addon already enabled"
minikube addons enable metrics-server 2>/dev/null || warn "metrics-server already enabled"

# ─── Step 4: Build or use GHCR image ─────────────────────────────────────────
if [ "$USE_GHCR" = true ]; then
  log "Using image from GHCR: $IMAGE"
else
  log "Building Docker image locally inside Minikube..."
  eval $(minikube docker-env)
  docker build -t monitoring-app:1.0 -f docker/Dockerfile .
  IMAGE="monitoring-app:1.0"
  log "Image built successfully: $IMAGE"
fi

# ─── Step 5: Apply Namespace ──────────────────────────────────────────────────
log "Applying Kubernetes manifests..."
kubectl apply -f k8s/namespace/namespace.yaml
log "  ✓ Namespace"

# ─── Step 6: Create GHCR pull secret if PAT is provided ──────────────────────
if [ "$USE_GHCR" = true ] && [ -n "$GITHUB_PAT" ]; then
  log "Creating GHCR image pull secret..."
  kubectl delete secret ghcr-secret -n monitoring-app --ignore-not-found

  kubectl create secret docker-registry ghcr-secret \
    --docker-server=ghcr.io \
    --docker-username="${GITHUB_USER}" \
    --docker-password="${GITHUB_PAT}" \
    --docker-email="${GITHUB_EMAIL}" \
    --namespace=monitoring-app

  log "  ✓ GHCR pull secret created"
elif [ "$USE_GHCR" = true ] && [ -z "$GITHUB_PAT" ]; then
  warn "No GITHUB_PAT set — assuming image is public on GHCR"
fi

# ─── Step 7: Apply ConfigMap, Secret, RBAC ───────────────────────────────────
kubectl apply -f k8s/configmap/configmap.yaml
log "  ✓ ConfigMap"

kubectl apply -f k8s/secret/secret.yaml
log "  ✓ Secret"

kubectl apply -f k8s/rbac/rbac.yaml
log "  ✓ RBAC"

# ─── Step 8: Apply Deployment with correct image ─────────────────────────────
sed "s|image: .*monitoring-app.*|image: ${IMAGE}|g" k8s/base/deployment.yaml \
  | kubectl apply -f -
log "  ✓ Deployment (image: $IMAGE)"

# ─── Step 9: Patch imagePullSecrets if using private GHCR ────────────────────
if [ "$USE_GHCR" = true ] && [ -n "$GITHUB_PAT" ]; then
  kubectl patch deployment monitoring-app \
    -n monitoring-app \
    --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/imagePullSecrets","value":[{"name":"ghcr-secret"}]}]'
  log "  ✓ imagePullSecret patched"
fi

# ─── Step 10: Apply Service, HPA, PDB, NetworkPolicy ─────────────────────────
kubectl apply -f k8s/base/service.yaml
log "  ✓ Service"

kubectl apply -f k8s/hpa/hpa.yaml
log "  ✓ HPA"

kubectl apply -f k8s/pdb/pdb.yaml
log "  ✓ PodDisruptionBudget"

kubectl apply -f k8s/network/networkpolicy.yaml
log "  ✓ NetworkPolicy"

# ─── Step 11: Wait for deployment rollout ────────────────────────────────────
log "Waiting for deployment to roll out..."
if ! kubectl rollout status deployment/monitoring-app \
    -n monitoring-app --timeout=180s; then

  warn "Rollout timed out. Checking pod status..."
  echo ""
  kubectl get pods -n monitoring-app
  echo ""
  kubectl get events -n monitoring-app \
    --sort-by='.lastTimestamp' | tail -15
  error "Deployment failed. Check the pod events above."
fi
log "  ✓ Deployment rolled out successfully"

# ─── Step 12: Install Prometheus + Grafana via Helm ──────────────────────────
log "Setting up Prometheus + Grafana..."

# Check if already installed
if helm status monitoring -n monitoring &>/dev/null; then
  warn "Helm release 'monitoring' already exists — upgrading..."
  helm upgrade monitoring \
    prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set grafana.adminPassword="${GRAFANA_PASSWORD}" \
    --wait --timeout=5m
else
  helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts 2>/dev/null || true
  helm repo update

  helm install monitoring \
    prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --set grafana.adminPassword="${GRAFANA_PASSWORD}" \
    --wait --timeout=5m
fi

kubectl apply -f k8s/monitoring/monitoring.yaml
log "  ✓ ServiceMonitor + PrometheusRule + Grafana dashboard"

# ─── Step 13: Final status ────────────────────────────────────────────────────
echo ""
log "✅ Deployment complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  📦 App URL:"
echo "     $(minikube service monitoring-app-nodeport -n monitoring-app --url 2>/dev/null || echo 'run: minikube service monitoring-app-nodeport -n monitoring-app --url')"
echo ""
echo "  📊 Grafana:"
echo "     URL:      http://localhost:3000"
echo "     Command:  kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
echo "     Username: admin"
echo "     Password: ${GRAFANA_PASSWORD}"
echo ""
echo "  🔥 Prometheus:"
echo "     URL:      http://localhost:9091"
echo "     Command:  kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9091:9090 -n monitoring"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log "Pod status:"
kubectl get pods -n monitoring-app
echo ""
log "All resources:"
kubectl get all -n monitoring-app
