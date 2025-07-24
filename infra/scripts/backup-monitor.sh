#!/bin/bash

# n8n Backup Monitor Script
# This script checks backup health and sends alerts

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-unknown}"
S3_BUCKET="${S3_BUCKET}"
BACKUP_PREFIX="backups/${NAMESPACE}"
WARNING_HOURS=26  # Alert if no backup in 26 hours
CRITICAL_HOURS=48 # Critical alert if no backup in 48 hours
LOG_FILE="/var/log/n8n-backup-monitor.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check latest backup
check_backup_health() {
    log "Checking backup health for namespace: ${NAMESPACE}"
    
    # Get latest backup
    LATEST_BACKUP=$(aws s3 ls "s3://${S3_BUCKET}/${BACKUP_PREFIX}/" | grep -E '\.sql\.gz$' | sort | tail -1)
    
    if [ -z "$LATEST_BACKUP" ]; then
        log "CRITICAL: No backups found for namespace ${NAMESPACE}"
        send_metric 0 "Critical"
        return 1
    fi
    
    # Extract timestamp from backup filename
    BACKUP_DATE=$(echo "$LATEST_BACKUP" | awk '{print $1 " " $2}')
    BACKUP_NAME=$(echo "$LATEST_BACKUP" | awk '{print $4}')
    BACKUP_TIMESTAMP=$(echo "$BACKUP_NAME" | grep -oE '[0-9]{8}_[0-9]{6}' || echo "")
    
    if [ -z "$BACKUP_TIMESTAMP" ]; then
        log "ERROR: Cannot parse backup timestamp from ${BACKUP_NAME}"
        return 1
    fi
    
    # Convert to epoch
    BACKUP_EPOCH=$(date -d "$(echo $BACKUP_TIMESTAMP | sed 's/_/ /' | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3/')" +%s)
    CURRENT_EPOCH=$(date +%s)
    HOURS_OLD=$(( ($CURRENT_EPOCH - $BACKUP_EPOCH) / 3600 ))
    
    log "Latest backup: ${BACKUP_NAME} (${HOURS_OLD} hours old)"
    
    # Check backup age
    if [ $HOURS_OLD -gt $CRITICAL_HOURS ]; then
        log "CRITICAL: Latest backup is ${HOURS_OLD} hours old (threshold: ${CRITICAL_HOURS})"
        send_metric 0 "Critical"
        return 1
    elif [ $HOURS_OLD -gt $WARNING_HOURS ]; then
        log "WARNING: Latest backup is ${HOURS_OLD} hours old (threshold: ${WARNING_HOURS})"
        send_metric 1 "Warning"
        return 0
    else
        log "OK: Backup is current (${HOURS_OLD} hours old)"
        send_metric 2 "Ok"
        return 0
    fi
}

# Send CloudWatch metric
send_metric() {
    local VALUE=$1
    local STATUS=$2
    
    aws cloudwatch put-metric-data \
        --namespace "n8n/${NAMESPACE}" \
        --metric-name BackupHealth \
        --value "$VALUE" \
        --dimensions Status="$STATUS" \
        --timestamp "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" || true
}

# Get backup statistics
get_backup_stats() {
    log "Gathering backup statistics..."
    
    # Count backups
    BACKUP_COUNT=$(aws s3 ls "s3://${S3_BUCKET}/${BACKUP_PREFIX}/" | grep -E '\.sql\.gz$' | wc -l)
    
    # Calculate total size
    TOTAL_SIZE=$(aws s3 ls "s3://${S3_BUCKET}/${BACKUP_PREFIX}/" --summarize --human-readable | grep "Total Size" | awk '{print $3 " " $4}')
    
    log "Total backups: ${BACKUP_COUNT}"
    log "Total size: ${TOTAL_SIZE}"
    
    # Send metrics
    aws cloudwatch put-metric-data \
        --namespace "n8n/${NAMESPACE}" \
        --metric-name BackupCount \
        --value "$BACKUP_COUNT" \
        --timestamp "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" || true
}

# Main execution
log "=== Starting backup health check ==="
check_backup_health
get_backup_stats
log "=== Backup health check completed ===