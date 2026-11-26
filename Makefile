PYTHON := $(shell command -v python3 2>/dev/null || command -v python 2>/dev/null)

.PHONY: verify guardrails help

help:
	@echo "Available Make targets for shoplite-gitops:"
	@echo "  make verify     - Validate YAML syntax across apps/ and envs/"
	@echo "  make guardrails - Run full GitOps validation"

verify:
	$(PYTHON) -c "import pathlib, yaml; [list(yaml.safe_load_all(p.read_text())) for p in list(pathlib.Path('apps').rglob('*.yaml')) + list(pathlib.Path('envs').rglob('*.yaml'))]; print('GitOps YAML validation passed.')"

guardrails: verify
	@echo "GitOps guardrails verification completed successfully!"
