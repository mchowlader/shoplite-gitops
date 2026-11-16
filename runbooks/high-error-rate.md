# Runbook: HighErrorRate (Severity: Critical)

## Alert Details
- **Condition:** HTTP 5xx rate exceeds 5% for 5 minutes.
- **Impact:** Customers experiencing checkout or product catalog browsing failures.

## Diagnostic Steps
1. **Check Backend Pod Logs via Loki:**
   ```bash
   kubectl logs -n shoplite -l app.kubernetes.io/component=backend --tail=100
   ```
2. **Inspect Database & Redis Connectivity:**
   ```bash
   kubectl exec -it -n shoplite deploy/shoplite-backend -- curl -s http://localhost:8000/readyz
   ```
3. **Grafana Trace Inspection (Tempo):**
   - Navigate to Grafana Explore -> Tempo datasource.
   - Filter by `status_code=500` to inspect error stack traces.

## Mitigation
- If database connection pool is saturated, scale backend replicas:
  ```bash
  kubectl scale deployment shoplite-backend -n shoplite --replicas=4
  ```
- If bad release was deployed, rollback via ArgoCD or Helm:
  ```bash
  helm rollback shoplite -n shoplite
  ```
