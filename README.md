# n8n Automation Cookbook

A simple, self-hosted setup for n8n automation using Docker Compose with persistent data storage.

## Overview

This repository provides a quick way to set up [n8n](https://n8n.io/) - an open-source workflow automation tool similar to Zapier or Make.com. It allows you to connect various services like Google Drive, Notion, GitHub, and Miro to create automated workflows.

## Prerequisites

- Docker and Docker Compose installed on your system
- Basic familiarity with terminal/command line

## Quick Start

1. Clone this repository to your local machine
2. Run the installation script:

```bash
./install-n8n.sh
```

3. Access n8n at: http://localhost:5678
4. Create your first workflow!

## What's Included

- **Docker Compose configuration**: Sets up n8n with proper networking and persistent storage
- **Automated installation script**: Creates necessary directories and a secure encryption key
- **Local files directory**: For sharing files between n8n and your system

## Data Persistence

Your n8n data (workflows, credentials, etc.) is stored in:
- `./n8n_data`: Main n8n data directory (mounted as a volume)
- `./local-files`: A directory accessible from within n8n at `/files` path

## Managing Credentials

For services like Google Drive, Notion, GitHub, and Miro:

1. Log in to n8n interface at http://localhost:5678
2. Navigate to **Settings → Credentials**
3. Create new credentials for each service you want to connect
4. These credentials are stored securely in n8n's encrypted database

## Configuration

The setup automatically creates a `.env` file with necessary configuration:

- `N8N_ENCRYPTION_KEY`: A randomly generated key for securing credentials
- `GENERIC_TIMEZONE`: Set to UTC by default, change to your timezone if needed

You can edit the `.env` file to customize your configuration.

## Adding PostgreSQL (Future Enhancement)

This setup currently uses SQLite (default). To switch to PostgreSQL later:

1. Uncomment the PostgreSQL-related lines in `docker-compose.yml`
2. Update the `.env` file with your PostgreSQL settings
3. Restart n8n with `docker compose down && docker compose up -d`

## Commands

- **Start n8n**: `./install-n8n.sh` or `docker compose up -d`
- **Stop n8n**: `docker compose down`
- **View logs**: `docker compose logs -f`
- **Restart n8n**: `docker compose restart`

## Accessing n8n Files

From within n8n workflows, use the **Read/Write Files from Disk** node with the path `/files/` to access files in the `./local-files` directory on your host system.

## Updating n8n

To update to the latest version:

```bash
docker compose pull
docker compose down
docker compose up -d
```

## Troubleshooting

- **Cannot access n8n**: Make sure ports 5678 is not being used by another application
- **Credentials not working**: Check that you've generated a proper encryption key
- **Webhook errors**: Webhooks require your instance to be accessible from the internet
