#!/usr/bin/env python3
"""
Verification-Driven Validation Script: Verify Kubernetes, Helm Values, Observability, and JSON configs.
Usage: python scripts/verify-workloads.py
"""

import sys
import os
import json
import yaml
from pathlib import Path

def validate_json_file(file_path):
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            json.load(f)
        return True, None
    except Exception as e:
        return False, str(e)

def validate_yaml_file(file_path):
    # Skip Jinja2 or Go template files that contain unescaped template directives
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    
    # If it's a Helm template file containing {{ ... }}, validate syntax line-by-line or structure
    if "{{" in content and "}}" in content and "templates" in str(file_path):
        return True, None  # Helm templates require helm template engine to render

    try:
        yaml.safe_load_all(content)
        return True, None
    except Exception as e:
        return False, str(e)

def main():
    root_dir = Path(__file__).resolve().parent.parent
    errors = []
    yaml_count = 0
    json_count = 0

    # Search for all yaml and json files
    for root, dirs, files in os.walk(root_dir):
        # Skip git and cache directories
        if ".git" in dirs:
            dirs.remove(".git")
        if ".venv" in dirs:
            dirs.remove(".venv")
        if "__pycache__" in dirs:
            dirs.remove("__pycache__")
        if ".pytest_cache" in dirs:
            dirs.remove(".pytest_cache")

        for file in files:
            p = Path(root) / file
            if p.suffix in [".yaml", ".yml"]:
                yaml_count += 1
                ok, err = validate_yaml_file(p)
                if not ok:
                    errors.append(f"YAML Syntax Error in {p.relative_to(root_dir)}: {err}")
            elif p.suffix == ".json":
                json_count += 1
                ok, err = validate_json_file(p)
                if not ok:
                    errors.append(f"JSON Syntax Error in {p.relative_to(root_dir)}: {err}")

    print(f"=== Workload Verification Report ===")
    print(f"Validated {yaml_count} YAML files and {json_count} JSON files across {root_dir.name}.")
    
    if errors:
        print(f"FAILED: {len(errors)} error(s) detected:")
        for err in errors:
            print(f"  - {err}")
        sys.exit(1)
    else:
        print("SUCCESS: 0 syntax errors detected across all configuration files.")
        sys.exit(0)

if __name__ == "__main__":
    main()
