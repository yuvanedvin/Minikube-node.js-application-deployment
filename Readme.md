# 🚀 Production-Ready Node.js on Kubernetes (Minikube)

A complete production-grade Kubernetes setup for a Node.js application with
Prometheus metrics, Grafana dashboards, alerting, autoscaling, security hardening,
and a full CI/CD pipeline using GitHub Actions.

---

## 📁 Project Structure

```
.
├── app/
│   ├── app.js                    # Node.js Express app
│   ├── package.json              # Dependencies and scripts
│   └── __tests__/
│       └── app.test.js           # Jest unit tests
├── docker/
│   ├── Dockerfile                # Multi-stage production Dockerfile
│   └── .dockerignore             # Files excluded from Docker build
├── k8s/
│   ├── namespace/
│   │   └── namespace.yaml        # Kubernetes namespace
│   ├── configmap/
│   │   └── configmap.yaml        # App configuration (non-sensitive)
│   ├── secret/
│   │   └── secret.yaml           # Sensitive config (API keys, passwords)
│   ├── rbac/
│   │   └── rbac.yaml             # ServiceAccount, Role, RoleBinding
│   ├── base/
│   │   ├── deployment.yaml       # App deployment with probes and security
│   │   └── service.yaml          # ClusterIP + NodePort services
│   ├── hpa/
│   │   └── hpa.yaml              # HorizontalPodAutoscaler
│   ├── pdb/
│   │   └── pdb.yaml              # PodDisruptionBudget
│   ├── network/
│   │   └── networkpolicy.yaml    # Network access control
│   ├── ingress/
│   │   └── ingress.yaml          # Ingress with TLS (cert-manager)
│   └── monitoring/
│       └── monitoring.yaml       # ServiceMonitor + PrometheusRule + Grafana dashboard
├── .github/
│   └── workflows/
│       └── ci-cd.yaml            # GitHub Actions CI/CD pipeline
├── .gitattributes                # Line ending rules (LF for all files)
├── deploy.sh                     # One-shot Minikube deployment script
├── destroy.sh                    # Cleanup script — removes all resources
└── README.md                     # This file
```

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                          MINIKUBE CLUSTER                           │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                   monitoring-app namespace                    │  │
│  │                                                              │  │
│  │   User Request                                               │  │
│  │       │                                                      │  │
│  │       ▼                                                      │  │
│  │   NodePort :30080                                            │  │
│  │       │                                                      │  │
│  │       ▼                                                      │  │
│  │   ClusterIP Service  ──────────────────────────────────┐    │  │
│  │       │                                                │    │  │
│  │       ├──► Pod 1 (app.js :3000)                        │    │  │
│  │       └──► Pod 2 (app.js :3000)                        │    │  │
│  │               │                                        │    │  │
│  │               ├── GET /          (main route)          │    │  │
│  │               ├── GET /healthz   (liveness probe)      │    │  │
│  │               ├── GET /readyz    (readiness probe)      │    │  │
│  │               └── GET /metrics   (prometheus scrape)   │    │  │
│  │                                                        │    │  │
│  │   HPA ──► watches CPU/Memory ──► scales pods           │    │  │
│  │   PDB ──► ensures min 2 pods always running            │    │  │
│  │   NetworkPolicy ──► controls traffic in/out            │    │  │
│  │   RBAC ──► least privilege service account             │    │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                     monitoring namespace                      │  │
│  │                                                              │  │
│  │   Prometheus ──► ServiceMonitor ──► scrapes /metrics         │  │
│  │       │                                                      │  │
│  │       ├──► evaluates PrometheusRules (5 alert rules)         │  │
│  │       └──► feeds data to Grafana                            │  │
│  │                                                              │  │
│  │   Grafana ──► dashboards (Request Rate, Latency, Errors)     │  │
│  │   Alertmanager ──► receives alerts from Prometheus           │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## ⚡ Quick Start

### Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| Minikube | Local Kubernetes cluster | https://minikube.sigs.k8s.io |
| kubectl | Kubernetes CLI | https://kubernetes.io/docs/tasks/tools |
| Helm | Kubernetes package manager | https://helm.sh/docs/intro/install |
| Docker | Container runtime | https://docs.docker.com/get-docker |

### Deploy everything in one command

```bash
# 1. Start Minikube
minikube start --cpus=4 --memory=6144

# 2. Create .env file
cat > .env << 'EOF'
GITHUB_USER=yuvanedvin
GITHUB_PAT=your_github_pat_here
GITHUB_EMAIL=your@email.com
GRAFANA_PASSWORD=yuvan@123
EOF

# 3. Add .env to gitignore
echo ".env" >> .gitignore

# 4. Run deploy script
chmod +x deploy.sh
source .env && ./deploy.sh
```

### Tear everything down

