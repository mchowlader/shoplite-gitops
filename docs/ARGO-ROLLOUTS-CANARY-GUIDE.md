# 🚀 Bonus Guide: Argo Rollouts Progressive Delivery (Canary Deployment)

**Bonus Marks:** +10 Marks (High Distinction Honors)  
**Standard:** GitOps Progressive Delivery with Automated Metric Analysis & Instant Rollback  
**Components:**
1. `argoproj.io/v1alpha1` **Rollout** resource (replaces standard Kubernetes Deployment)
2. **AnalysisTemplate** (Prometheus-backed real-time automated verification)
3. Separate **Canary** and **Stable** Kubernetes Services

---

## 🎯 1. Why Argo Rollouts over Standard Kubernetes RollingUpdate?

Standard Kubernetes `Deployment` (`RollingUpdate` strategy) blindly replaces old pods with new pods. If the new release has a silent bug (e.g., 500 error on checkout or high memory leak), all users eventually receive the broken version.

**Argo Rollouts Canary Strategy solves this:**
```
Traffic ───> NGINX Ingress ──┬──> 90% Traffic ──> Stable Service ──> Stable Pods (v1.0.0)
                             │
                             └──> 10% Traffic ──> Canary Service ──> Canary Pods (v1.1.0)
                                                        │
                                                        ▼
                                             Prometheus Metric Analysis
                                             (Success Rate >= 99% & Latency <= 500ms)
                                                        │
                                         ┌──────────────┴──────────────┐
                                         ▼                             ▼
                                   [✅ PASSED]                   [❌ FAILED]
                             Step 2: 30% -> 60% -> 100%    Automatic Rollback to v1.0.0
```

---

## 🛠️ 2. Architectural Structure in ShopLite

### 1. Canary Traffic Steps (`rollout-backend.yaml`):
```yaml
strategy:
  canary:
    steps:
      - setWeight: 10
      - pause: { duration: 1m }
      - setWeight: 30
      - pause: { duration: 2m }
      - setWeight: 60
      - pause: { duration: 2m }
```

### 2. Automated Prometheus Analysis (`analysistemplate.yaml`):
Every 30 seconds, Argo Rollouts executes PromQL queries against Prometheus:
1. **Success Rate:**
   $$\frac{\sum \text{rate}(http\_requests\_total\{status ! \sim 5..\}[1m])}{\sum \text{rate}(http\_requests\_total[1m])} \ge 0.99$$
   *(Asserts HTTP 5xx error rate is below 1%.)*
2. **Latency (p95):**
   $$\text{histogram\_quantile}(0.95, \dots) \le 0.5s$$
   *(Asserts 95th percentile latency is under 500 milliseconds.)*

---

## 🖥️ 3. Operational CLI Commands for Examiners

### 1. Check Rollout Status:
```bash
kubectl argo rollouts get rollout shoplite-backend -n shoplite --watch
```

### 2. Promote Canary Manually (Skip Pause):
```bash
kubectl argo rollouts promote shoplite-backend -n shoplite
```

### 3. Abort Rollout & Auto-Rollback:
```bash
kubectl argo rollouts abort shoplite-backend -n shoplite
kubectl argo rollouts undo shoplite-backend -n shoplite
```
