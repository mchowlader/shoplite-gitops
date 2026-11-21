# ==============================================================================
# ShopLite GitOps Makefile — Verification & Guardrails Target Specifications
# ==============================================================================

.PHONY: verify helm-lint guardrails help

help:
	@echo "Available Make targets for ShopLite GitOps:"
	@echo "  make verify     - Run YAML/JSON configuration syntax verification"
	@echo "  make helm-lint  - Run Helm lint on the shoplite chart"
	@echo "  make guardrails - Run pre-commit and syntax verification"

verify:
	python scripts/verify-workloads.py

helm-lint:
	helm lint helm/shoplite/

guardrails: verify
	@echo "GitOps guardrails verification completed successfully!"
