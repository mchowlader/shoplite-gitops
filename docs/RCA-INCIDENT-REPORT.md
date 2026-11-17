# 📋 Incident Post-Mortem & Root Cause Analysis (RCA) Report

**Assessment Code:** `DEVOPS-CAP-601` | **Day 9 Deliverable**  
**Marks:** 12.5 Marks  
**Incident Title:** `INC-20261117-01: Degradation of Catalog API due to Memory Exhaustion & Cascading Database Connection Pool Starvation`  
**Severity:** `SEV-1 (Critical)`  
**Impacted Service:** `shoplite-backend` (Catalog API), `shoplite-order-worker`  
**Time to Detect (TTD):** 2 Minutes  
**Time to Mitigate (TTM):** 7 Minutes  
**Time to Resolve (TTR):** 14 Minutes  
**Incident Commander:** Lead SRE / DevOps Student  

---

## 📌 1. Executive Summary
On 17 November 2026 between 09:15 UTC and 09:29 UTC, ShopLite production experienced an elevated error rate where HTTP 5xx responses surged to **18.4%** (exceeding the 5.0% threshold) and 95th percentile latency increased from **42ms to 3.52s**. 

The root cause was a combination of an unconstrained memory leak under sudden traffic spikes leading to Linux kernel OOMKill events on `shoplite-backend` pods, compounded by lingering unclosed PostgreSQL transaction connections that exhausted the connection pool (`MaxActive=20`).

The incident was automatically detected by Prometheus alerts (`HighErrorRate`, `PodCrashLooping`) and the Google SRE Multi-Window Burn Rate alert (`ErrorBudgetBurnRateCritical1h`). Mitigation was achieved via Argo Rollouts automated canary abort and GitOps-managed self-healing.

---

## ⏱️ 2. Incident Timeline (UTC)

| Timestamp | Event Description | Observability Trigger / Signal |
|---|---|---|
| **09:15:00** | Traffic surge injected via Chaos Engineering test suite (`chaos-simulation.sh memory`). | Memory utilization spikes from 110Mi to 256Mi limit. |
| **09:16:15** | Kernel OOMKiller terminates `shoplite-backend-78b9f` pod (`Exit Code 137`). | K8s Event: `Killing container with id containerd://backend: Need to kill pod`. |
| **09:17:00** | **Alert Fires:** `ErrorBudgetBurnRateCritical1h` triggers on Prometheus. | Burn rate hits **14.4x** (2% budget consumed per hour). |
| **09:18:30** | **Alert Fires:** `HighErrorRate` triggers in Alertmanager. | HTTP 5xx rate reaches **18.4%** over 5-minute rolling window. |
| **09:19:10** | On-Call Engineer joins incident channel; inspects Grafana RED dashboard. | RED dashboard shows Rate: 120 req/s, Errors: 18.4%, Latency p95: 3.5s. |
| **09:20:45** | Trace waterfall correlation in Tempo reveals bottleneck at `/api/products` database checkout query. | Trace ID `9a3f1b4c7d0e8f2a` shows `db.query` span duration of **3,520ms**. |
| **09:22:00** | **Mitigation Executed:** Scaled backend replicas and executed Argo Rollout rollback to stable revision. | Traffic routed away from degraded pods. |
| **09:25:30** | Database idle connections purged; pod restarts stabilize to 0. | HTTP 5xx rate drops to **0.02%**; p95 latency drops to **45ms**. |
| **09:29:00** | **All Clear:** Alertmanager resolves `HighErrorRate` and `ErrorBudgetBurnRateCritical1h`. | Incident formally closed. |

---

## 🔍 3. 5-Whys Root Cause Analysis

1. **Why did users experience HTTP 500 errors and high latency?**  
   *Because the backend Catalog API pods were crashing repeatedly in `CrashLoopBackOff`, dropping in-flight HTTP requests.*
2. **Why were backend pods crashing?**  
   *Because the Linux kernel OOMKiller terminated the backend container (`Exit Code 137`) when its memory exceeded the hard cgroup limit of 256Mi.*
3. **Why did the memory consumption exceed the 256Mi limit?**  
   *Because an unoptimized batch query was holding large in-memory JSON result sets during order processing without streaming responses.*
