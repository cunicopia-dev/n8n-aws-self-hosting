#!/bin/bash

# Parse command line arguments
USE_POSTGRES=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --postgres)
      USE_POSTGRES=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--postgres]"
      exit 1
      ;;
  esac
done

# Create directories for persistent storage
mkdir -p ./n8n_data
mkdir -p ./local-files

# Set correct permissions
chmod -R 777 ./n8n_data
chmod -R 777 ./local-files

# Check if .env file exists, if not create it with a random encryption key
if [ ! -f .env ]; then
  echo "Creating .env file with secure encryption key..."
  RANDOM_KEY=$(openssl rand -hex 24)
  echo "# n8n Configuration" > .env
  echo "N8N_ENCRYPTION_KEY=$RANDOM_KEY" >> .env
  echo "GENERIC_TIMEZONE=UTC" >> .env
  echo "" >> .env
  echo "# Database configuration" >> .env
  
  if [ "$USE_POSTGRES" = true ]; then
    POSTGRES_PASSWORD=$(openssl rand -hex 16)
    echo "DB_TYPE=postgresdb" >> .env
    echo "DB_POSTGRESDB_DATABASE=n8n" >> .env
    echo "DB_POSTGRESDB_HOST=postgres" >> .env
    echo "DB_POSTGRESDB_PORT=5432" >> .env
    echo "DB_POSTGRESDB_USER=n8n" >> .env
    echo "DB_POSTGRESDB_PASSWORD=$POSTGRES_PASSWORD" >> .env
    echo "" >> .env
    echo "PostgreSQL enabled with generated password"
  else
    echo "DB_TYPE=sqlite" >> .env
    echo "# Uncomment below to use PostgreSQL instead of SQLite" >> .env
    echo "# DB_POSTGRESDB_DATABASE=n8n" >> .env
    echo "# DB_POSTGRESDB_HOST=postgres" >> .env
    echo "# DB_POSTGRESDB_PORT=5432" >> .env
    echo "# DB_POSTGRESDB_USER=n8n" >> .env
    echo "# DB_POSTGRESDB_PASSWORD=change-to-secure-password" >> .env
    echo "" >> .env
    echo "Using SQLite database (default)"
  fi
  
  echo ".env file created with random encryption key"
else
  echo ".env file already exists, using existing configuration"
fi

echo "Starting n8n with Docker Compose..."
if [ "$USE_POSTGRES" = true ] || grep -q "^DB_TYPE=postgresdb" .env 2>/dev/null; then
  echo "Starting with PostgreSQL..."
  docker compose --profile postgres up -d
else
  echo "Starting with SQLite..."
  docker compose up -d
fi

echo "n8n is now running at http://localhost:5678"
echo "Use Ctrl+C to stop viewing logs or run 'docker compose down' to stop n8n"
echo ""
echo "IMPORTANT: When you log in to n8n, you'll create credentials for services"
echo "like Google Drive, Notion, GitHub, and Miro through the n8n interface."
echo "These will be securely stored in n8n's encrypted database."

# Show logs
docker compose logs -f 