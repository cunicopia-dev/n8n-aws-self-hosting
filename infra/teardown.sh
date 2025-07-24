#!/bin/bash

set -e

# Teardown script for namespaced n8n deployments

# Check for required parameters
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 --namespace <namespace>"
    echo ""
    echo "  --namespace: The namespace/client identifier of the deployment to remove"
    echo ""
    echo "Example: $0 --namespace acme-corp"
    echo ""
    echo "WARNING: This will permanently delete all resources for the specified namespace!"
    exit 1
fi

# Parse arguments
NAMESPACE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace) NAMESPACE="$2"; shift 2 ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
done

# Validate namespace format
if ! [[ "$NAMESPACE" =~ ^[a-z0-9-]+$ ]]; then
    echo "Error: Namespace must contain only lowercase letters, numbers, and hyphens"
    exit 1
fi

# Confirm deletion
echo "WARNING: This will delete ALL resources for namespace: $NAMESPACE"
echo "This includes:"
echo "  - EC2 instance and Auto Scaling Group"
echo "  - IAM roles and instance profile"
echo "  - S3 bucket and all its contents"
echo ""
read -p "Are you sure you want to continue? Type 'yes' to confirm: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Teardown cancelled."
    exit 0
fi

echo ""
echo "Starting teardown for namespace: $NAMESPACE..."

# Delete EC2 stack first (depends on IAM)
echo "Deleting EC2 resources..."
aws cloudformation delete-stack --stack-name "n8n-${NAMESPACE}-ec2" || true
aws cloudformation wait stack-delete-complete --stack-name "n8n-${NAMESPACE}-ec2" || true

# Delete IAM stack (depends on S3)
echo "Deleting IAM resources..."
aws cloudformation delete-stack --stack-name "n8n-${NAMESPACE}-iam" || true
aws cloudformation wait stack-delete-complete --stack-name "n8n-${NAMESPACE}-iam" || true

# Empty and delete S3 bucket
echo "Emptying S3 bucket..."
S3_BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name "n8n-${NAMESPACE}-s3" --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text 2>/dev/null || echo "")

if [ ! -z "$S3_BUCKET_NAME" ] && [ "$S3_BUCKET_NAME" != "None" ]; then
    echo "Found S3 bucket: $S3_BUCKET_NAME"
    # Empty the bucket before deletion
    aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive || true
fi

# Delete S3 stack
echo "Deleting S3 resources..."
aws cloudformation delete-stack --stack-name "n8n-${NAMESPACE}-s3" || true
aws cloudformation wait stack-delete-complete --stack-name "n8n-${NAMESPACE}-s3" || true

echo ""
echo "Teardown complete for namespace: $NAMESPACE"
echo "All resources have been deleted."