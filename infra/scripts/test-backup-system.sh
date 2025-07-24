#!/bin/bash

# Test script for n8n backup system
# This script validates that the backup system is properly configured

set -euo pipefail

NAMESPACE="${NAMESPACE:-unknown}"
S3_BUCKET="${S3_BUCKET}"

echo "n8n Backup System Test"
echo "======================"
echo "Namespace: $NAMESPACE"
echo "S3 Bucket: $S3_BUCKET"
echo ""

# Test 1: Check required environment variables
echo "Test 1: Environment Variables"
echo "------------------------------"
if [ "$NAMESPACE" != "unknown" ] && [ ! -z "$S3_BUCKET" ]; then
    echo "✓ Required environment variables are set"
else
    echo "✗ Missing required environment variables"
    echo "  NAMESPACE: $NAMESPACE"
    echo "  S3_BUCKET: $S3_BUCKET"
    exit 1
fi

# Test 2: Check if scripts are installed
echo ""
echo "Test 2: Script Installation"
echo "----------------------------"
SCRIPTS=("backup-n8n.sh" "restore-n8n.sh" "backup-monitor.sh" "backup-utils.sh")
for script in "${SCRIPTS[@]}"; do
    if [ -f "/opt/n8n-scripts/$script" ] && [ -x "/opt/n8n-scripts/$script" ]; then
        echo "✓ $script is installed and executable"
    else
        echo "✗ $script is missing or not executable"
    fi
done

# Test 3: Check symlinks
echo ""
echo "Test 3: Symlinks"
echo "----------------"
if [ -L "/usr/local/bin/n8n-backup" ] && [ -x "/usr/local/bin/n8n-backup" ]; then
    echo "✓ n8n-backup symlink is working"
else
    echo "✗ n8n-backup symlink is missing or broken"
fi

if [ -L "/usr/local/bin/n8n-restore" ] && [ -x "/usr/local/bin/n8n-restore" ]; then
    echo "✓ n8n-restore symlink is working"
else
    echo "✗ n8n-restore symlink is missing or broken"
fi

# Test 4: Check cron jobs
echo ""
echo "Test 4: Cron Configuration"
echo "---------------------------"
if crontab -u n8n -l 2>/dev/null | grep -q backup-n8n.sh; then
    echo "✓ Daily backup cron job is configured"
else
    echo "✗ Daily backup cron job is missing"
fi

if crontab -u n8n -l 2>/dev/null | grep -q backup-monitor.sh; then
    echo "✓ Backup monitoring cron job is configured"
else
    echo "✗ Backup monitoring cron job is missing"
fi

# Test 5: Check AWS permissions
echo ""
echo "Test 5: AWS Permissions"
echo "-----------------------"
# Test S3 access
if aws s3 ls "s3://$S3_BUCKET/" > /dev/null 2>&1; then
    echo "✓ S3 bucket access is working"
else
    echo "✗ Cannot access S3 bucket"
fi

# Test CloudWatch permissions
if aws cloudwatch put-metric-data --namespace "n8n/${NAMESPACE}/test" --metric-name TestMetric --value 1 > /dev/null 2>&1; then
    echo "✓ CloudWatch permissions are working"
else
    echo "✗ CloudWatch permissions are not working"
fi

# Test 6: Check Docker services
echo ""
echo "Test 6: Docker Services"
echo "-----------------------"
cd /home/n8n/n8n-aws-self-hosting || exit 1

if docker compose ps postgres | grep -q "running"; then
    echo "✓ PostgreSQL container is running"
else
    echo "✗ PostgreSQL container is not running"
fi

if docker compose ps n8n | grep -q "running"; then
    echo "✓ n8n container is running"
else
    echo "⚠ n8n container is not running (this may be normal during startup)"
fi

# Test 7: Database connectivity
echo ""
echo "Test 7: Database Connectivity"
echo "------------------------------"
if docker compose exec -T postgres pg_isready -U n8n > /dev/null 2>&1; then
    echo "✓ PostgreSQL is accepting connections"
else
    echo "✗ PostgreSQL is not accepting connections"
fi

# Test 8: Backup directory structure
echo ""
echo "Test 8: Log Files"
echo "-----------------"
LOG_FILES=("/var/log/n8n-backup.log" "/var/log/n8n-restore.log" "/var/log/n8n-backup-monitor.log")
for logfile in "${LOG_FILES[@]}"; do
    if [ -f "$logfile" ]; then
        echo "✓ $logfile exists"
    else
        echo "✗ $logfile is missing"
    fi
done

# Test 9: Quick backup test (if requested)
echo ""
echo "Test 9: Backup Test (Optional)"
echo "-------------------------------"
read -p "Would you like to test creating a backup? (y/N): " test_backup
if [[ "$test_backup" =~ ^[Yy]$ ]]; then
    echo "Creating test backup..."
    if /opt/n8n-scripts/backup-n8n.sh; then
        echo "✓ Test backup completed successfully"
    else
        echo "✗ Test backup failed"
    fi
else
    echo "⏭ Skipping backup test"
fi

echo ""
echo "Test Summary"
echo "============"
echo "Backup system test completed."
echo "Review any ✗ items above and fix as needed."
echo ""
echo "To manually test backups:"
echo "  n8n-backup backup-now"
echo ""
echo "To check backup status:"
echo "  n8n-backup status"