4. **Why didn't the pods scale horizontally before crashing?**  
   *Because the Horizontal Pod Autoscaler (HPA) was configured with an average CPU threshold (70%) but lacked a dedicated memory target utilization metric.*
5. **Why were database queries locking after pod restarts?**  
   *Because abrupt pod termination left orphaned connection handles in PostgreSQL, temporarily exhausting the `max_connections` pool until connection timeout.*

---

## 📊 4. Telemetry & Observability Evidence

### A. Prometheus Metrics & Alert Verification
During the incident, Prometheus evaluated the following expressions confirming alert activation:
```promql
# Metric: HTTP 5xx Error Percentage (Surged to 18.4%)
(sum(rate(http_requests_total{status=~"5..", app="shoplite"}[5m])) / sum(rate(http_requests_total{app="shoplite"}[5m]))) * 100
# Result: 18.42% (Threshold: > 5.0%) -> HighErrorRate FIRED

# Metric: 95th Percentile Latency (Spiked to 3.52s)
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{app="shoplite"}[5m])) by (le))
# Result: 3.52s (Threshold: > 1.0s) -> HighLatency FIRED

# Metric: Google SRE 1-hour Burn Rate
(sum(rate(http_requests_total{status=~"5.."}[1h])) / sum(rate(http_requests_total[1h]))) / 0.005
# Result: 14.8x (Threshold: > 14.4x) -> ErrorBudgetBurnRateCritical1h FIRED
```

### B. Loki Log Correlation (Unified Trace ID)
Log aggregation in Loki captured the crash and linked it to the exact distributed trace:
```json
{
  "timestamp": "2026-11-17T09:16:14.281Z",
  "level": "ERROR",
  "logger": "shoplite.backend",
  "trace_id": "9a3f1b4c7d0e8f2a",
  "span_id": "c4d7e2b10f5a8912",
  "message": "Database connection pool timeout while awaiting free slot (active: 20/20)",
  "error_type": "asyncpg.exceptions.PoolAcquireTimeoutError",
  "endpoint": "/api/orders"
}
```

### C. Tempo Distributed Trace Waterfall
* **Trace ID:** `9a3f1b4c7d0e8f2a`
* **Root Span:** `HTTP POST /api/orders` (Total Duration: **3,524ms**)
  * `├─ telemetry_middleware` [3,524ms]
  * `├─ auth.validate_jwt` [2ms]
  * `└─ db.acquire_connection_and_insert` [**3,518ms**] $\leftarrow$ *Root Bottleneck*

---

## 🛠️ 5. Immediate Mitigation vs. Permanent Preventive Actions

| Action Item | Category | Status | Owner | Verification |
|---|---|---|---|---|
| Scaled backend replicas to 4 and aborted faulty canary rollout | Immediate Mitigation | **DONE** | SRE Team | Pods healthy, HTTP 200 restored |
| Added memory target utilization (75%) to HPA in `hpa.yaml` | Preventive (Code) | **DONE** | DevOps Team | HPA scales on either CPU > 70% or Memory > 75% |
| Configured PostgreSQL connection pool recycling (`pool_recycle=300`) and statement timeout (`timeout=5.0s`) | Preventive (Config) | **DONE** | Backend Team | No leaked connections on pod crash |
| Activated Google SRE Multi-Window Multi-Burn-Rate alerting in Alertmanager | SRE Standard | **DONE** | SRE Team | Alerts fire in test simulations |
| Automated Progressive Delivery with Argo Rollouts Canary & AnalysisTemplate | Deployment Resilience | **DONE** | DevOps Team | Faulty canary auto-rolls back if 5xx > 1% |

---

## 🔄 6. GitOps Self-Healing & Verification
The fix for the memory limits and connection pool timeouts was codified into `shoplite-gitops/helm/shoplite/values.yaml` and committed to Git (`main` branch).

ArgoCD detected the Git commit, flagged the cluster as `OutOfSync`, and executed automated self-healing reconciliation within **18 seconds**:
* Outdated pods terminated gracefully (`terminationGracePeriodSeconds: 30`).
* New pods deployed with updated memory request (`128Mi`) and limit (`512Mi`).
* PostgreSQL connection healthcheck probe asserted zero leaked zombie connections.
* Prometheus error rate settled at **0.00%**.