```bash
chmod +x destroy.sh
./destroy.sh
```

---

## 📖 End-to-End Project Explanation

### 1. The Application (`app/app.js`)

A Node.js Express app that serves HTTP requests and exposes Prometheus metrics.

**Key features:**
- **Structured JSON logging** — every request logged as JSON for easy parsing
- **3 Prometheus metrics:**
  - `http_requests_total` — Counter, tracks every request by method/route/status
  - `http_request_duration_seconds` — Histogram, measures request latency (p50/p95/p99)
  - `http_active_requests` — Gauge, tracks in-flight requests in real time
- **Health endpoints:**
  - `GET /healthz` — liveness probe, answers "is the process alive?"
  - `GET /readyz` — readiness probe, answers "is the app ready for traffic?"
  - `GET /metrics` — Prometheus scrape endpoint
- **Graceful shutdown** — listens for `SIGTERM`, drains in-flight requests before exiting

**Request flow:**
```
Request arrives
     │
     ▼
Middleware: start latency timer, increment active_requests gauge
     │
     ▼
Route handler: process request
     │
     ▼
Response sent
     │
     ▼
Middleware: record http_requests_total, observe latency histogram, decrement gauge
     │
     ▼
Structured log written to stdout (JSON)
```

---

### 2. Docker (`docker/Dockerfile`)

Multi-stage build that produces a minimal, secure production image.

```
Stage 1 (deps):          Stage 2 (runner):
────────────────         ─────────────────────────────
node:18-alpine     →     node:18-alpine
npm ci --omit=dev        copy node_modules from stage 1
                         copy app source
                         create non-root user (UID 1000)
                         switch to non-root user
                         HEALTHCHECK built in
                         dumb-init as PID 1
```

**Why multi-stage?**
- Stage 1 has build tools and dev dependencies
- Stage 2 only has what's needed to run — smaller, more secure image
- Final image size: ~150MB vs ~1GB for `node:18`

**Why non-root user?**
- If the container is compromised, attacker has limited OS privileges
- Industry standard security practice

**Why dumb-init?**
- Node.js is not designed to be PID 1
- `dumb-init` properly forwards `SIGTERM` to Node.js for graceful shutdown

---

### 3. Kubernetes Manifests

#### `namespace.yaml` — Isolation
```yaml
kind: Namespace
metadata:
  name: monitoring-app
```
Creates a dedicated namespace. All app resources live here, isolated from
other workloads on the cluster. Prevents accidental cross-app interference.

---

#### `configmap.yaml` — Non-sensitive Configuration
```yaml
kind: ConfigMap
data:
  PORT: "3000"
  APP_ENV: "production"
  LOG_LEVEL: "info"
```
Externalizes app configuration. Change config without rebuilding the image.
Mounted into the pod as environment variables via `envFrom`.

---

#### `secret.yaml` — Sensitive Configuration
```yaml
kind: Secret
type: Opaque
data:
  API_KEY: <base64>
  DB_PASSWORD: <base64>
```
Stores sensitive values separately from ConfigMap. Values are base64 encoded
(not encrypted by default — use Sealed Secrets or Vault in real production).
Injected into pod as individual env vars via `secretKeyRef`.

---

#### `rbac.yaml` — Least Privilege Access
Three resources work together:

```
ServiceAccount (monitoring-app-sa)
        │
        │ bound by RoleBinding
        ▼
Role (monitoring-app-role)
  └── can only: GET, LIST ConfigMaps
        │
        │ assigned to
        ▼
Pod runs as monitoring-app-sa
  └── has ONLY the permissions defined in Role
```

This means even if the app is compromised, it cannot access Secrets,
other namespaces, or modify any Kubernetes resources.

---

#### `deployment.yaml` — The Core Workload

The most important manifest. Key sections explained:

**Replicas + RollingUpdate:**
```yaml
replicas: 2
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1   # at most 1 pod down during update
    maxSurge: 1         # at most 1 extra pod during update
```
Zero-downtime deployments. Kubernetes spins up new pods before killing old ones.

**Three probes:**
```yaml
startupProbe:    # gives app time to start (runs first, once)
  httpGet: /healthz
  failureThreshold: 10   # 10 × 5s = 50s to start

livenessProbe:   # is app alive? (runs forever, restart if fails)
  httpGet: /healthz
  periodSeconds: 15

readinessProbe:  # is app ready for traffic? (runs forever, remove from LB if fails)
  httpGet: /readyz
  periodSeconds: 10
```

**securityContext:**
```yaml
securityContext:
  runAsNonRoot: true              # never run as root
  runAsUser: 1000                 # specific UID
  readOnlyRootFilesystem: true    # filesystem is immutable
  allowPrivilegeEscalation: false # cannot gain more privileges
  capabilities:
    drop: ["ALL"]                 # no Linux capabilities
```

