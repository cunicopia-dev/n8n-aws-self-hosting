#!/bin/bash

# n8n PostgreSQL Restore Script
# This script restores an n8n PostgreSQL database from S3

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-unknown}"
S3_BUCKET="${S3_BUCKET}"
BACKUP_PREFIX="backups/${NAMESPACE}"
TEMP_DIR="/tmp"
LOG_FILE="/var/log/n8n-restore.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Usage function
usage() {
    echo "Usage: $0 [backup_file_name]"
    echo "If no backup file is specified, lists available backups"
    echo ""
    echo "Examples:"
    echo "  $0                    # List available backups"
    echo "  $0 n8n_backup_${NAMESPACE}_20240101_020000.sql.gz"
    exit 1
}

# List available backups
list_backups() {
    log "Available backups for namespace ${NAMESPACE}:"
    aws s3 ls "s3://${S3_BUCKET}/${BACKUP_PREFIX}/" | grep -E '\.sql\.gz$' | sort -r | head -20
}

# Main restore function
restore_backup() {
    local BACKUP_FILE="$1"
    
    log "Starting restore for namespace: ${NAMESPACE}"
    log "Backup file: ${BACKUP_FILE}"
    
    # Download backup from S3
    log "Downloading backup from S3..."
    aws s3 cp "s3://${S3_BUCKET}/${BACKUP_PREFIX}/${BACKUP_FILE}" "${TEMP_DIR}/${BACKUP_FILE}"
    
    if [ ! -f "${TEMP_DIR}/${BACKUP_FILE}" ]; then
        log "ERROR: Failed to download backup file"
        exit 1
    fi
    
    # Decompress backup
    log "Decompressing backup..."
    gunzip -c "${TEMP_DIR}/${BACKUP_FILE}" > "${TEMP_DIR}/${BACKUP_FILE%.gz}"
    
    # Change to n8n directory
    cd /home/n8n/n8n-aws-self-hosting || exit 1
    
    # Confirm restore
    echo ""
    echo "WARNING: This will overwrite the current n8n database!"
    echo "All existing workflows and credentials will be replaced."
    read -p "Are you sure you want to continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        log "Restore cancelled by user"
        exit 0
    fi
    
    # Stop n8n container
    log "Stopping n8n container..."
    docker compose stop n8n
    
    # Ensure PostgreSQL is running
    docker compose up -d postgres
    sleep 5
    
    # Perform restore
    log "Restoring database..."
    docker compose exec -T postgres psql -U n8n -d n8n < "${TEMP_DIR}/${BACKUP_FILE%.gz}"
    
    if [ $? -eq 0 ]; then
        log "Database restored successfully"
    else
        log "ERROR: Database restore failed"
        exit 1
    fi
    
    # Restart n8n
    log "Starting n8n container..."
    docker compose up -d n8n
    
    # Clean up temporary files
    rm -f "${TEMP_DIR}/${BACKUP_FILE}" "${TEMP_DIR}/${BACKUP_FILE%.gz}"
    
    log "Restore completed successfully"
    echo ""
    echo "n8n has been restored from backup: ${BACKUP_FILE}"
    echo "Please verify your workflows and credentials are working correctly."
}

# Main logic
if [ $# -eq 0 ]; then
    # No arguments - list backups
    list_backups
    echo ""
    echo "To restore a backup, run: $0 <backup_file_name>"
elif [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    usage
else
    # Restore specified backup
    restore_backup "$1"
fi