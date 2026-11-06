#!/usr/bin/env bash
# ==============================================================================
# ShopLite: Automated PostgreSQL Backup Script
# - Dumps database via running container
# - Gzip maximum compression
# - SHA256 integrity checksum generation
# - 7-day automatic rotation / cleanup
# ==============================================================================
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/shoplite}"
CONTAINER_NAME="${CONTAINER_NAME:-shoplite-postgres}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-shoplite_db}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"

# Optional 100% Free Discord Webhook Alert Helper
notify_discord() {
    local status="$1"
    local message="$2"
    if [ -n "${DISCORD_WEBHOOK_URL}" ]; then
        local color=5763719 # Green
        [ "${status}" != "SUCCESS" ] && color=15548997 # Red
        local payload="{\"embeds\": [{\"title\": \"ShopLite DB Backup: ${status}\", \"description\": \"${message}\", \"color\": ${color}, \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]}"
        curl -s -H "Content-Type: application/json" -X POST -d "${payload}" "${DISCORD_WEBHOOK_URL}" >/dev/null 2>&1 || true
    fi
}

trap 'notify_discord "CRITICAL_FAILURE" "PostgreSQL backup job failed unexpectedly! Check system logs."' ERR

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
FILENAME="${DB_NAME}_${TIMESTAMP}.sql.gz"
TARGET="${BACKUP_DIR}/${FILENAME}"

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

echo "[INFO] Starting database backup for '${DB_NAME}' from container '${CONTAINER_NAME}'..."

# Verify docker container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[ERROR] Container '${CONTAINER_NAME}' is not running!" >&2
    exit 1
fi

# Execute dump and pipe through gzip
docker exec "${CONTAINER_NAME}" pg_dump -U "${DB_USER}" "${DB_NAME}" | gzip -9 > "${TARGET}"
chmod 600 "${TARGET}"

# Generate checksum
sha256sum "${TARGET}" > "${TARGET}.sha256"

# Cleanup old backups
DELETED_COUNT=$(find "${BACKUP_DIR}" -type f -name "${DB_NAME}_*.sql.gz*" -mtime +"${RETENTION_DAYS}" -delete -print | wc -l)

BACKUP_SIZE=$(du -h "${TARGET}" | cut -f1)
echo "[SUCCESS] Backup created successfully: ${TARGET} (${BACKUP_SIZE})"
echo "[INFO] Cleaned up ${DELETED_COUNT} file(s) older than ${RETENTION_DAYS} days."

notify_discord "SUCCESS" "Backup created: \`${FILENAME}\` (${BACKUP_SIZE}). Rotated ${DELETED_COUNT} old files."