**Resource limits:**
```yaml
resources:
  requests:               # guaranteed minimum
    cpu: "100m"           # 100 millicores = 0.1 CPU core
    memory: "128Mi"
  limits:                 # hard maximum
    cpu: "250m"
    memory: "256Mi"
```
Without limits, one pod can consume all node resources and starve others.

---

#### `service.yaml` — Network Access

Two services created:

```
ClusterIP (monitoring-app)
  └── internal access only
  └── used by: ServiceMonitor (Prometheus scraping)
  └── port: 80 → 3000

NodePort (monitoring-app-nodeport)
  └── external access via Minikube IP
  └── port: 30080 → 3000
  └── access: http://<minikube-ip>:30080
```

---

#### `hpa.yaml` — Autoscaling

```yaml
minReplicas: 2
maxReplicas: 10
metrics:
  - cpu > 60%    → scale up
  - memory > 70% → scale up
behavior:
  scaleUp:   add 2 pods per 60s (fast response to load)
  scaleDown: remove 1 pod per 60s (slow to avoid flapping)
```

Requires `metrics-server` addon: `minikube addons enable metrics-server`

---

#### `pdb.yaml` — High Availability During Maintenance

```yaml
minAvailable: 2
```

When a node is drained (maintenance, upgrade), Kubernetes will only evict pods
if at least 2 remain running. Prevents all pods being evicted simultaneously.

---

#### `networkpolicy.yaml` — Traffic Control

Four policies applied:

```
default-deny-all          → block ALL traffic by default
allow-ingress-controller  → allow traffic from nginx ingress
allow-prometheus-scrape   → allow Prometheus to reach /metrics
allow-dns-egress          → allow DNS lookups (required for everything)
```

Zero-trust networking — deny everything, explicitly allow only what's needed.

---

#### `monitoring.yaml` — Observability Stack

Three resources:

**ServiceMonitor** — tells Prometheus to scrape this app:
```
ServiceMonitor
  └── selector: app=monitoring-app  →  finds the ClusterIP Service
  └── endpoints: port=http, path=/metrics, interval=15s
  └── label: release=monitoring  →  Prometheus Operator picks this up
```

**PrometheusRule** — 5 alerting rules:
```
AppPodDown         → pod unreachable > 1min      → CRITICAL
HighErrorRate      → 5xx rate > 5%               → WARNING
HighLatency        → p95 latency > 1s            → WARNING
HighMemoryUsage    → memory > 85% of limit       → WARNING
DeploymentUnavailable → 0 available replicas     → CRITICAL
```

**Grafana Dashboard ConfigMap** — auto-loaded by Grafana sidecar:
```
ConfigMap (label: grafana_dashboard=1)
  └── contains dashboard JSON
  └── Grafana sidecar detects this label
  └── automatically imports dashboard
```

---

### 4. CI/CD Pipeline (`.github/workflows/ci-cd.yaml`)

5 jobs run on every push to `master`:

```
git push
    │
    ▼
Job 1 — Run Tests
    ├── npm ci (install deps)
    ├── npm test (jest --coverage)
    └── npm run lint (eslint)
    │
    ▼
Job 2 — Lint K8s Manifests
    └── kubeval validates all YAML files
    │
    ▼ (only on master branch)
Job 3 — Build & Push Docker Image
    ├── docker/setup-buildx-action (enables GHA cache)
    ├── login to ghcr.io
    ├── build image (multi-stage)
    └── push to ghcr.io/yuvanedvin/monitoring-app:latest + :<sha>
    │
    ▼
Job 4 — Scan Image (Trivy)
    ├── pull image from GHCR
    ├── scan for CVEs (CRITICAL, HIGH)
    ├── generate trivy-results.sarif
    └── upload to GitHub Security tab
    │
    ▼
Job 5 — Deploy (skipped for Minikube)
    └── requires cloud cluster with public API endpoint
```

**Image tagging strategy:**
```
ghcr.io/yuvanedvin/monitoring-app:latest      ← always points to latest master
ghcr.io/yuvanedvin/monitoring-app:a03bfb8     ← immutable, git SHA tag
```

---

### 5. deploy.sh — Deployment Automation

Automates the entire Minikube deployment in one script:

```
Step 1  → Check prerequisites (minikube, kubectl, helm installed)
Step 2  → Verify Minikube is running
Step 3  → Enable addons (ingress, metrics-server)
Step 4  → Decide image source (GHCR or local build)
Step 5  → Apply Namespace
Step 6  → Create GHCR pull secret (if private image)
Step 7  → Apply ConfigMap, Secret, RBAC
Step 8  → Apply Deployment (with correct image injected via sed)
Step 9  → Patch imagePullSecrets into Deployment (if private)
Step 10 → Apply Service, HPA, PDB, NetworkPolicy
Step 11 → Wait for rollout (180s timeout, shows events on failure)
Step 12 → Install/upgrade Prometheus + Grafana via Helm
Step 13 → Apply ServiceMonitor + PrometheusRule + Grafana dashboard
Step 14 → Print access URLs and pod status
```

