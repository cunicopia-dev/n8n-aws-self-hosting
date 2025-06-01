#!/bin/bash

set -e

# Simple deployment script for n8n CloudFormation stacks

# Check for required parameters
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 --vpc-id <vpc-id> --subnet-id <subnet-id> [--instance-type t4g.small|t4g.medium]"
    exit 1
fi

# Parse arguments
VPC_ID=""
SUBNET_ID=""
INSTANCE_TYPE="t4g.small"

while [[ $# -gt 0 ]]; do
    case $1 in
        --vpc-id) VPC_ID="$2"; shift 2 ;;
        --subnet-id) SUBNET_ID="$2"; shift 2 ;;
        --instance-type) INSTANCE_TYPE="$2"; shift 2 ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
done

# Validate templates with SAM
echo "Validating templates..."
sam validate --template-file s3.yaml --lint || exit 1
sam validate --template-file iam.yaml --lint || exit 1
sam validate --template-file ec2.yaml --lint || exit 1

# Deploy S3
echo "Deploying S3 bucket..."
aws cloudformation deploy \
    --template-file s3.yaml \
    --stack-name n8n-s3

# Get S3 outputs
S3_BUCKET_ARN=$(aws cloudformation describe-stacks --stack-name n8n-s3 --query 'Stacks[0].Outputs[?OutputKey==`BucketArn`].OutputValue' --output text)
S3_BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name n8n-s3 --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text)

# Deploy IAM
echo "Deploying IAM roles..."
aws cloudformation deploy \
    --template-file iam.yaml \
    --stack-name n8n-iam \
    --parameter-overrides S3BucketArn="$S3_BUCKET_ARN" \
    --capabilities CAPABILITY_NAMED_IAM

# Get IAM output
INSTANCE_PROFILE=$(aws cloudformation describe-stacks --stack-name n8n-iam --query 'Stacks[0].Outputs[?OutputKey==`InstanceProfileName`].OutputValue' --output text)

# Deploy EC2
echo "Deploying EC2 instance..."
aws cloudformation deploy \
    --template-file ec2.yaml \
    --stack-name n8n-ec2 \
    --parameter-overrides \
        VpcId="$VPC_ID" \
        SubnetId="$SUBNET_ID" \
        InstanceType="$INSTANCE_TYPE" \
        InstanceProfileName="$INSTANCE_PROFILE" \
        S3BucketName="$S3_BUCKET_NAME"

# Get instance info
ASG_NAME=$(aws cloudformation describe-stacks --stack-name n8n-ec2 --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' --output text)
echo ""
echo "Deployment complete! Waiting for instance..."
sleep 30

INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)

echo ""
echo "Instance ID: $INSTANCE_ID"
echo ""
echo "To connect:"
echo "1. Port forward: aws ssm start-session --target $INSTANCE_ID --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"5678\"],\"localPortNumber\":[\"5678\"]}'"
echo "2. Open browser: http://localhost:5678"