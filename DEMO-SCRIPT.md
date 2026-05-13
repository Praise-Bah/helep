# HELEP Demo Video Script (~8 minutes)

## Segment 1 — Introduction (0:00–0:45)

**Narrate:**
> "This is HELEP — the Help Emergency Location Platform. It's a microservices-based emergency response system built with FastAPI, Apache Kafka, and Kubernetes. When a citizen triggers an SOS, the platform assigns the nearest available responder, delivers a notification, and logs everything for analytics — all in under one second. Let me walk you through the architecture and a live deployment."

**Show:** architecture diagram from `design-process-template.md` §4 (Mermaid flowchart)

---

## Segment 2 — Architecture Overview (0:45–2:00)

**Narrate:**
> "We have 5 microservices: user, SOS, dispatch, notification, and analytics — each in its own container. They communicate exclusively through Apache Kafka, managed by the Strimzi Operator on Kubernetes. This is an event-driven choreographed saga — no central orchestrator."

**Show:**
- Open `architecture-overview.md` — point to the saga sequence diagram
- Show the Kafka topic list: `sos.triggered` → `responder.assigned` → `notification.sent`
- Show `strimzi/kafka-topics.yaml` — 7 topics, 3 partitions each

---

## Segment 3 — Local Smoke Test (2:00–3:30)

**Run commands (pre-recorded or live):**
```bash
# Start the dev stack
docker compose -f docker-compose.dev.yml up --build -d

# Wait for services
docker compose -f docker-compose.dev.yml ps

# 1. Register a citizen
curl -s -X POST localhost:8001/signup \
  -H 'content-type: application/json' \
  -d '{"phone":"+237600000001","password":"hunter22","role":"citizen"}' | jq .

# 2. Save the token
TOKEN="<paste token here>"

# 3. Trigger an SOS
curl -s -X POST localhost:8002/sos \
  -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"lat":4.0500,"lon":9.7700,"mode":"online"}' | jq .

# 4. Watch notification arrive
docker compose -f docker-compose.dev.yml logs notification-service | tail -5

# 5. Check analytics
curl -s localhost:8005/stats/events | jq .
```

**Narrate:**
> "The saga completes in milliseconds. The notification log shows the simulated SMS sent, and the analytics service has already recorded the event."

---

## Segment 4 — Kubernetes Deployment (3:30–5:30)

**Run commands:**
```bash
# Confirm Docker Desktop K8s is running
kubectl cluster-info
kubectl config current-context  # should show: docker-desktop

# Step 1: Create namespace and base resources
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml

# Step 2: Install Strimzi + Kafka
cd strimzi && bash strimzi-install.sh

# Step 3: Deploy all services via Helm
helm dependency update helm/helep-chart/
helm install helep helm/helep-chart/ \
  --namespace helep \
  --set global.jwtSecret="demo-secret-replace-in-prod"

# Step 4: Watch pods come up
kubectl get pods -n helep -w
```

**Show:** All 10 pods running (2 replicas × 5 services)

```bash
# Step 5: Install NGINX Ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml

# Step 6: Verify health
kubectl get ingress -n helep
curl -s http://localhost/api/users/healthz
curl -s http://localhost/api/sos/healthz
```

---

## Segment 5 — Monitoring Dashboard (5:30–6:30)

**Run commands:**
```bash
cd monitoring && bash install-monitoring.sh

# Port-forward Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
```

**Open browser:** `http://localhost:3000`
- Log in: admin / helep-admin
- Open **HELEP Services Dashboard**
- **Show:** SOS trigger count, responder assignment counter, pod CPU usage

**Narrate:**
> "Every service exposes `/metrics` scraped by Prometheus. The Grafana dashboard shows real-time SOS events, assignment counts, and HPA replica counts."

---

## Segment 6 — HPA Scaling Demo (6:30–7:15)

```bash
# Generate load (in a separate terminal)
for i in $(seq 1 50); do
  curl -s http://localhost/api/analytics/stats/events > /dev/null &
done

# Watch HPA scale up
kubectl get hpa -n helep -w
```

**Show:** `analytics-service-hpa` scaling from 2 to 3+ replicas under CPU pressure.

---

## Segment 7 — CI/CD Pipeline (7:15–7:45)

**Show GitHub Actions:**
- Open `.github/workflows/ci-cd.yaml`
- Point to: Lint stage → Build & Push stage → Helm deploy stage
- Briefly show a green pipeline run (screenshot acceptable)

---

## Segment 8 — Conclusion (7:45–8:00)

**Narrate:**
> "To summarise: 5 microservices deployed on Kubernetes with Helm, event-driven via Strimzi-managed Kafka, monitored with Prometheus and Grafana, and deployed automatically via GitHub Actions. The design and patterns documents provide the architectural traceability required. Thank you."

---

## Recording Checklist

- [ ] All terminal commands pre-tested and outputs ready
- [ ] Docker Desktop K8s running before recording
- [ ] `TOKEN` variable set from real signup response
- [ ] Grafana dashboard loaded with at least a few data points
- [ ] Screen resolution: 1920×1080 minimum
- [ ] Microphone checked
- [ ] Export as MP4, < 10 minutes
