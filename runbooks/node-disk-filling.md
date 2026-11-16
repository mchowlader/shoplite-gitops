# Runbook: NodeDiskFilling (Severity: Warning)

## Alert Details
- **Condition:** Disk usage exceeds 85%.
- **Impact:** Pod eviction, disk write failures, database write stalls.

## Diagnostic Steps
1. **Identify High Disk Usage Node:**
   ```bash
   kubectl get nodes -o wide
   df -h
   ```
2. **Find Directory Consuming Most Space:**
   ```bash
   du -sh /var/lib/docker /var/lib/containerd /var/log/* 2>/dev/null | sort -hr | head -n 10
   ```
3. **Clean Up Unused Container Artifacts:**
   ```bash
   crictl rmi --prune
   journalctl --vacuum-time=2d
   ```

## Mitigation
- Prune unused images and vacuum logs.
- If persistent, expand AWS EBS volume size via Terraform / AWS Console and execute `sudo growpart /dev/nvme0n1 1 && sudo resize2fs /dev/nvme0n1p1`.
