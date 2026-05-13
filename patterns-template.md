# L3 Patterns-in-Code Document — HELEP

> ~3 pages. Each pattern entry cites the exact file and line number. No citation = no marks.

---

## Part A — Pre-implemented Patterns

### A.1 Choreographed Saga

**Where (happy path):**
1. `sos-service/app/main.py:85-96` — `trigger()` inserts incident row, then publishes `sos.triggered` with `key=incident_id`
2. `dispatch-service/app/main.py:62-93` — `handle_sos()` consumes `sos.triggered`, picks a responder, publishes `responder.assigned`
3. `notification-service/app/main.py` — consumes `responder.assigned`, logs "SMS sent", publishes `notification.sent`

**Compensation step:**
- Trigger: citizen calls `POST /sos/{id}/cancel` → `sos-service/app/main.py:102-111` publishes `sos.cancelled`
- Rollback: `dispatch-service/app/main.py:96-103` — `handle_cancel()` calls `release_assignment(iid)` which sets `assignments.status='RELEASED'` and `responders.busy=0` (`dispatch-service/app/db.py:97-103`)
- **State rolled back:** responder is freed (`busy=0`), assignment is marked `RELEASED`

**Why Choreography (not Orchestration):** No central coordinator = no single point of failure. Each service reacts independently to Kafka events, satisfying ASR-2 (Availability).

---

### A.2 Pub/Sub via Apache Kafka

**Where:** `app/events.py` in all 5 services — `AIOKafkaProducer` (lines 26-37) and `AIOKafkaConsumer` (lines 95-117).

**Consumer group semantics (at-least-once delivery):**
- `enable_auto_commit=False` is set at `events.py:100` — Kafka does NOT automatically advance the offset.
- Manual `await consumer.commit()` is called at `events.py:112`, **only after** `await handler(payload)` succeeds.
- If the handler raises, the exception is caught at `events.py:113-115` and the offset is left uncommitted → the message is re-delivered on the next poll.
- This guarantees every event is processed **at least once**, even across pod restarts.

**Partition keying:**
- `publish(..., key=incident_id)` at `sos-service/app/main.py:95` and `dispatch-service/app/main.py:80` routes all events for one incident to the **same partition**.
- One partition is owned by exactly one consumer pod within a group → events for incident X are always processed by the same pod in sequence, preserving the "no double dispatch" invariant even with 5 dispatch-service replicas.

---

### A.3 Repository

**Where:** `app/db.py` in every service. Example: `dispatch-service/app/db.py:1-109`.

**Key functions:**
- `reserve_responder_for()` at `dispatch-service/app/db.py:71-89` — atomic `UPDATE … WHERE busy=0` with idempotency check
- `insert_incident()`, `get()`, `cancel()` in `sos-service/app/db.py`

**Why this matters:**
If route handlers queried SQLite directly, the `UPDATE … WHERE busy=0` logic would be scattered across multiple files. Any new replica or endpoint that needs to claim a responder would re-implement (and possibly break) the atomicity guarantee. The Repository centralises the atomic claim in one tested function — the rest of the codebase cannot accidentally bypass it.

**Additional benefit:** Unit tests can mock `app.db` module without spawning a real SQLite file.

---

### A.4 Strategy

**Where:** `dispatch-service/app/matching.py:31-83`

**Three strategies implemented:**

| Strategy | Class | Lines | Logic |
|----------|-------|-------|-------|
| Nearest | `NearestMatcher` | 31-39 | Haversine distance → pick minimum |
| Credibility-weighted | `CredibilityWeightedMatcher` | 42-54 | `score = credibility / (dist_km + 1)` → pick maximum |
| Round-robin *(added)* | `RoundRobinMatcher` | 60-74 | Cycle through pool by modulo counter |

**How to switch:** set `MATCHER=nearest|credibility|round_robin` environment variable; factory `matcher()` at line 77-83 returns the correct instance.

**Round-robin addition (lines added by us):**
```python
# dispatch-service/app/matching.py:57-74
_round_robin_index: int = 0

class RoundRobinMatcher:
    def pick(self, victim_lat, victim_lon, responders):
        global _round_robin_index
        pool = list(responders)
        if not pool:
            return None
        chosen = pool[_round_robin_index % len(pool)]
        _round_robin_index += 1
        return {"id": chosen["id"], "index": _round_robin_index - 1}
```

**Trade-off vs Nearest:** Round-robin ensures equal load distribution but may dispatch a far responder. Suitable for station-based urban deployments where all responders are equidistant.

---

### A.5 Outbox-lite

**Where:** `sos-service/app/main.py:84-96` — `trigger()` function.

```python
# sos-service/app/main.py:84-96
insert_incident(iid, claims["sub"], body.lat, body.lon, body.mode, media_ref)
await publish("sos.triggered", { ... }, key=iid)
```

