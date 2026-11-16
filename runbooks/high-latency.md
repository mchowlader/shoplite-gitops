# Runbook: HighLatency (Severity: Warning)

## Alert Details
- **Condition:** p95 latency exceeds 1 second for 5 minutes.
- **Impact:** Slow user response times on frontend, potential request timeouts.

## Diagnostic Steps
1. **Analyze Tempo Latency Waterfall:**
   - Filter spans where duration > 1000ms.
   - Determine if latency is in SQL query execution (`SELECT/INSERT`) or Redis enqueue.
2. **Check Pod CPU Throttling:**
   ```bash
   kubectl top pods -n shoplite
   ```
3. **Check Database Query Performance:**
   ```bash
   kubectl exec -it -n shoplite deploy/shoplite-postgres -- psql -U shoplite_admin -d shoplite_db -c "SELECT pid, now() - query_start AS duration, query FROM pg_stat_activity WHERE state != 'idle' ORDER BY duration DESC;"
   ```

## Mitigation
- Increase HPA max replicas or adjust CPU limits if throttled.
- Optimize slow queries with proper indexing.
