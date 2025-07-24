#!/bin/bash

# n8n PostgreSQL Backup Script
# This script backs up the n8n PostgreSQL database to S3

set -euo pipefail

# Configuration from environment
NAMESPACE="${NAMESPACE:-unknown}"
S3_BUCKET="${S3_BUCKET}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PREFIX="backups/${NAMESPACE}"
BACKUP_FILE="n8n_backup_${NAMESPACE}_${TIMESTAMP}.sql"
TEMP_DIR="/tmp"
LOG_FILE="/var/log/n8n-backup.log"
RETENTION_DAYS=30

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handler
error_handler() {
    log "ERROR: Backup failed at line $1"
    exit 1
}

trap 'error_handler $LINENO' ERR

# Start backup process
log "Starting backup for namespace: ${NAMESPACE}"

# Change to n8n directory
cd /home/n8n/n8n-aws-self-hosting || exit 1

# Check if PostgreSQL container is running
if ! docker compose ps postgres | grep -q "running"; then
    log "ERROR: PostgreSQL container is not running"
    exit 1
fi

# Perform database dump
log "Creating PostgreSQL dump..."
docker compose exec -T postgres pg_dump -U n8n -d n8n --clean --if-exists > "${TEMP_DIR}/${BACKUP_FILE}"

# Check if dump was successful
if [ ! -s "${TEMP_DIR}/${BACKUP_FILE}" ]; then
    log "ERROR: Database dump is empty"
    exit 1
fi

# Get dump size for logging
DUMP_SIZE=$(du -h "${TEMP_DIR}/${BACKUP_FILE}" | cut -f1)
log "Database dump created successfully (${DUMP_SIZE})"

# Compress the backup
log "Compressing backup..."
gzip "${TEMP_DIR}/${BACKUP_FILE}"
BACKUP_FILE="${BACKUP_FILE}.gz"

# Get compressed size
COMPRESSED_SIZE=$(du -h "${TEMP_DIR}/${BACKUP_FILE}" | cut -f1)
log "Backup compressed successfully (${COMPRESSED_SIZE})"

# Upload to S3
log "Uploading backup to S3..."
aws s3 cp "${TEMP_DIR}/${BACKUP_FILE}" "s3://${S3_BUCKET}/${BACKUP_PREFIX}/${BACKUP_FILE}" \
    --storage-class STANDARD_IA \
    --metadata "namespace=${NAMESPACE},timestamp=${TIMESTAMP}"

if [ $? -eq 0 ]; then
    log "Backup uploaded successfully to s3://${S3_BUCKET}/${BACKUP_PREFIX}/${BACKUP_FILE}"
else
    log "ERROR: Failed to upload backup to S3"
    exit 1
fi

# Clean up local file
rm -f "${TEMP_DIR}/${BACKUP_FILE}"

# Retention policy - delete backups older than RETENTION_DAYS
log "Applying retention policy (${RETENTION_DAYS} days)..."
CUTOFF_DATE=$(date -d "${RETENTION_DAYS} days ago" +%Y%m%d)

# List and delete old backups
aws s3 ls "s3://${S3_BUCKET}/${BACKUP_PREFIX}/" | while read -r line; do
    FILE_DATE=$(echo "$line" | awk '{print $4}' | grep -oE '[0-9]{8}' || true)
    FILE_NAME=$(echo "$line" | awk '{print $4}')
    
    if [ ! -z "$FILE_DATE" ] && [ "$FILE_DATE" -lt "$CUTOFF_DATE" ]; then
        log "Deleting old backup: ${FILE_NAME}"
        aws s3 rm "s3://${S3_BUCKET}/${BACKUP_PREFIX}/${FILE_NAME}"
    fi
done

# List current backups
BACKUP_COUNT=$(aws s3 ls "s3://${S3_BUCKET}/${BACKUP_PREFIX}/" | wc -l)
log "Backup completed successfully. Total backups: ${BACKUP_COUNT}"

# Send CloudWatch metric
aws cloudwatch put-metric-data \
    --namespace "n8n/${NAMESPACE}" \
    --metric-name BackupSuccess \
    --value 1 \
    --timestamp "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" || true

exit 0