**Why "lite":** The DB write and Kafka publish are in the same `async` block but are **not atomic**. If the process crashes after `insert_incident()` but before `publish()`, the incident exists in SQLite but no `sos.triggered` event is ever emitted — the saga never starts.

**What a real Outbox would add:** Write the pending event to an `outbox` table inside the same SQLite transaction as the incident row. A background relay process polls the outbox, publishes to Kafka, then marks the row `published=1`. This survives process crashes with no event loss.

---

### A.6 Circuit Breaker (completed)

**Where:** `app/events.py:58-87` in all 5 services (identical implementation).

**State machine implemented:**

```python
# app/events.py:65-87 (user-service shown; identical in all services)
def allow(self) -> bool:
    import time as _time
    if self.opened_at is None:
        return self.fails < self.fail_threshold   # CLOSED
    elapsed = _time.monotonic() - self.opened_at
    if elapsed >= self.reset_after_s:
        self.opened_at = None; self.fails = 0
        return True                               # HALF_OPEN → probe
    return False                                  # OPEN

def record_failure(self) -> None:
    import time as _time
    self.fails += 1
    if self.fails >= self.fail_threshold:
        self.opened_at = _time.monotonic()        # CLOSED → OPEN
```

**State transitions:**
| Transition | Trigger | Condition |
|------------|---------|-----------|
| CLOSED → OPEN | `record_failure()` | `fails >= fail_threshold` (default: 5) |
| OPEN → HALF_OPEN | `allow()` called | `elapsed >= reset_after_s` (default: 10 s) |
| HALF_OPEN → CLOSED | `record_success()` | Next publish succeeds |
| HALF_OPEN → OPEN | `record_failure()` | Probe publish fails |

**Effect in HELEP:** When the Kafka broker is unreachable, the circuit opens after 5 consecutive failures. For the next 10 seconds, all `publish()` calls immediately raise `RuntimeError("circuit-open: …")` without waiting for a TCP timeout, protecting service threads from blocking.

---

## Part B — Patterns Added

### B.1 API Gateway (Cloud-Native Catalogue)

**Where added:** `k8s/ingress.yaml:1-47` (NGINX Ingress Controller)

**Problem it solves in HELEP:**
Without a gateway, each service exposes a separate `NodePort` or `LoadBalancer`. External clients must know 5 different ports (8001–8005) and service hostnames. The API Gateway provides a single external entry point (`/api/{service}/*`) and rewrites paths before forwarding to the backend ClusterIP service.

```yaml
# k8s/ingress.yaml:14-19
- path: /api/sos(/|$)(.*)
  pathType: ImplementationSpecific
  backend:
    service:
      name: sos-service
      port: { number: 8002 }
```

**Trade-off vs alternatives:**
- *Ingress (chosen):* built into K8s ecosystem, no extra process, path-based routing. Limitation: no advanced traffic shaping.
- *Service Mesh (e.g., Istio):* adds mTLS, circuit breaking at network level, and advanced traffic policies — but requires a sidecar per pod and significant operational overhead that exceeds the 24-hour build budget.

---

### B.2 Bulkhead (Cloud-Native Catalogue)

**Where added:** each service declares its own Kafka consumer group in `app/main.py`.

| Service | Consumer Group | Lines |
|---------|---------------|-------|
| dispatch-service | `"dispatch-service"` | `dispatch-service/app/main.py:38` |
| notification-service | `"notification-service"` | `notification-service/app/main.py:26` |
| analytics-service | `"analytics-service"` | `analytics-service/app/main.py:23` |

**Problem it solves in HELEP:**
If all services shared one consumer group, a slow analytics query would consume a Kafka partition share that blocks dispatch processing. Separate groups mean each service has its own independent offset cursor — analytics consumer lag cannot affect dispatch or notification throughput.

**Trade-off vs alternatives:**
- *Separate consumer groups (chosen):* full isolation, each service processes at its own rate. Each group requires the topic to replicate messages to all groups.
- *Single shared group with topic fan-out:* simpler config but couples processing rates — rejected because it violates the Bulkhead goal of independent failure domains.

---

## Part C — Anti-pattern Avoided: Shared Database

**Anti-pattern:** Shared Database across services (a.k.a. Integration Database).

**Why it is dangerous:** If all services read/write the same database, a schema change in `dispatch-service` can silently break `analytics-service`. Services become coupled at the data layer, negating the independence benefit of microservices.

**How HELEP avoids it:**
Each service has its own SQLite file on its own PVC (`/data/*.db`). Cross-service data access is achieved exclusively through Kafka events — `analytics-service` receives a `responder.assigned` event rather than joining against the `dispatch-service` assignments table.

**Citation:** `dispatch-service/app/db.py:1` — `DB_PATH = os.getenv("DB_PATH", "/data/dispatch.db")` — the path is service-private and not shared with any other service container.

---

## Submission

Submit as `patterns.pdf`. Keep code excerpts ≤ 10 lines.
