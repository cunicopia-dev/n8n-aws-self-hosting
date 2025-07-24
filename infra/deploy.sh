#!/bin/bash

set -e

# Namespaced deployment script for n8n CloudFormation stacks

# Check for required parameters
if [ "$#" -lt 6 ]; then
    echo "Usage: $0 --namespace <namespace> --vpc-id <vpc-id> --subnet-id <subnet-id> [--instance-type t4g.small|t4g.medium]"
    echo ""
    echo "  --namespace: A unique identifier for this client/deployment (e.g., client-name)"
    echo "  --vpc-id: The VPC ID where the instance will be deployed"
    echo "  --subnet-id: The subnet ID for the EC2 instance"
    echo "  --instance-type: (Optional) EC2 instance type, defaults to t4g.small"
    echo ""
    echo "Example: $0 --namespace acme-corp --vpc-id vpc-12345 --subnet-id subnet-67890"
    exit 1
fi

# Parse arguments
NAMESPACE=""
VPC_ID=""
SUBNET_ID=""
INSTANCE_TYPE="t4g.small"

while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace) NAMESPACE="$2"; shift 2 ;;
        --vpc-id) VPC_ID="$2"; shift 2 ;;
        --subnet-id) SUBNET_ID="$2"; shift 2 ;;
        --instance-type) INSTANCE_TYPE="$2"; shift 2 ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
done

# Validate namespace format
if ! [[ "$NAMESPACE" =~ ^[a-z0-9-]+$ ]]; then
    echo "Error: Namespace must contain only lowercase letters, numbers, and hyphens"
    exit 1
fi

# Validate templates with SAM
echo "Validating templates..."
sam validate --template-file s3.yaml --lint || exit 1
sam validate --template-file iam.yaml --lint || exit 1
sam validate --template-file ec2.yaml --lint || exit 1

# Deploy S3 with namespace
echo "Deploying S3 bucket for namespace: $NAMESPACE..."
aws cloudformation deploy \
    --template-file s3.yaml \
    --stack-name "n8n-${NAMESPACE}-s3" \
    --parameter-overrides Namespace="$NAMESPACE"

# Get S3 outputs
S3_BUCKET_ARN=$(aws cloudformation describe-stacks --stack-name "n8n-${NAMESPACE}-s3" --query 'Stacks[0].Outputs[?OutputKey==`BucketArn`].OutputValue' --output text)
S3_BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name "n8n-${NAMESPACE}-s3" --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text)

# Upload backup scripts to S3 if they exist
if [ -d "scripts" ]; then
    echo "Uploading backup scripts to S3..."
    aws s3 sync scripts/ "s3://${S3_BUCKET_NAME}/scripts/" --exclude "*" --include "*.sh"
fi

# Deploy IAM with namespace
echo "Deploying IAM roles for namespace: $NAMESPACE..."
aws cloudformation deploy \
    --template-file iam.yaml \
    --stack-name "n8n-${NAMESPACE}-iam" \
    --parameter-overrides \
        Namespace="$NAMESPACE" \
        S3BucketArn="$S3_BUCKET_ARN" \
    --capabilities CAPABILITY_NAMED_IAM

# Get IAM output
INSTANCE_PROFILE=$(aws cloudformation describe-stacks --stack-name "n8n-${NAMESPACE}-iam" --query 'Stacks[0].Outputs[?OutputKey==`InstanceProfileName`].OutputValue' --output text)

# Deploy EC2 with namespace
echo "Deploying EC2 instance for namespace: $NAMESPACE..."
aws cloudformation deploy \
    --template-file ec2.yaml \
    --stack-name "n8n-${NAMESPACE}-ec2" \
    --parameter-overrides \
        Namespace="$NAMESPACE" \
        VpcId="$VPC_ID" \
        SubnetId="$SUBNET_ID" \
        InstanceType="$INSTANCE_TYPE" \
        InstanceProfileName="$INSTANCE_PROFILE" \
        S3BucketName="$S3_BUCKET_NAME"

# Get instance info
ASG_NAME=$(aws cloudformation describe-stacks --stack-name "n8n-${NAMESPACE}-ec2" --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' --output text)
echo ""
echo "Deployment complete for namespace: $NAMESPACE"
echo "Waiting for instance..."
sleep 30

INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)

echo ""
echo "=== Deployment Summary ==="
echo "Namespace: $NAMESPACE"
echo "Instance ID: $INSTANCE_ID"
echo "S3 Bucket: $S3_BUCKET_NAME"
echo ""
echo "To connect to this instance:"
echo "1. Port forward: aws ssm start-session --target $INSTANCE_ID --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"5678\"],\"localPortNumber\":[\"5678\"]}'"
echo "2. Open browser: http://localhost:5678"
echo ""
echo "To delete this deployment:"
echo "./teardown.sh --namespace $NAMESPACE"