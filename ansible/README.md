# ⚙️ Ansible Configuration & Node Bootstrapping (Question 4.g)
**Assessment Rubric:** Question 4.g — Server Configuration Management & Kubernetes Bootstrapping (4.0 Marks)  
**Target Cluster:** 1 Control-Plane (`10.0.10.187`) + 2 Worker EC2 Nodes (`10.0.10.106`, `10.0.20.42`) across AWS Private Subnets

---

## 1. Directory Structure

```
shoplite-gitops/ansible/
├── ansible.cfg                 # Global Ansible engine settings, SSH multiplexing & privilege escalation
├── inventory/
│   └── hosts.ini               # Static inventory defining [control_plane] and [workers]
├── site.yml                    # Master driver playbook running Phase 1 & Phase 2
├── playbook.yml                # Phase 1: Server bootstrapping, runtimes, and Linux hardening
├── cluster-init.yml            # Phase 2: kubeadm init, Flannel CNI, and worker joining
├── run-ansible.sh              # Unified execution harness script
└── roles/
    ├── common/                 # Base OS updates, swapoff, kernel modules (overlay, br_netfilter), sysctl
    ├── containerd/             # Containerd.io installation, SystemdCgroup alignment
    ├── kubernetes/             # Official pkgs.k8s.io v1.30 packages (kubeadm, kubelet, kubectl) with dpkg hold
    └── hardening/              # OpenSSH hardening, sudoers RBAC, and daily PostgreSQL backup timer
```

---

## 2. Key Architectural Guarantees

1. **Idempotence:** Every task uses native Ansible modules (`apt`, `file`, `systemd`, `copy`, `replace`, `modprobe`) with change detection (`changed_when`), ensuring safe multi-run execution without server drift.
2. **Kubernetes CRI Alignment:** `containerd` config explicitly sets `SystemdCgroup = true` to align with modern `kubelet` cgroup management, preventing runtime split-brain crashes.
3. **Version Pinning & Protection:** `kubelet`, `kubeadm`, and `kubectl` are locked using `dpkg_selections: hold` to prevent uncontrolled nightly `unattended-upgrades` from violating cluster version skew policy.
4. **Defense-in-Depth Hardening:** Deploys Day 3's OpenSSH key-only rules (`99-shoplite.conf`), least-privilege `shoplite` user with visudo validation, and an automated systemd timer for PostgreSQL backups.

---

## 3. Execution Commands

```bash
# 1. Verify syntax
./run-ansible.sh check

# 2. Run Phase 1: Server bootstrapping & hardening
./run-ansible.sh bootstrap

# 3. Run Phase 2: Cluster initialization & worker join
./run-ansible.sh cluster

# 4. Or execute everything end-to-end
./run-ansible.sh all
```

---

## 4. Verification & Validation

After running the playbooks, verify node readiness from the Control-Plane node:
```bash
kubectl get nodes -o wide
```

Expected output:
```
NAME            STATUS   ROLES           AGE   VERSION   INTERNAL-IP   OS-IMAGE             KERNEL-VERSION
cp-node-1       Ready    control-plane   5m    v1.30.0   10.0.10.187   Ubuntu 24.04 LTS     6.8.0-aws
worker-node-1   Ready    <none>          3m    v1.30.0   10.0.10.106   Ubuntu 24.04 LTS     6.8.0-aws
worker-node-2   Ready    <none>          3m    v1.30.0   10.0.20.42    Ubuntu 24.04 LTS     6.8.0-aws
```
