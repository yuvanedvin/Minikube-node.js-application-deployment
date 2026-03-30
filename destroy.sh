#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# destroy.sh — Remove all resources created by deploy.sh
# Usage: ./destroy.sh
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

# ─── Confirm before destroying ───────────────────────────────────────────────
echo ""
echo -e "${RED}⚠️  WARNING: This will delete ALL resources created by deploy.sh${NC}"
echo ""
echo "  This includes:"
echo "  - monitoring-app namespace (app, services, HPA, PDB, network policies)"
echo "  - monitoring namespace (Prometheus, Grafana, Alertmanager)"
echo "  - All ClusterRoles and ClusterRoleBindings for monitoring"
echo "  - All webhook configurations for monitoring"
echo "  - All monitoring services in kube-system"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  log "Destroy cancelled."
  exit 0
fi

echo ""

# ─── Step 1: Delete app namespace resources ───────────────────────────────────
log "Deleting app resources in monitoring-app namespace..."

kubectl delete -f k8s/monitoring/monitoring.yaml \
  --ignore-not-found 2>/dev/null || true
log "  ✓ ServiceMonitor + PrometheusRule + Grafana dashboard"

kubectl delete -f k8s/network/networkpolicy.yaml \
  --ignore-not-found 2>/dev/null || true
log "  ✓ NetworkPolicy"

kubectl delete -f k8s/pdb/pdb.yaml \
  --ignore-not-found 2>/dev/null || true
log "  ✓ PodDisruptionBudget"

kubectl delete -f k8s/hpa/hpa.yaml \
  --ignore-not-found 2>/dev/null || true
log "  ✓ HPA"

kubectl delete -f k8s/base/service.yaml \
  --ignore-not-found 2>/dev/null || true
log "  ✓ Services"

kubectl delete -f k8s/base/deployment.yaml \
  --ignore-not-found 2>/dev/null || true
log "  ✓ Deployment"

kubectl delete -f k8s/rbac/rbac.yaml \
  --ignore-not-found 2>/dev/null || true
log "  ✓ RBAC"

kubectl delete -f k8s/secret/secret.yaml \
  --ignore-not-found 2>/dev/null || true
log "  ✓ Secret"

kubectl delete -f k8s/configmap/configmap.yaml \
  --ignore-not-found 2>/dev/null || true
log "  ✓ ConfigMap"

# Delete GHCR pull secret if it exists
kubectl delete secret ghcr-secret \
  -n monitoring-app --ignore-not-found 2>/dev/null || true
log "  ✓ GHCR pull secret"

# ─── Step 2: Uninstall Helm release ──────────────────────────────────────────
log "Uninstalling Prometheus + Grafana Helm release..."
if helm status monitoring -n monitoring &>/dev/null; then
  helm uninstall monitoring -n monitoring
  log "  ✓ Helm release 'monitoring' uninstalled"
else
  warn "  Helm release 'monitoring' not found — skipping"
fi

# ─── Step 3: Delete namespaces ───────────────────────────────────────────────
log "Deleting namespaces..."

kubectl delete namespace monitoring-app --ignore-not-found
log "  ✓ Namespace monitoring-app deleted"

kubectl delete namespace monitoring --ignore-not-found
log "  ✓ Namespace monitoring deleted"

# ─── Step 4: Clean cluster-scoped resources ──────────────────────────────────
log "Cleaning cluster-scoped resources..."

# ClusterRoles
kubectl delete clusterrole \
  monitoring-grafana-clusterrole \
  monitoring-kube-prometheus-operator \
  monitoring-kube-prometheus-prometheus \
  monitoring-kube-state-metrics \
  --ignore-not-found 2>/dev/null || true
log "  ✓ ClusterRoles deleted"

# ClusterRoleBindings
kubectl delete clusterrolebinding \
  monitoring-grafana-clusterrolebinding \
  monitoring-kube-prometheus-operator \
  monitoring-kube-prometheus-prometheus \
  monitoring-kube-state-metrics \
  --ignore-not-found 2>/dev/null || true
log "  ✓ ClusterRoleBindings deleted"

# ─── Step 5: Clean webhook configurations ────────────────────────────────────
log "Cleaning webhook configurations..."

kubectl delete mutatingwebhookconfiguration \
  monitoring-kube-prometheus-admission \
  --ignore-not-found 2>/dev/null || true

kubectl delete validatingwebhookconfiguration \
  monitoring-kube-prometheus-admission \
  --ignore-not-found 2>/dev/null || true

log "  ✓ Webhook configurations deleted"

# ─── Step 6: Clean leftover services in kube-system ─────────────────────────
log "Cleaning leftover services in kube-system..."

LEFTOVER_SVCS=$(kubectl get svc -n kube-system 2>/dev/null \
  | grep "^monitoring-" | awk '{print $1}' || true)

if [ -n "$LEFTOVER_SVCS" ]; then
  echo "$LEFTOVER_SVCS" | xargs kubectl delete svc -n kube-system
  log "  ✓ kube-system services deleted"
else
  log "  ✓ No leftover services in kube-system"
fi

# ─── Step 7: Final verification ──────────────────────────────────────────────
echo ""
log "✅ Destroy complete! Verifying cleanup..."
echo ""

echo "Remaining monitoring namespaces:"
kubectl get namespace | grep -E "monitoring" || echo "  None ✓"

echo ""
echo "Remaining monitoring ClusterRoles:"
kubectl get clusterrole 2>/dev/null \
  | grep "^monitoring-" || echo "  None ✓"

echo ""
echo "Remaining monitoring ClusterRoleBindings:"
kubectl get clusterrolebinding 2>/dev/null \
  | grep "^monitoring-" || echo "  None ✓"

echo ""
echo "Remaining kube-system monitoring services:"
kubectl get svc -n kube-system 2>/dev/null \
  | grep "^monitoring-" || echo "  None ✓"

echo ""
log "All resources cleaned up successfully!"
log "Run './deploy.sh' to redeploy from scratch."
