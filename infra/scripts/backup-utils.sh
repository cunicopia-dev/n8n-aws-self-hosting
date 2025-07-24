#!/bin/bash

# n8n Backup Utilities
# Helper commands for managing backups

set -euo pipefail

NAMESPACE="${NAMESPACE:-unknown}"
S3_BUCKET="${S3_BUCKET}"
BACKUP_PREFIX="backups/${NAMESPACE}"

usage() {
    cat << EOF
n8n Backup Utilities

Usage: $0 <command> [options]

Commands:
  list                    List all available backups
  latest                  Show latest backup information
  backup-now              Create a backup immediately
  status                  Show backup system status
  retention <days>        Set retention policy (default: 30 days)
  test-restore <file>     Test restore (dry run) from backup file
  logs                    Show backup logs

Examples:
  $0 list
  $0 backup-now
  $0 test-restore n8n_backup_${NAMESPACE}_20240101_020000.sql.gz
  $0 retention 45

EOF
    exit 1
}

list_backups() {
    echo "Available backups for namespace: ${NAMESPACE}"
    echo "=========================================="
    aws s3 ls "s3://${S3_BUCKET}/${BACKUP_PREFIX}/" | grep -E '\.sql\.gz$' | \
    while read -r date time size file; do
        # Extract timestamp from filename
        timestamp=$(echo "$file" | grep -oE '[0-9]{8}_[0-9]{6}' || echo "unknown")
        if [ "$timestamp" != "unknown" ]; then
            formatted_date=$(echo "$timestamp" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
            echo "$formatted_date  $size  $file"
        else
            echo "$date $time  $size  $file"
        fi
    done | sort -r
}

latest_backup() {
    echo "Latest backup for namespace: ${NAMESPACE}"
    echo "==============================="
    latest=$(aws s3 ls "s3://${S3_BUCKET}/${BACKUP_PREFIX}/" | grep -E '\.sql\.gz$' | sort | tail -1)
    
    if [ -z "$latest" ]; then
        echo "No backups found"
        return 1
    fi
    
    date=$(echo "$latest" | awk '{print $1}')
    time=$(echo "$latest" | awk '{print $2}')
    size=$(echo "$latest" | awk '{print $3}')
    file=$(echo "$latest" | awk '{print $4}')
    
    echo "File: $file"
    echo "Date: $date $time"
    echo "Size: $size"
    
    # Calculate age
    timestamp=$(echo "$file" | grep -oE '[0-9]{8}_[0-9]{6}' || echo "")
    if [ ! -z "$timestamp" ]; then
        backup_epoch=$(date -d "$(echo $timestamp | sed 's/_/ /' | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3/')" +%s 2>/dev/null || echo "0")
        current_epoch=$(date +%s)
        if [ "$backup_epoch" != "0" ]; then
            hours_old=$(( ($current_epoch - $backup_epoch) / 3600 ))
            echo "Age: $hours_old hours"
        fi
    fi
}

backup_now() {
    echo "Creating backup now..."
    /opt/n8n-scripts/backup-n8n.sh
}

show_status() {
    echo "n8n Backup System Status"
    echo "========================"
    echo "Namespace: $NAMESPACE"
    echo "S3 Bucket: $S3_BUCKET"
    echo "Backup Path: s3://${S3_BUCKET}/${BACKUP_PREFIX}/"
    echo ""
    
    # Check if scripts exist
    echo "Script Status:"
    [ -f "/opt/n8n-scripts/backup-n8n.sh" ] && echo "✓ Backup script installed" || echo "✗ Backup script missing"
    [ -f "/opt/n8n-scripts/restore-n8n.sh" ] && echo "✓ Restore script installed" || echo "✗ Restore script missing"
    [ -f "/opt/n8n-scripts/backup-monitor.sh" ] && echo "✓ Monitor script installed" || echo "✗ Monitor script missing"
    echo ""
    
    # Check cron jobs
    echo "Cron Jobs:"
    if crontab -u n8n -l 2>/dev/null | grep -q backup-n8n.sh; then
        echo "✓ Daily backup scheduled"
    else
        echo "✗ Daily backup not scheduled"
    fi
    
    if crontab -u n8n -l 2>/dev/null | grep -q backup-monitor.sh; then
        echo "✓ Backup monitoring scheduled"
    else
        echo "✗ Backup monitoring not scheduled"
    fi
    echo ""
    
    # Show backup count
    count=$(aws s3 ls "s3://${S3_BUCKET}/${BACKUP_PREFIX}/" | grep -E '\.sql\.gz$' | wc -l)
    echo "Total Backups: $count"
    
    if [ $count -gt 0 ]; then
        latest_backup
    fi
}

test_restore() {
    local backup_file="$1"
    echo "Testing restore from: $backup_file"
    echo "=================================="
    
    # Check if backup exists
    if ! aws s3 ls "s3://${S3_BUCKET}/${BACKUP_PREFIX}/${backup_file}" > /dev/null; then
        echo "ERROR: Backup file not found in S3"
        return 1
    fi
    
    # Download and test
    echo "✓ Backup file exists in S3"
    
    temp_file="/tmp/test_restore_$$"
    aws s3 cp "s3://${S3_BUCKET}/${BACKUP_PREFIX}/${backup_file}" "$temp_file"
    
    if [ -f "$temp_file" ]; then
        echo "✓ Successfully downloaded backup"
        
        # Test gunzip
        if gunzip -t "$temp_file" 2>/dev/null; then
            echo "✓ Backup file is valid gzip format"
        else
            echo "✗ Backup file is corrupted"
            rm -f "$temp_file"
            return 1
        fi
        
        # Test SQL content
        if gunzip -c "$temp_file" | head -10 | grep -q "PostgreSQL database dump"; then
            echo "✓ Backup contains valid PostgreSQL dump"
        else
            echo "⚠ Warning: Backup may not be a valid PostgreSQL dump"
        fi
        
        rm -f "$temp_file"
        echo "✓ Test completed successfully"
    else
        echo "✗ Failed to download backup"
        return 1
    fi
}

show_logs() {
    echo "Recent backup logs:"
    echo "=================="
    if [ -f "/var/log/n8n-backup.log" ]; then
        tail -20 /var/log/n8n-backup.log
    else
        echo "No backup logs found"
    fi
}

# Main command processing
case "${1:-}" in
    list)
        list_backups
        ;;
    latest)
        latest_backup
        ;;
    backup-now)
        backup_now
        ;;
    status)
        show_status
        ;;
    test-restore)
        if [ $# -lt 2 ]; then
            echo "Error: Please specify backup file"
            echo "Usage: $0 test-restore <backup_file>"
            exit 1
        fi
        test_restore "$2"
        ;;
    logs)
        show_logs
        ;;
    *)
        usage
        ;;
esac