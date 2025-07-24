# n8n Self-Hosted Workflow Automation

![License](https://img.shields.io/badge/license-MIT-blue)
![AWS Deployment](https://img.shields.io/badge/deployment-AWS-orange)
![n8n Version](https://img.shields.io/badge/n8n-latest-green)
![Architecture](https://img.shields.io/badge/architecture-ARM64-red)

Self-hosted n8n automation stack with secure AWS deployment, PostgreSQL support, and full CloudFormation infrastructure.

## Table of Contents

- [Why This Solution?](#why-this-solution)
- [Features](#features)
- [Quick Start](#quick-start)
  - [Local Development](#local-development)
  - [Switching Database Backends](#switching-database-backends)
- [AWS Deployment](#aws-deployment)
  - [Architecture](#architecture)
  - [Prerequisites](#prerequisites)
  - [Deployment Steps](#deployment-steps)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Backup and Restore](#backup-and-restore)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Extend This Stack](#extend-this-stack)
- [Contributing](#contributing)

## Why This Solution?

- 💰 **Cost-Optimized**: $5-10/month vs $25+ for managed solutions
- 🔒 **Secure by Default**: Private subnet deployment, SSM access only, no public IPs
- 🚀 **Production-Ready**: Auto-healing via ASG, automated backups, CloudWatch monitoring
- 🛠️ **Zero Lock-in**: Your data, your infrastructure, export and migrate anytime
- 📦 **Simple Architecture**: Just EC2 + PostgreSQL, no Kubernetes complexity
- ⚡ **Infrastructure as Code**: Fully automated CloudFormation deployment
- 🎯 **Single-Command Deploy**: From zero to running in ~5 minutes

## Features

- Docker Compose based deployment
- PostgreSQL backend 
- Automatic encryption key generation
- Persistent data storage
- AWS CloudFormation templates for production deployment
- Secure AWS deployment with SSM port forwarding

## Quick Start

### Local Development

1. Clone this repository:
```bash
git clone https://github.com/cunicopia-dev/n8n-aws-self-hosting.git
cd n8n-aws-self-hosting
```

2. Run the installation script:
```bash
# With SQLite (default)
./install-n8n.sh

# With PostgreSQL
./install-n8n.sh --postgres
```

3. Access n8n at http://localhost:5678

### Switching Database Backends

To switch from SQLite to PostgreSQL after initial setup:

1. Edit `.env` file and change:
   - `DB_TYPE=sqlite` to `DB_TYPE=postgresdb`
   - Uncomment and configure the PostgreSQL settings

2. Restart with PostgreSQL profile:
```bash
docker compose down
docker compose --profile postgres up -d
```

## AWS Deployment

### Namespaced Deployments

The infrastructure now supports namespaced deployments, allowing you to run separate n8n instances for different clients or environments. Each namespace creates isolated resources with no shared dependencies.

### Architecture

```mermaid
graph TB
    subgraph "Your Computer"
        Browser[Web Browser<br/>localhost:5678]
        Terminal[Terminal/CLI]
    end
    
    subgraph "AWS Infrastructure"
        subgraph "CloudFormation Stacks"
            CF1[S3 Stack]
            CF2[IAM Stack]
            CF3[EC2 Stack]
        end
        
        subgraph "Resources"
            S3[(S3 Bucket<br/>File Storage)]
            IAM[IAM Role +<br/>Instance Profile]
            
            subgraph "VPC"
                ASG[Auto Scaling Group<br/>min=1, max=1]
                LT[Launch Template]
                EC2[EC2 Instance<br/>t4g.small/medium<br/>+ n8n + PostgreSQL 17]
            end
        end
        
        SSM[Systems Manager]
    end
    
    Browser -.->|Port Forward| Terminal
    Terminal -->|SSM Session| SSM
    SSM -->|Private Connection| EC2
    
    CF1 -->|Creates| S3
    CF2 -->|Creates| IAM
    CF3 -->|Creates| ASG
    CF3 -->|Creates| LT
    
    ASG -->|Uses| LT
    LT -->|Launches| EC2
    IAM -->|Attached to| EC2
    EC2 -->|Store Files| S3
    EC2 -->|Internet Access| Internet((Internet))
    
    style EC2 fill:#e1f5fe,color:#01579b
    style S3 fill:#fff3e0,color:#e65100
    style SSM fill:#f3e5f5,color:#4a148c
    style CF1 fill:#c8e6c9,color:#1b5e20
    style CF2 fill:#c8e6c9,color:#1b5e20
    style CF3 fill:#c8e6c9,color:#1b5e20
```

**Note**: AWS deployments now default to PostgreSQL 17 for better performance and reliability. The EC2 instance includes PostgreSQL client tools for database management and backups.

### Prerequisites

- **AWS CLI**: [Installation guide](https://aws.amazon.com/cli/)
- **AWS SAM CLI**: [Installation guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)
- **AWS Session Manager Plugin**: [Installation guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) (required for SSM connections)
- **Docker** and **Docker Compose v2.20.2+** (for local development)
- AWS credentials configured (`aws configure`)
- VPC with at least one subnet
- Appropriate AWS permissions for CloudFormation, EC2, S3, IAM, and SSM

> 💰 **Estimated Cost**: With AWS EC2 RIs, you can get a t4g.small for as low as $5 a month. 
> This setup is ideal for lean, production-grade automation infrastructure without the managed service tax.

### Important: n8n Licensing for Client Deployments

⚠️ **Note**: According to n8n's license, separate instances are required when hosting workloads for different clients. The deployment scripts now support namespaced deployments to ensure compliance.

### Deployment Steps

You have two options for deployment:

#### Option 1: Manual Deployment (Recommended for understanding what's happening)

1. Deploy the S3 bucket:
```bash
cd infra
aws cloudformation create-stack \
  --stack-name n8n-s3 \
  --template-body file://s3.yaml
```

2. Deploy IAM roles:
```bash
aws cloudformation create-stack \
  --stack-name n8n-iam \
  --template-body file://iam.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters ParameterKey=S3BucketArn,ParameterValue=$(aws cloudformation describe-stacks --stack-name n8n-s3 --query 'Stacks[0].Outputs[?OutputKey==`BucketArn`].OutputValue' --output text)
```

3. Deploy EC2 instance:

- Make sure to replace the `VpcId` and the `SubnetId` with real values.
```bash
aws cloudformation create-stack \
  --stack-name n8n-ec2 \
  --template-body file://ec2.yaml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=vpc-xxxxxx \
    ParameterKey=SubnetId,ParameterValue=subnet-xxxxxx \
    ParameterKey=InstanceType,ParameterValue=t4g.small \
    ParameterKey=InstanceProfileName,ParameterValue=$(aws cloudformation describe-stacks --stack-name n8n-iam --query 'Stacks[0].Outputs[?OutputKey==`InstanceProfileName`].OutputValue' --output text) \
    ParameterKey=S3BucketName,ParameterValue=$(aws cloudformation describe-stacks --stack-name n8n-s3 --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text)
```

4. Get your instance ID:
```bash
# Wait a minute for the instance to launch, then:
ASG_NAME=$(aws cloudformation describe-stacks \
  --stack-name n8n-ec2 \
  --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
  --output text)

INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

echo "Your instance ID is: $INSTANCE_ID"
```

5. Connect to n8n:
```bash
# Terminal 1 - SSH into the instance (optional)
aws ssm start-session --target $INSTANCE_ID

# Terminal 2 - Port forward n8n (requires Session Manager plugin)
aws ssm start-session \
  --target $INSTANCE_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["5678"],"localPortNumber":["5678"]}'
```

> **Note**: If you get an error about the Session Manager plugin, make sure you've installed it from the prerequisites above.

6. Access n8n at http://localhost:5678

#### Option 2: Automated Deployment Script (Recommended)

The deployment script now supports namespaced deployments for hosting multiple isolated n8n instances:

```bash
cd infra
# Deploy for a specific client/namespace
./deploy.sh --namespace acme-corp --vpc-id vpc-xxxxxx --subnet-id subnet-xxxxxx

# Deploy another instance for a different client
./deploy.sh --namespace contoso-ltd --vpc-id vpc-xxxxxx --subnet-id subnet-xxxxxx
```

Each namespace creates completely isolated resources:
- Separate EC2 instance
- Dedicated S3 bucket
- Isolated IAM roles and permissions
- Independent n8n installation

To remove a deployment:
```bash
./teardown.sh --namespace acme-corp
```

## Project Structure

```
n8n-aws-self-hosting/
├── docker-compose.yml      # Docker Compose configuration
├── install-n8n.sh         # Installation script
├── .env                   # Environment configuration (created on first run)
├── n8n_data/             # n8n persistent data
├── local-files/          # Local file storage
├── workflows/            # n8n workflow exports
├── prompts/             # Prompt templates
└── infra/               # AWS CloudFormation templates
    ├── s3.yaml          # S3 bucket configuration
    ├── ec2.yaml         # EC2 instance configuration
    ├── iam.yaml         # IAM roles and policies
    ├── deploy.sh        # Namespaced deployment script
    └── teardown.sh      # Cleanup script for namespaced deployments
```

## Configuration

### Environment Variables

Key environment variables in `.env` (see `.env.example` for all options):

- `N8N_ENCRYPTION_KEY`: Auto-generated encryption key for credentials
- `DB_TYPE`: Database type (`sqlite` or `postgresdb`)
- `DB_POSTGRESDB_*`: PostgreSQL connection settings
- `GENERIC_TIMEZONE`: Timezone setting (default: UTC)

For a complete list of configuration options, check `.env.example` which includes:
- External database connections (RDS)
- Basic authentication
- Email/SMTP configuration
- Webhook settings
- S3 file storage
- Execution timeouts

## Security

### Why SSM over SSH?

SSM (Systems Manager) provides several advantages over traditional SSH access:

- **No SSH keys to manage** - Access controlled via AWS IAM
- **No public IPs needed** - Instances stay in private subnets
- **Session auditing** - All access logged via AWS CloudTrail
- **Easy automation** - Simple `aws ssm start-session` commands

### Security Features

| Feature | Description |
|---------|-------------|
| 🔐 No Public IPs | Instances deployed in private subnets only |
| 🔑 IAM-Based Access | All access controlled via instance profiles |
| 📦 Encrypted Secrets | Auto-generated encryption keys and passwords |
| 🛡️ SSM Access Only | No SSH keys, auditable access via SSM |
| 🔒 Outbound Only | Security group blocks all inbound traffic |
| 🎲 Random Passwords | Auto-generated PostgreSQL and encryption keys |

### ARM64 Compatibility

This deployment uses ARM64-based `t4g` instances for cost efficiency. All Docker images in the stack support ARM64 architecture.

## Backup and Restore

### Local Deployment

**SQLite:**
```bash
# Backup
cp -r n8n_data n8n_data_backup

# Restore
cp -r n8n_data_backup n8n_data
```

**PostgreSQL:**
```bash
# Manual backup
docker compose exec postgres pg_dump -U n8n n8n > backup.sql

# Manual restore
docker compose exec -T postgres psql -U n8n n8n < backup.sql
```

### AWS Deployment

**Production Backup Strategy:**

1. **Create a backup script on your EC2 instance:**

```bash
# SSH into your instance
aws ssm start-session --target <instance-id>

# Create backup script
sudo tee /opt/backup-n8n.sh > /dev/null <<'EOF'
#!/bin/bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BUCKET_NAME="${S3_BUCKET}"
BACKUP_FILE="/tmp/n8n_backup_${TIMESTAMP}.sql"

# Create PostgreSQL backup
cd /opt/n8n-aws-self-hosting
docker compose exec -T postgres pg_dump -U n8n n8n > "$BACKUP_FILE"

# Compress the backup
gzip "$BACKUP_FILE"

# Upload to S3
aws s3 cp "${BACKUP_FILE}.gz" "s3://${BUCKET_NAME}/backups/n8n_backup_${TIMESTAMP}.sql.gz"

# Cleanup local file
rm "${BACKUP_FILE}.gz"

# Keep only last 30 days of backups in S3
aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --prefix "backups/" \
  --query 'Contents[?LastModified<=`'$(date -d '30 days ago' --iso-8601)'`].[Key]' \
  --output text | xargs -I {} aws s3 rm "s3://${BUCKET_NAME}/{}"

echo "Backup completed: n8n_backup_${TIMESTAMP}.sql.gz"
EOF

# Make executable
sudo chmod +x /opt/backup-n8n.sh
```

2. **Set up automated daily backups with cron:**

```bash
# Add to crontab for daily backups at 2 AM
sudo crontab -e

# Add this line:
0 2 * * * /opt/backup-n8n.sh >> /var/log/n8n-backup.log 2>&1
```

3. **Restore from S3 backup:**

```bash
# List available backups
aws s3 ls s3://${S3_BUCKET}/backups/

# Download and restore a specific backup
BACKUP_FILE="n8n_backup_20241201_020000.sql.gz"
aws s3 cp "s3://${S3_BUCKET}/backups/${BACKUP_FILE}" /tmp/
gunzip "/tmp/${BACKUP_FILE}"

# Stop n8n, restore database, restart
cd /opt/n8n-aws-self-hosting
docker compose down
docker compose up -d postgres
sleep 10
docker compose exec -T postgres psql -U n8n n8n < "/tmp/${BACKUP_FILE%.gz}"
docker compose up -d n8n
```

**Weekly Full Instance Backup:**

For additional safety, consider weekly EBS snapshots of your EC2 volume:

```bash
# Create a snapshot via AWS CLI
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
VOLUME_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' --output text)

aws ec2 create-snapshot --volume-id $VOLUME_ID \
  --description "n8n Weekly Backup $(date +%Y-%m-%d)"
```

## Troubleshooting

### Common Issues

1. **Port already in use**: Change the port mapping in `docker-compose.yml`
2. **Permission denied**: Ensure proper permissions on `n8n_data` and `local-files` directories
3. **Database connection failed**: Check PostgreSQL container health and credentials in `.env`
4. **Encryption key mismatch**: If you see encryption key errors after changing `.env`:
   ```bash
   ./install-n8n.sh --clean
   ```
   This removes the old config but preserves your workflows

### PostgreSQL Connection Notes

- The host should be `postgres` (the Docker service name), not `localhost`
- The database name is `n8n` by default
- Connection happens over Docker's internal network
- To connect from your host machine for debugging:
  ```bash
  docker compose exec postgres psql -U n8n -d n8n
  ```

### Connecting with DBeaver/pgAdmin

To connect from local database tools:
- **Host**: localhost
- **Port**: 5432 (see note below if you have conflicts)
- **Database**: n8n
- **Username**: n8n
- **Password**: (from your .env file)

> **Port Conflict Note**: If you already have PostgreSQL running locally on port 5432, you'll need to change the port mapping in `docker-compose.yml` from `"5432:5432"` to something like `"5433:5432"`, then connect to port 5433 instead.

### Logs

View logs:
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f n8n
docker compose logs -f postgres
```

## FAQ

**Q: Can I expose n8n to the public internet?**
A: Yes, but you'll need to alter the architecture slightly. One strategy is to add an Application Load Balancer, use Route53 and ACM for DNS and SSL certificate management. For enterprise deployments, included a layer 7 web application firewall would be a good idea. Another strategy is to use Cloudflare which is a cheaper option. 

The current setup prioritizes security with private access only - exposing n8n across the public internet comes with some security risks that you should be wary of. 

**Q: How do I update n8n to the latest version?**
A: For local: `docker compose pull && docker compose down && docker compose up -d`. For AWS: redeploy the stack or SSH in and run the same commands.

**Q: Can I use RDS instead of local PostgreSQL?**
A: Yes! Set the `DB_POSTGRESDB_HOST` to your RDS endpoint in the `.env` file and remove the postgres service from docker-compose.yml.

**Q: What if I already have PostgreSQL running on port 5432?**
A: Change the port mapping in docker-compose.yml from `"5432:5432"` to something like `"5433:5432"`.

**Q: How do I backup my data?**
A: See the [Backup and Restore](#backup-and-restore) section above for detailed instructions.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Extend This Stack

- 📦 Replace local Postgres with external RDS or Aurora
- 🔁 Use GitHub Actions + SAM CLI for CI/CD deploys
- 📊 Send logs to CloudWatch or Loki
- 🤖 Integrate Ollama or Bedrock into workflows
- 🔐 Add secrets management via AWS Parameter Store
- 🌐 Put behind Application Load Balancer for team access
- 📈 Add CloudWatch dashboards for monitoring
- 🔄 Implement automated backups to S3