#!/usr/bin/env bash
# ==============================================================================
# ShopLite: Master Observability Deployment Script (Question 6 - LGTM Stack)
# Automates the complete provisioning of:
#   1. Prometheus (Metrics & Alerting Rules)
#   2. Loki & Promtail (Log Aggregation & Container Log Shipping)
#   3. Tempo (Distributed Tracing Backend)
#   4. Grafana (Unified RED Metrics & Telemetry Dashboard)
# Target Namespace: observability
# ==============================================================================

set -euo pipefail

# ANSI Color Codes for readable output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Determine script root directory (allows running from anywhere)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="observability"

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
# Step 1: Ensure Target Namespace Exists
# ------------------------------------------------------------------------------
log_info "Ensuring '${NAMESPACE}' namespace exists..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
log_success "Namespace '${NAMESPACE}' ready."

# ------------------------------------------------------------------------------
# Step 2: Add and Update Required Helm Repositories
# ------------------------------------------------------------------------------
log_info "Adding official Helm chart repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo add grafana https://grafana.github.io/helm-charts --force-update
log_info "Updating Helm chart repositories..."
helm repo update
log_success "Helm repositories updated."

# ------------------------------------------------------------------------------
# Step 3: Deploy Prometheus & Alerting Rules
# ------------------------------------------------------------------------------
log_info "Deploying Prometheus server & node-exporter..."
helm upgrade --install shoplite-prometheus prometheus-community/prometheus \
    --namespace "${NAMESPACE}" \
    --values "${SCRIPT_DIR}/prometheus/prometheus-values.yaml" \
    --wait --timeout 300s
log_success "Prometheus deployed successfully."

log_info "Applying Prometheus Alerting Rules..."
kubectl apply -f "${SCRIPT_DIR}/prometheus/alerts.yaml" -n "${NAMESPACE}"
log_success "Alerting rules applied to '${NAMESPACE}'."

# ------------------------------------------------------------------------------
# Step 4: Deploy Grafana Loki (Log Aggregation Engine)
# ------------------------------------------------------------------------------
log_info "Deploying Grafana Loki (Single Binary Mode)..."
helm upgrade --install shoplite-loki grafana/loki \
    --namespace "${NAMESPACE}" \
    --values "${SCRIPT_DIR}/loki/loki-values.yaml" \
    --wait --timeout 300s
log_success "Loki deployed successfully."

# ------------------------------------------------------------------------------
# Step 5: Deploy Promtail (DaemonSet Log Shipper)
# ------------------------------------------------------------------------------
log_info "Deploying Promtail DaemonSet log collector..."
helm upgrade --install shoplite-promtail grafana/promtail \
    --namespace "${NAMESPACE}" \
    --values "${SCRIPT_DIR}/loki/promtail-values.yaml" \
    --wait --timeout 180s
log_success "Promtail DaemonSet deployed to all cluster nodes."

# ------------------------------------------------------------------------------
# Step 6: Deploy Grafana Tempo (Distributed Tracing)
# ------------------------------------------------------------------------------
log_info "Deploying Grafana Tempo tracing engine..."
helm upgrade --install shoplite-tempo grafana/tempo \
    --namespace "${NAMESPACE}" \
    --values "${SCRIPT_DIR}/tempo/tempo-values.yaml" \
    --wait --timeout 180s
log_success "Tempo deployed successfully."

# ------------------------------------------------------------------------------
# Step 7: Provision Grafana ConfigMaps (Datasources & Dashboards)
# ------------------------------------------------------------------------------
log_info "Provisioning Grafana Datasource configuration..."
kubectl create configmap grafana-datasources \
    --from-file=datasources.yaml="${SCRIPT_DIR}/grafana/datasources.yaml" \
    --namespace "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

log_info "Provisioning Grafana Dashboard Provider..."
kubectl create configmap grafana-dashboard-provider \
    --from-file=dashboard-provider.yaml="${SCRIPT_DIR}/grafana/dashboards/dashboard-provider.yaml" \
    --namespace "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

log_info "Provisioning ShopLite RED Metrics Dashboard..."
kubectl create configmap grafana-shoplite-dashboard \
    --from-file=shoplite-overview.json="${SCRIPT_DIR}/grafana/dashboards/shoplite-overview.json" \
    --namespace "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
log_success "Grafana ConfigMaps created."

# ------------------------------------------------------------------------------
# Step 8: Deploy Grafana (Unified Visualizer)
# ------------------------------------------------------------------------------
log_info "Deploying Grafana with auto-mounted Datasources & Dashboards..."
helm upgrade --install shoplite-grafana grafana/grafana \
    --namespace "${NAMESPACE}" \
    --set adminPassword="admin" \
    --set persistence.enabled=false \
    --set "extraConfigMapMounts[0].name=datasources" \
    --set "extraConfigMapMounts[0].mountPath=/etc/grafana/provisioning/datasources/datasources.yaml" \
    --set "extraConfigMapMounts[0].subPath=datasources.yaml" \
    --set "extraConfigMapMounts[0].configMap=grafana-datasources" \
    --set "extraConfigMapMounts[0].readOnly=true" \
    --set "extraConfigMapMounts[1].name=dashboard-provider" \
    --set "extraConfigMapMounts[1].mountPath=/etc/grafana/provisioning/dashboards/dashboard-provider.yaml" \
    --set "extraConfigMapMounts[1].subPath=dashboard-provider.yaml" \
    --set "extraConfigMapMounts[1].configMap=grafana-dashboard-provider" \
    --set "extraConfigMapMounts[1].readOnly=true" \
    --set "extraConfigMapMounts[2].name=shoplite-dashboard" \
    --set "extraConfigMapMounts[2].mountPath=/var/lib/grafana/dashboards/shoplite-overview.json" \
    --set "extraConfigMapMounts[2].subPath=shoplite-overview.json" \
    --set "extraConfigMapMounts[2].configMap=grafana-shoplite-dashboard" \
    --set "extraConfigMapMounts[2].readOnly=true" \
    --wait --timeout 300s
log_success "Grafana deployed successfully."

# ------------------------------------------------------------------------------
# Step 9: Summary & Verification
# ------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN} 🎉 Full LGTM Observability Stack Deployed Successfully!${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo ""
log_info "Current Pods in namespace '${NAMESPACE}':"
kubectl get pods -n "${NAMESPACE}" -o wide
echo ""
log_info "To access Grafana locally, run:"
echo -e "  ${YELLOW}kubectl port-forward svc/shoplite-grafana 3000:80 -n ${NAMESPACE}${NC}"
echo -e "  URL: ${BLUE}http://localhost:3000${NC} (User: ${YELLOW}admin${NC} / Password: ${YELLOW}admin${NC})"
echo ""
