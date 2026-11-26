# shoplite-gitops

Declarative GitOps repository for **ShopLite (`DEVOPS-CAP-601`)** containing ArgoCD `Application` definitions (`apps/argocd-applications/`) and environment-specific Helm value overrides (`envs/dev/values.yaml`, `envs/prod/values.yaml`).

The canonical Helm chart, Terraform modules, Ansible playbooks, application source, and monitoring stack live in [`shoplite-app`](https://github.com/mchowlader/shoplite-app). ArgoCD uses multi-source composition so there is zero duplication between repositories.
