# HELEP — Help Emergency Location Platform

Real-time emergency response system: 5 FastAPI microservices orchestrated on Kubernetes with Apache Kafka (Strimzi), Prometheus/Grafana monitoring, and a GitHub Actions CI/CD pipeline.

---

## Repository Structure

```
helep/
├── services/
│   ├── user-service/         (port 8001) — identity, JWT, credibility
│   ├── sos-service/          (port 8002) — SOS trigger, cancel
│   ├── dispatch-service/     (port 8003) — responder matching (Strategy pattern)
│   ├── notification-service/ (port 8004) — SMS/push simulation
│   └── analytics-service/    (port 8005) — police stats, zone heatmaps
├── k8s/                      — raw Kubernetes manifests
│   ├── namespace.yaml, configmap.yaml, secret.yaml, ingress.yaml
│   └── {service}/            — deployment, service, hpa, pvc, networkpolicy
├── helm/helep-chart/         — Helm umbrella chart + 5 sub-charts
├── strimzi/                  — Kafka cluster CR + 7 KafkaTopic CRDs
├── monitoring/               — kube-prometheus-stack values + Grafana dashboard
├── .github/workflows/        — GitHub Actions CI/CD pipeline
├── design-process-template.md ← L4 Design Process Document (→ design.pdf)
├── patterns-template.md       ← L3 Patterns Document (→ patterns.pdf)
├── DEMO-SCRIPT.md             ← Demo video script
└── docker-compose.dev.yml     ← dev-only local smoke test
```

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Docker Desktop | ≥ 4.28 | https://www.docker.com/products/docker-desktop |
| Kubernetes | enabled in Docker Desktop | Settings → Kubernetes → Enable |
| kubectl | bundled with Docker Desktop | `kubectl version` |
| Helm | ≥ 3.14 | https://helm.sh/docs/intro/install/ |

Verify everything works:
```bash
kubectl cluster-info
kubectl config use-context docker-desktop
helm version
```

---

## Quick Local Smoke Test (dev only — NOT graded)

```bash
docker compose -f docker-compose.dev.yml up --build

# In another shell:
curl -X POST localhost:8001/signup -H 'content-type: application/json' \
     -d '{"phone":"+237600000001","password":"hunter22","role":"citizen"}'
TOKEN=<token from above>

curl -X POST localhost:8002/sos -H "authorization: Bearer $TOKEN" \
     -H 'content-type: application/json' \
     -d '{"lat":4.0500,"lon":9.7700,"mode":"online"}'

docker compose -f docker-compose.dev.yml logs -f notification-service
curl localhost:8005/stats/events
```

---

## Production Deployment on Kubernetes

### Step 1 — Build & Push Docker Images

```bash
# Build all 5 images (replace <your-dockerhub-user>)
REGISTRY=<your-dockerhub-user>
for svc in user-service sos-service dispatch-service notification-service analytics-service; do
  docker build -t $REGISTRY/helep-$svc:1.0.0 services/$svc/
  docker push $REGISTRY/helep-$svc:1.0.0
done
```

### Step 2 — Create Namespace & Base Resources

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
```

### Step 3 — Install Strimzi & Kafka Cluster

```bash
cd strimzi
bash strimzi-install.sh
cd ..
```

This installs the Strimzi Operator, deploys a 3-broker Kafka cluster, and creates all 7 KafkaTopic CRDs.

### Step 4 — Install NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

### Step 5 — Deploy All Services via Helm

```bash
helm dependency update helm/helep-chart/
helm install helep helm/helep-chart/ \
  --namespace helep \
  --set global.jwtSecret="change-me-strong-secret" \
  --set "user-service.image.repository=<your-dockerhub-user>/helep-user-service" \
  --set "sos-service.image.repository=<your-dockerhub-user>/helep-sos-service" \
  --set "dispatch-service.image.repository=<your-dockerhub-user>/helep-dispatch-service" \
  --set "notification-service.image.repository=<your-dockerhub-user>/helep-notification-service" \
  --set "analytics-service.image.repository=<your-dockerhub-user>/helep-analytics-service" \
  --wait --timeout 10m
```

Verify all pods are running:
```bash
kubectl get pods -n helep
kubectl get hpa -n helep
```

### Step 6 — Test via Ingress

```bash
curl http://localhost/api/users/healthz
curl http://localhost/api/sos/healthz
curl http://localhost/api/analytics/stats/events
```

### Step 7 — Monitoring

```bash
cd monitoring && bash install-monitoring.sh
# Access Grafana at http://localhost:32000
# Username: admin  Password: helep-admin
```

---

## Switching Matching Strategy

```bash
helm upgrade helep helm/helep-chart/ --namespace helep \
  --reuse-values --set global.matcher=round_robin
# Options: nearest | credibility | round_robin
```

---

## CI/CD (GitHub Actions)

Set the following repository secrets in GitHub:
| Secret | Value |
|--------|-------|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `KUBECONFIG` | Base64-encoded kubeconfig (`base64 ~/.kube/config`) |
| `JWT_SECRET` | Production JWT secret |

Pipeline runs on every push to `main`:
1. **Lint & test** all 5 services (ruff + pytest)
2. **Build & push** Docker images to Docker Hub
3. **Lint** Helm chart
4. **Deploy** via `helm upgrade --install`

---

## Submission

See demo script: [`DEMO-SCRIPT.md`](./DEMO-SCRIPT.md)

Submit via: **https://forms.gle/9QCvLTMV3CSZpxPc8**

### Submission Checklist
- [x] 5 services with production `Dockerfile`s
- [x] Raw K8s manifests (`k8s/`)
- [x] Helm umbrella chart + 5 sub-charts (`helm/helep-chart/`)
- [x] Strimzi Kafka cluster CR + 7 KafkaTopic CRDs (`strimzi/`)
- [x] Prometheus + Grafana monitoring stack (`monitoring/`)
- [x] GitHub Actions CI/CD pipeline (`.github/workflows/ci-cd.yaml`)
- [x] Circuit Breaker state machine completed (all `services/*/app/events.py`)
- [x] Third matching strategy added (`RoundRobinMatcher` in `dispatch-service/app/matching.py`)
- [x] L4 Design Process Document (`design-process-template.md` → export to `design.pdf`)
- [x] L3 Patterns Document (`patterns-template.md` → export to `patterns.pdf`)
- [x] Demo video script (`DEMO-SCRIPT.md`)
