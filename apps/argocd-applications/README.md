# ArgoCD Applications (`DEVOPS-CAP-601` Question 7.1c)

- [shoplite-dev.yaml](./shoplite-dev.yaml): Deploys `shoplite-app/helm/shoplite` with `envs/dev/values.yaml` into `shoplite-dev` with **automatic sync, prune, and self-healing**.
- [shoplite-prod.yaml](./shoplite-prod.yaml): Deploys `shoplite-app/helm/shoplite` with `envs/prod/values.yaml` into `shoplite` with **manual sync required** for production gating.

```bash
kubectl apply -f apps/argocd-applications/
```
