# 📘 Incident Runbook: SLO Error Budget Burn Rate

**Alert Names:** `ErrorBudgetBurnRateCritical1h`, `ErrorBudgetBurnRateCritical6h`, `ErrorBudgetBurnRateWarning3d`  
**Service:** `shoplite-backend` (Catalog API)  
**Target SLO:** 99.5% Availability over 30 days rolling period (Error Budget: 0.5% = 0.005)  
**Standard:** Google SRE Handbook Chapter 5 (Alerting on SLOs)

---

## 🎯 1. Overview & Architectural Rationale
Unlike naive point-in-time threshold alerts (e.g. `5xx > 1%`) which generate high false positives during temporary glitches, **Multi-Window Multi-Burn-Rate Alerting** assesses the **rate at which the error budget is being consumed** over complementary short and long time windows:

| Alert | Burn Rate | Long Window | Short Window | Budget Consumed | Action |
|---|---|---|---|---|---|
| `ErrorBudgetBurnRateCritical1h` | **14.4x** | 1 Hour | 5 Minutes | 2% in 1 hour | Immediate Pager (Page On-Call) |
| `ErrorBudgetBurnRateCritical6h` | **6.0x** | 6 Hours | 30 Minutes | 5% in 6 hours | Immediate Pager (Page On-Call) |
| `ErrorBudgetBurnRateWarning3d` | **1.0x** | 3 Days | 6 Hours | 10% in 3 days | High-Priority Ticket (Business Hours) |

---

## 🔍 2. Step-by-Step Diagnostic Workflow

### Step 1: Confirm Active Burn Rate & Impact
Check the current burn rate and request rate in Prometheus / Grafana:
```promql
# Current Error Rate (%) over 5m
(sum(rate(http_requests_total{status=~"5..", app="shoplite"}[5m])) / sum(rate(http_requests_total{app="shoplite"}[5m]))) * 100

# Burn Rate Factor (Relative to 0.5% budget)
(sum(rate(http_requests_total{status=~"5..", app="shoplite"}[1h])) / sum(rate(http_requests_total{app="shoplite"}[1h]))) / 0.005
```

### Step 2: Correlate with Recent Deployments (Argo Rollouts)
Determine if a recent Canary deployment triggered the burn:
```bash
kubectl argo rollouts status rollout shoplite-backend -n shoplite
```
*If a rollout is in progress:*
Check if the Canary revision is returning HTTP 5xx errors:
```bash
kubectl logs -l app.kubernetes.io/component=backend,rollouts-pod-template-hash -n shoplite --tail=100 | grep -E "500|502|503"
```

### Step 3: Check Distributed Tracing in Tempo
1. Open Grafana Explore -> Select **Tempo** datasource.
2. Filter by `service.name = "shoplite-catalog-api"` and `status.code = ERROR`.
3. Inspect trace waterfalls for PostgreSQL timeout or Redis queue connection drops.

### Step 4: Inspect Database Connection Pool & Latency
```bash
kubectl exec -it deployment/shoplite-postgres -n shoplite -- psql -U shoplite_admin -d shoplite_db -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"
```

---

## 🛠️ 3. Remediation & Recovery Protocol

### Immediate Mitigation:
1. **If caused by recent deployment:**
   Trigger an immediate Argo Rollouts abort:
   ```bash
   kubectl argo rollouts abort rollout shoplite-backend -n shoplite
   kubectl argo rollouts undo rollout shoplite-backend -n shoplite
   ```
2. **If caused by high traffic / pod resource exhaustion:**
   Temporarily scale the backend replicas:
   ```bash
   kubectl scale deployment/shoplite-backend -n shoplite --replicas=5
   ```
3. **If caused by PostgreSQL pool starvation:**
   Restart the backend pods to drop stale connections:
   ```bash
   kubectl rollout restart deployment/shoplite-backend -n shoplite
   ```

---

## 🛡️ 4. Post-Incident Review & Error Budget Accounting
1. Calculate total error budget consumed:
   $$\text{Budget Consumed (\%)} = \frac{\text{Total 5xx Errors in Incident}}{\text{Total Valid Requests in 30 Days} \times 0.005} \times 100$$
2. If total consumed budget $> 100\%$, implement a **Feature Freeze**: halts non-critical feature releases until the rolling 30-day budget recovers above $0\%$.
