# ShopLite Architecture State & Context Memory

**Project:** ShopLite on AWS DevOps Capstone Assessment (`DEVOPS-CAP-601`)  
**Target:** 100/100 Points + 10 Bonus Points (Distinction Tier)  
**Primary Repositories:**
- Application & Assessment Source: [`https://github.com/mchowlader/shoplite-app.git`](https://github.com/mchowlader/shoplite-app.git)
- GitOps & Cluster Delivery: [`https://github.com/mchowlader/shoplite-gitops.git`](https://github.com/mchowlader/shoplite-gitops.git)

---

## 1. Executive Architecture Summary

ShopLite is a distributed, containerized e-commerce microservices platform orchestrated on a highly available, multi-AZ Kubernetes cluster deployed on Amazon Web Services (AWS) using Infrastructure as Code (Terraform) and Configuration Management (Ansible). 

The application architecture decouples transactional client operations from asynchronous background processing:
- **Frontend:** React SPA served via Nginx reverse proxy.
- **Catalog API:** Python 3.11 / FastAPI service handling catalog lookups and order submissions.
- **Message Broker:** Redis cluster running `orders:pending` streams for asynchronous processing.
- **Order Worker:** Python 3.11 background processor extracting orders from Redis and writing confirmed transactions to the relational store.
- **Database:** PostgreSQL 15 deployed as a Kubernetes `StatefulSet` with dynamic persistent volume management.
- **Observability Stack:** Prometheus (Metrics + Exemplars), Grafana Tempo (Distributed Tracing), Grafana Loki (Log Aggregation), and Grafana ("ShopLite - Golden Signals" Dashboard).

```mermaid
flowchart TD
    Client(["Internet Clients"]) --> ALB["AWS Application Load Balancer"]
    ALB --> Ingress["NGINX Ingress Controller"]
    
    subgraph K8s["Kubernetes Cluster (v1.29)"]
        Ingress --> FE["frontend (React/Nginx)"]
        Ingress --> API["catalog-api (FastAPI)"]
        Ingress --> Grafana["grafana (/grafana/)"]
        
        API -- "W3C traceparent" --> Redis[("redis:6379\n(Message Broker)")]
        Redis --> Worker["order-worker (Python 3.11)"]
        Worker --> Postgres[("shoplite-postgres\n(StatefulSet 10Gi)")]
        
        API -. "OTLP gRPC 4317" .-> Tempo[("tempo:4317\n(Traces)")]
        Worker -. "OTLP gRPC 4317" .-> Tempo
        
        Prometheus[("prometheus:9090\n(Metrics + Exemplars)")] -. "Scrape /metrics" .-> API
        Promtail["promtail (DaemonSet)"] -. "Ship logs" .-> Loki[("loki:3100\n(Logs)")]
        
        Grafana --> Prometheus
        Grafana --> Tempo
        Grafana --> Loki
    end
```

---

## 2. Infrastructure & Network Topology

### AWS Custom VPC Specifications
- **CIDR Block:** `10.0.0.0/16` across two Availability Zones (`ap-southeast-1a`, `ap-southeast-1b`).
- **Public Subnets:** `10.0.1.0/24` (AZ-a), `10.0.2.0/24` (AZ-b) hosting Internet Gateway, NAT Gateway, and external ALB.
- **Private Subnets:** `10.0.10.0/24` (AZ-a), `10.0.11.0/24` (AZ-b) hosting Kubernetes worker nodes and database workloads.
- **Cost Guard:** AWS Budget Alarm provisioned via Terraform (`aws_budgets_budget.cost_guard`) enforcing a \$20 USD monthly limit with automated email alerting.

### Dual-Access Security Mode (`enable_ssh_bastion`)
To ensure full compliance with strict assessment rubrics while preserving operational agility in restricted sandboxes (e.g., Poridhi Labs where AWS Systems Manager endpoints may be blocked by Service Control Policies), the Terraform compute and network modules implement a feature toggle:

| Mode | Variable Setting | Control Plane Location | Port 22 | Public IP | Compliance Target |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Pure SSM (Default)** | `-var="enable_ssh_bastion=false"` | Private Subnet (`10.0.10.x`) | Closed | None (0) | 100% Exam & Enterprise Rubric |
| **Sandbox Bastion** | `-var="enable_ssh_bastion=true"` | Public Subnet (`10.0.1.x`) | Open (Key Pair) | Elastic IP (1) | Poridhi Restricted Lab Sandbox |

*Worker nodes remain 100% private in `10.0.10.x` and `10.0.11.x` under both modes, accessible exclusively via the control plane.*

---

## 3. Kubernetes Workload Design & GitOps Primitives

1. **Stateful Workloads (`shoplite-postgres`):**
   - Deployed as `kind: StatefulSet` with `serviceName: shoplite-postgres` and dynamic `volumeClaimTemplates` requesting 10Gi on Rancher's `local-path` default StorageClass.
   - Guaranteed predictable network identity, persistent volume lifecycle management, and zero pod-split risks during node recycles.

2. **Zero-Downtime Delivery (`catalog-api`):**
   - Packaged with dual deployment definitions: standard `Deployment` and Argo Rollouts Canary `Rollout` (20% step, 1m pause, automated analysis), guarded by mutual-exclusivity templates.
   - Protected by `PodDisruptionBudget` (`minAvailable: 1`) and `HorizontalPodAutoscaler` (min: 2, max: 5, target: 70% CPU utilization).

3. **Multi-Environment Configuration Drift Prevention:**
   - `envs/dev/values.yaml`: Cost-optimized single-replica footprint (`v1.0.0-dev`, CPU: 50m, Memory: 64Mi).
   - `envs/prod/values.yaml`: High-availability multi-replica footprint (`v1.0.0`, CPU: 200m–1000m, Memory: 256Mi–1Gi, HPA enabled).

4. **Section 2.1 Repository Alignment:**
   - `shoplite-app` houses the full application codebase, CI pipeline, and mirrored assessment deliverables (`ansible/`, `helm/`, `observability/`, `runbooks/`, `docs/`) to satisfy single-repository assessment evaluators.
   - `shoplite-gitops` serves as the live GitOps cluster source managing declarations for Helm and cluster configurations.

---

## 4. Observability & Distributed Tracing Matrix

| Telemetry Pillar | Technology | Implementation Details |
| :--- | :--- | :--- |
| **Distributed Tracing** | Grafana Tempo + OpenTelemetry | End-to-end W3C `traceparent` context injection from `catalog-api` into Redis payloads (`orders:pending`), extracted by `order-worker` and exported via OTLP gRPC (`4317`). Produces single unified waterfall traces spanning HTTP, Queue, Worker, and DB. |
| **Exemplars & Metrics** | Prometheus + OpenMetrics | FastAPI exposes OpenMetrics on `/metrics`. `http_request_duration_seconds` records OpenTelemetry `TraceID` exemplars. Grafana queries render clickable exemplar markers linking directly to Tempo traces. |
| **Log Aggregation** | Promtail + Grafana Loki | Promtail daemonset scrapes all container logs and ships structured logs with Kubernetes labels to Loki. |
| **Unified Dashboard** | Grafana 10.x | Pre-provisioned dashboard: `"ShopLite - Golden Signals"` (`shoplite-golden-signals.json`) located at `http://<ALB-DNS>/grafana/`. Displays Request Rate, 95th Percentile Latency with Exemplars, Error Rate, and Cluster Saturations. |

---

## 5. Security & Verification Guardrails

- **Pre-commit Hooks:** Enforced across both repositories via `.pre-commit-config.yaml` (`terraform_fmt`, `hadolint`, `yamllint`, `detect-secrets`, `check-yaml`, `check-added-large-files`).
- **CI/CD Pipeline:** Enforced in `.github/workflows/app-ci.yml` with automated testing, `hadolint` Dockerfile linting, `helm lint`, and Trivy security scanning failing builds on `CRITICAL` severity (`exit-code: 1`).
- **Antigravity Protocol:** Governed by `AGENTS.md` and `.agents/rules/strict-protocol.md` mandating secular engineering tone, deterministic terminal verification, and diff-first patch management.

---

## 6. Fresh Lab Spin-Up Sequence (Quick Resumption Runbook)

When initiating a fresh lab session on a Poridhi AWS VM, execute the following deterministic steps:

### Step 1: Provision Infrastructure via Terraform (Terminal 1)
```bash
cd ~/code/shoplite-app/terraform
git pull origin main
terraform init
terraform apply -var="enable_ssh_bastion=true" -auto-approve
```

### Step 2: Extract Outputs & Create ECR Secret
```bash
CP_PUBLIC_IP=$(terraform output -raw control_plane_public_ip)
ECR_PASS=$(aws ecr get-login-password --region ap-southeast-1)

ssh -o StrictHostKeyChecking=no -i ~/.ssh/shoplite-key.pem ubuntu@$CP_PUBLIC_IP \
  "kubectl create namespace shoplite --dry-run=client -o yaml | kubectl apply -f - && \
   kubectl create secret docker-registry ecr-secret --namespace shoplite \
   --docker-server=779846822536.dkr.ecr.ap-southeast-1.amazonaws.com \
   --docker-username=AWS --docker-password='$ECR_PASS'"
```

### Step 3: Bootstrap Kubernetes Cluster via Ansible (Terminal 1)
```bash
cd ~/code/shoplite-app/ansible
git pull origin main
./run-ansible.sh
```

### Step 4: Deploy Workloads & Observability (Terminal 2 - Control Plane)
```bash
# Connect to Control Plane
ssh -i ~/.ssh/shoplite-key.pem ubuntu@$CP_PUBLIC_IP

# Deploy ShopLite Application
cd ~/shoplite-gitops
git pull origin main
helm upgrade --install shoplite ./helm/shoplite -n shoplite --create-namespace

# Deploy Observability Stack
cd ~/shoplite-gitops/observability
git pull origin main
./deploy-observability.sh

# Verify Cluster Status
kubectl get pods -A
```
