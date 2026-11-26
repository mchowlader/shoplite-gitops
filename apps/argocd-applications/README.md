# ArgoCD Applications (Pure GitOps App-of-Apps — Question 6 & Question 7.1c)

- [../root-app.yaml](../root-app.yaml): App-of-Apps root application that automatically reconciles every manifest below.
- [shoplite-dev.yaml](./shoplite-dev.yaml): Deploys `shoplite-app/helm/shoplite` with `envs/dev/values.yaml` into `shoplite-dev` with **automatic sync, prune, and self-healing**.
- [shoplite-prod.yaml](./shoplite-prod.yaml): Deploys `shoplite-app/helm/shoplite` with `envs/prod/values.yaml` into `shoplite` with **manual sync required** for production gating.
- [monitoring-kube-prometheus-stack.yaml](./monitoring-kube-prometheus-stack.yaml): Deploys `prometheus-community/kube-prometheus-stack` (`94.1.0`) into `monitoring` (Prometheus, Alertmanager, Grafana, exporters).
- [monitoring-loki.yaml](./monitoring-loki.yaml): Deploys `grafana/loki` (`7.7.0`) into `monitoring`.
- [monitoring-promtail.yaml](./monitoring-promtail.yaml): Deploys `grafana/promtail` (`6.17.1`) into `monitoring`.
- [monitoring-tempo.yaml](./monitoring-tempo.yaml): Deploys `grafana/tempo` (`1.24.4`) into `monitoring`.
- [monitoring-config.yaml](./monitoring-config.yaml): Deploys Kustomize bundle `shoplite-app/monitoring` (Grafana datasources, Golden Signals dashboard, ServiceMonitors, PrometheusRule alerts, Grafana Ingress).

Bootstrap command (also run automatically by `ansible/cluster-init.yml`):
```bash
kubectl apply -f https://raw.githubusercontent.com/mchowlader/shoplite-gitops/main/apps/root-app.yaml
```
