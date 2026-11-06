#!/usr/bin/env bash
# ==============================================================================
# ShopLite: Linux Host Hardening & Systemd Automation Setup Script
# Task 3: Linux Administration & Security (12.5 Marks)
# ==============================================================================
set -euo pipefail

echo "=========================================================="
echo "      ShopLite Linux Hardening & Security Setup           "
echo "=========================================================="

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Please run this script with sudo or as root." >&2
    exit 1
fi

# 1. Create Dedicated Service User
echo "[1/5] Ensuring 'shoplite' user & group exist..."
if ! id -u shoplite &>/dev/null; then
    if ! getent passwd 1001 &>/dev/null; then
        groupadd -g 1001 shoplite 2>/dev/null || groupadd shoplite
        useradd -u 1001 -g shoplite -m -s /bin/bash shoplite
    else
        useradd -m -s /bin/bash shoplite
    fi
    echo "[OK] Created user 'shoplite' (UID: $(id -u shoplite))."
else
    echo "[INFO] User 'shoplite' already exists (UID: $(id -u shoplite))."
fi

# 2. Configure Least-Privilege Sudoers Drop-in
echo "[2/5] Configuring restricted sudo privileges..."
cat << 'EOF' > /etc/sudoers.d/shoplite
shoplite ALL=(ALL) NOPASSWD: /usr/bin/systemctl start shoplite-backup, /usr/bin/systemctl start shoplite-backup.service, /usr/bin/systemctl status shoplite-backup, /usr/bin/systemctl status shoplite-backup.service, /usr/bin/systemctl restart shoplite-backup, /usr/bin/systemctl restart shoplite-backup.service, /usr/bin/journalctl -u shoplite-backup, /usr/bin/journalctl -u shoplite-backup.service
EOF
chmod 0440 /etc/sudoers.d/shoplite
visudo -c -f /etc/sudoers.d/shoplite
echo "[OK] Sudoers drop-in configured at /etc/sudoers.d/shoplite."

# 3. Deploy OpenSSH Hardening Configuration
echo "[3/5] Applying OpenSSH hardening configuration..."
mkdir -p /etc/ssh/sshd_config.d
cp "$(dirname "$0")/sshd_shoplite.conf" /etc/ssh/sshd_config.d/99-shoplite.conf
chmod 0644 /etc/ssh/sshd_config.d/99-shoplite.conf
if sshd -t; then
    echo "[OK] OpenSSH configuration syntax validated."
else
    echo "[WARN] sshd configuration test failed. Reverting..."
    rm -f /etc/ssh/sshd_config.d/99-shoplite.conf
fi

# 4. Install PostgreSQL Backup Script & Systemd Units
echo "[4/5] Installing automated backup script and systemd units..."
mkdir -p /opt/shoplite/scripts /var/backups/shoplite
cp "$(dirname "$0")/backup-postgres.sh" /opt/shoplite/scripts/backup-postgres.sh
chmod 0750 /opt/shoplite/scripts/backup-postgres.sh
chown -R root:shoplite /opt/shoplite
chmod 0700 /var/backups/shoplite

cp "$(dirname "$0")/shoplite-backup.service" /etc/systemd/system/
cp "$(dirname "$0")/shoplite-backup.timer" /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now shoplite-backup.timer
echo "[OK] shoplite-backup.timer is active and scheduled."

# 5. Configure Strict UFW Firewall Rules
echo "[5/5] Configuring UFW firewall rules..."
if command -v ufw &>/dev/null; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw limit 22/tcp comment 'SSH rate-limited'
    ufw allow 80/tcp comment 'HTTP ShopLite Web'
    ufw allow 443/tcp comment 'HTTPS Edge'
    echo "[OK] UFW rules configured (run 'sudo ufw enable' to activate)."
else
    echo "[INFO] UFW not installed on host. Skipping firewall activation."
fi

echo "=========================================================="
echo "✅ Day 3 Linux Hardening & Security Setup Complete!"
echo "=========================================================="

