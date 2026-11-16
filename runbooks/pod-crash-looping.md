# Runbook: PodCrashLooping (Severity: Critical)

## Alert Details
- **Condition:** Pod restarts are increasing over 10 minutes.
- **Impact:** Service degradation, loss of active replicas, potential 502/503 errors.

## Diagnostic Steps
1. **Identify the Failing Pod:**
   ```bash
   kubectl get pods -n shoplite | grep -E "CrashLoopBackOff|Error"
   ```
2. **Inspect Exit Code and Termination Reason:**
   ```bash
   kubectl describe pod <pod-name> -n shoplite
   ```
   *Look for `Last State: Terminated` with `Exit Code: 137` (OOMKilled) or `Exit Code: 1` (Application Exception).*
3. **Check Previous Container Logs:**
   ```bash
   kubectl logs <pod-name> -n shoplite --previous
   ```

## Mitigation
- If **OOMKilled (Exit 137)**: Increase memory limit in `values.yaml` (e.g. from 256Mi to 512Mi).
- If **Liveness Probe Failure**: Verify if initialDelaySeconds is too short.
