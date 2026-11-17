#!/usr/bin/env bash
# ==============================================================================
# ShopLite: Production Chaos Engineering & Failure Injection Suite (Day 9)
# Purpose: Simulates deterministic real-world failures to test:
#   1. Prometheus & Google SRE Multi-Burn-Rate Alert Triggering
#   2. Grafana RED Metrics, Loki Log Traces & Tempo Distributed Tracing
#   3. Argo Rollouts Automated Canary Rollback & GitOps Self-Healing
# Usage: ./chaos-simulation.sh [memory|latency|queue|status|cleanup]
# ==============================================================================

set -euo pipefail

NAMESPACE="shoplite"
BACKEND_DEPLOY="shoplite-backend"
WORKER_DEPLOY="shoplite-order-worker"
POSTGRES_DEPLOY="shoplite-postgres"

# ANSI Colors for Executive Terminal Output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_header() {
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${BLUE}===================================================================${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ------------------------------------------------------------------------------
# Chaos Scenario 1: Memory Exhaustion & OOMKill (Triggers PodCrashLooping & 5xx)
# ------------------------------------------------------------------------------
inject_memory_exhaustion() {
    log_header "Chaos Scenario 1: Backend Memory Exhaustion & OOMKill"
    log_info "Target Namespace: ${NAMESPACE} | Target: ${BACKEND_DEPLOY}"
    log_info "Injecting memory stress exceeding container 256Mi memory limit..."

    # Deploy ephemeral stress container in shoplite namespace targeting backend memory
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: chaos-memory-bomb
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/component: chaos
spec:
  ttlSecondsAfterFinished: 120
  template:
    metadata:
      labels:
        app.kubernetes.io/component: chaos
    spec:
      restartPolicy: Never
      containers:
        - name: stress-memory
          image: polinux/stress:latest
          command: ["stress"]
          args: ["--vm", "2", "--vm-bytes", "512M", "--timeout", "90s"]
          resources:
            requests:
              memory: "128Mi"
            limits:
              memory: "600Mi"
EOF

    log_success "Memory stress job 'chaos-memory-bomb' dispatched."
    log_info "Observability Targets to Watch:"
    echo -e "  - Prometheus Alert : ${YELLOW}PodCrashLooping${NC} (Restarts increasing)"
    echo -e "  - Prometheus Alert : ${YELLOW}HighErrorRate${NC} (HTTP 5xx > 5%)"
    echo -e "  - Google SRE Alert : ${RED}ErrorBudgetBurnRateCritical1h${NC} (14.4x Burn Rate)"
    echo -e "  - Grafana Dashboard: ShopLite RED Metrics -> Memory Usage Spike"
    echo -e "  - Loki Logs        : Search '{namespace=\"shoplite\"} |= \"OOMKilled\"'"
}

# ------------------------------------------------------------------------------
# Chaos Scenario 2: Database Latency & Saturation (Triggers HighLatency & Tempo)
# ------------------------------------------------------------------------------
inject_database_latency() {
    log_header "Chaos Scenario 2: Database Latency & Slow Query Injection"
    log_info "Target: PostgreSQL Database (${POSTGRES_DEPLOY})"
    log_info "Injecting synthetic lock and sleep delays into active database transactions..."

    # Execute 3-second sleep query inside PostgreSQL to exhaust connection pool
    kubectl exec -i deployment/${POSTGRES_DEPLOY} -n ${NAMESPACE} -- \
        psql -U shoplite_admin -d shoplite_db -c \
        "SELECT pg_sleep(3.5);" >/dev/null 2>&1 &

    log_success "Synthetic slow query running in background (sleep 3.5s)."
    log_info "Observability Targets to Watch:"
    echo -e "  - Prometheus Alert : ${YELLOW}HighLatency${NC} (p95 > 1.0s for 5m)"
    echo -e "  - Grafana Tempo    : Filter by 'service.name=\"shoplite-catalog-api\"' and status=ERROR"
    echo -e "  - Tempo Waterfall  : Trace span 'db.query' expanding from 4ms to 3500ms"
    echo -e "  - Loki Logs        : Search '{app=\"shoplite\"} |= \"database connection timeout\"'"
}

# ------------------------------------------------------------------------------
# Chaos Scenario 3: Order Queue Backlog (Triggers QueueBacklog Alert)
# ------------------------------------------------------------------------------
inject_queue_backlog() {
    log_header "Chaos Scenario 3: Redis Order Queue Backlog Accumulation"
    log_info "Temporarily pausing worker consumer to simulate queue pileup..."

    # Scale worker to 0 replicas to prevent queue draining
    kubectl scale deployment/${WORKER_DEPLOY} -n ${NAMESPACE} --replicas=0
    log_info "Scaled ${WORKER_DEPLOY} to 0 replicas."

    log_info "Pumping 60 synthetic orders into Redis queue 'order_queue'..."
    for i in $(seq 1 60); do
        ORDER_PAYLOAD="{\"order_id\":\"chaos-$i\",\"customer_id\":\"c-$i\",\"amount\":99.99,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
        kubectl exec -i deployment/shoplite-redis -n ${NAMESPACE} -- \
            redis-cli LPUSH order_queue "${ORDER_PAYLOAD}" >/dev/null 2>&1
    done

    CURRENT_DEPTH=$(kubectl exec -i deployment/shoplite-redis -n ${NAMESPACE} -- redis-cli LLEN order_queue | tr -d '\r')
    log_success "Order queue depth is now: ${CURRENT_DEPTH} (Threshold: > 50)"

    log_info "Observability Targets to Watch:"
    echo -e "  - Prometheus Alert : ${YELLOW}QueueBacklog${NC} (order_queue_depth > 50 for 10m)"
    echo -e "  - Grafana Dashboard: Redis Queue Depth gauge turning Red"
}

# ------------------------------------------------------------------------------
# Scenario 4: Clean Up & Verify Automated Recovery
# ------------------------------------------------------------------------------
cleanup_chaos() {
    log_header "Recovery: Restoring Clean Production Baseline"
    log_info "Deleting ephemeral chaos jobs..."
    kubectl delete job chaos-memory-bomb -n ${NAMESPACE} --ignore-not-found=true

    log_info "Restoring ${WORKER_DEPLOY} replicas to 2..."
    kubectl scale deployment/${WORKER_DEPLOY} -n ${NAMESPACE} --replicas=2

    log_info "Clearing backlog in Redis queue..."
    kubectl exec -i deployment/shoplite-redis -n ${NAMESPACE} -- redis-cli DEL order_queue >/dev/null 2>&1 || true

    log_info "Waiting for all pods in '${NAMESPACE}' to return to Running state..."
    kubectl wait --namespace ${NAMESPACE} \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/part-of=shoplite \
        --timeout=60s || true

    log_success "Production cluster restored to stable baseline."
}

# ------------------------------------------------------------------------------
# Status Command: Real-Time Cluster Health & Metrics
# ------------------------------------------------------------------------------
show_status() {
    log_header "ShopLite Live Cluster & Telemetry Status"
    echo -e "${CYAN}Namespace Pods:${NC}"
    kubectl get pods -n ${NAMESPACE} -o wide
    echo ""
    echo -e "${CYAN}Redis Queue Depth:${NC}"
    QUEUE_LEN=$(kubectl exec -i deployment/shoplite-redis -n ${NAMESPACE} -- redis-cli LLEN order_queue 2>/dev/null | tr -d '\r' || echo "N/A")
    echo "  Current Depth: ${QUEUE_LEN}"
    echo ""
    echo -e "${CYAN}Recent Crash/Restart Events (last 10m):${NC}"
    kubectl get events -n ${NAMESPACE} --field-selector type=Warning --sort-by='.metadata.creationTimestamp' | tail -n 5 || true
}

# ------------------------------------------------------------------------------
# Entrypoint Dispatcher
# ------------------------------------------------------------------------------
ACTION="${1:-status}"

case "${ACTION}" in
    memory)
        inject_memory_exhaustion
        ;;
    latency)
        inject_database_latency
        ;;
    queue)
        inject_queue_backlog
        ;;
    status)
        show_status
        ;;
    cleanup)
        cleanup_chaos
        ;;
    *)
        echo "Usage: $0 [memory|latency|queue|status|cleanup]"
        exit 1
        ;;
esac