**Two modes:**
```bash
USE_GHCR=true   → pulls image from ghcr.io (uses CI/CD built image)
USE_GHCR=false  → builds image locally inside Minikube docker daemon
```

---

### 6. destroy.sh — Cleanup

Removes everything created by deploy.sh in reverse order:

```
Step 1  → Delete app resources (Deployment, Service, HPA, PDB, NetworkPolicy)
Step 2  → Delete monitoring resources (ServiceMonitor, PrometheusRule)
Step 3  → Uninstall Helm release (Prometheus + Grafana)
Step 4  → Delete namespaces (monitoring-app, monitoring)
Step 5  → Clean cluster-scoped resources (ClusterRole, ClusterRoleBinding)
Step 6  → Clean webhook configurations
Step 7  → Clean kube-system services
```

---

## 🛠️ Useful Commands

```bash
# ── App ──────────────────────────────────────────────────────────────
# Get app URL
minikube ip   # then access http://<ip>:30080

# Watch pods
kubectl get pods -n monitoring-app --watch

# View structured logs
kubectl logs -n monitoring-app -l app=monitoring-app -f

# Describe pod (events, probe status)
kubectl describe pod -n monitoring-app -l app=monitoring-app

# Force rolling restart
kubectl rollout restart deployment/monitoring-app -n monitoring-app

# Check resource usage
kubectl top pods -n monitoring-app

# ── HPA ──────────────────────────────────────────────────────────────
kubectl get hpa -n monitoring-app --watch

# ── Monitoring ───────────────────────────────────────────────────────
# Port-forward Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring

# Port-forward Prometheus
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9091:9090 -n monitoring

# Check ServiceMonitor is picked up
kubectl get servicemonitor -n monitoring-app

# Check alert rules
kubectl get prometheusrule -n monitoring-app

# ── Debugging ────────────────────────────────────────────────────────
# Get all events in namespace
kubectl get events -n monitoring-app --sort-by='.lastTimestamp'

# Get all resources
kubectl get all -n monitoring-app

# Check network policies
kubectl get networkpolicy -n monitoring-app
```

---

## 📊 Prometheus Queries

```promql
# Request rate per second
rate(http_requests_total[5m])

# p95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Error rate (5xx)
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# Active requests right now
http_active_requests

# CPU usage
rate(process_cpu_seconds_total{job="monitoring-app"}[5m])

# Memory usage
process_resident_memory_bytes{job="monitoring-app"}
```

---

## 🔐 Security Checklist

- [x] Non-root container user (UID 1000)
- [x] Read-only root filesystem
- [x] All Linux capabilities dropped
- [x] No privilege escalation
- [x] Dedicated ServiceAccount
- [x] RBAC with least privilege (read ConfigMaps only)
- [x] NetworkPolicy — default deny all
- [x] Secrets separate from ConfigMaps
- [x] Resource limits on all containers
- [x] Image vulnerability scanning (Trivy in CI/CD)
- [x] Multi-stage Docker build (no build tools in prod image)
- [x] Non-root base image (alpine)
- [ ] Sealed Secrets / Vault (recommended for real production)
- [ ] Image signing with Cosign

---

## 🚨 Alerting Rules

| Alert | Expression | Threshold | Severity |
|-------|-----------|-----------|----------|
| `AppPodDown` | `up{job="monitoring-app"} == 0` | > 1 min | Critical |
| `HighErrorRate` | 5xx / total requests | > 5% for 2 min | Warning |
| `HighLatency` | p95 request duration | > 1s for 5 min | Warning |
| `HighMemoryUsage` | memory / memory limit | > 85% for 5 min | Warning |
| `DeploymentUnavailable` | available replicas | == 0 for 1 min | Critical |

---

## 🌍 Moving to Production (Cloud)

To move from Minikube to a real cloud cluster:

| Step | Action |
|------|--------|
| 1 | Provision cluster (EKS/GKE/AKS) |
| 2 | Update `imagePullPolicy: Always` |
| 3 | Remove `topologySpreadConstraints` single-node workaround |
| 4 | Add `KUBECONFIG` secret to GitHub Actions |
| 5 | Enable Deploy job in `ci-cd.yaml` |
| 6 | Replace NodePort with LoadBalancer or Ingress |
| 7 | Add real domain + TLS via cert-manager |
| 8 | Replace plain Secrets with Sealed Secrets or Vault |
| 9 | Configure Alertmanager → Slack/PagerDuty notifications |
