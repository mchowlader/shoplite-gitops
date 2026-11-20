#!/usr/bin/env bash
# ==============================================================================
# ShopLite: Automated Ansible Execution Harness (Question 4.g)
# Usage: ./run-ansible.sh [check|bootstrap|cluster|all]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

MODE="${1:-all}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}===================================================================${NC}"
echo -e "${BLUE}  ShopLite Ansible Automation Suite — Mode: ${MODE}                ${NC}"
echo -e "${BLUE}===================================================================${NC}"

# Check Ansible installation; auto-install if missing
if ! command -v ansible-playbook &>/dev/null; then
    echo -e "${YELLOW}[INFO] ansible-playbook not found. Installing Ansible automatically...${NC}"
    sudo apt-get update -y
    sudo apt-get install -y ansible
    echo -e "${GREEN}[SUCCESS] Ansible installed successfully!${NC}"
fi

case "${MODE}" in
    check)
        echo -e "${GREEN}[INFO] Verifying Playbook Syntaxes...${NC}"
        ansible-playbook -i inventory/hosts.ini playbook.yml --syntax-check
        ansible-playbook -i inventory/hosts.ini cluster-init.yml --syntax-check
        echo -e "${GREEN}[SUCCESS] All playbooks passed syntax check!${NC}"
        ;;
    bootstrap)
        echo -e "${GREEN}[INFO] Running Phase 1: Server Bootstrapping & Hardening...${NC}"
        ansible-playbook -i inventory/hosts.ini playbook.yml
        ;;
    cluster)
        echo -e "${GREEN}[INFO] Running Phase 2: Kubernetes Cluster Initialization...${NC}"
        ansible-playbook -i inventory/hosts.ini cluster-init.yml
        ;;
    all)
        echo -e "${GREEN}[INFO] Running Complete End-to-End Site Automation...${NC}"
        ansible-playbook -i inventory/hosts.ini site.yml
        ;;
    *)
        echo "Usage: $0 [check|bootstrap|cluster|all]"
        exit 1
        ;;
esac

echo -e "${GREEN}===================================================================${NC}"
echo -e "${GREEN}  Automation Complete!                                             ${NC}"
echo -e "${GREEN}===================================================================${NC}"

