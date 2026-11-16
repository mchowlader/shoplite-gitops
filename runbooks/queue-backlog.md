# Runbook: QueueBacklog (Severity: Warning)

## Alert Details
- **Condition:** `order_queue_depth` exceeds 50 for 10 minutes.
- **Impact:** Delay in asynchronous order confirmation and customer fulfillment.

## Diagnostic Steps
1. **Check Queue Length Directly in Redis:**
   ```bash
   kubectl exec -it -n shoplite deploy/shoplite-redis -- redis-cli LLEN orders:pending
   ```
2. **Inspect Worker Pod Logs:**
   ```bash
   kubectl logs -n shoplite -l app.kubernetes.io/component=worker --tail=100
   ```
3. **Verify Worker Health:**
   ```bash
   kubectl get pods -n shoplite -l app.kubernetes.io/component=worker
   ```

## Mitigation
- Scale the worker replicas to drain the queue backlog faster:
  ```bash
  kubectl scale deployment shoplite-worker -n shoplite --replicas=3
  ```
- Once queue drains back to normal (< 5), scale back to desired baseline.
