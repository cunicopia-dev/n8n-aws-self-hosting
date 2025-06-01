#!/bin/bash

# Parse command line arguments
USE_POSTGRES=false
CLEAN_DATA=false
RESET_POSTGRES=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --postgres)
      USE_POSTGRES=true
      shift
      ;;
    --clean)
      CLEAN_DATA=true
      shift
      ;;
    --reset-postgres)
      RESET_POSTGRES=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--postgres] [--clean] [--reset-postgres]"
      echo "  --postgres: Use PostgreSQL instead of SQLite"
      echo "  --clean: Remove existing n8n data (useful for encryption key issues)"
      echo "  --reset-postgres: Remove PostgreSQL data and start fresh"
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
  
  # Check if user wants to clean data
  if [ "$CLEAN_DATA" = true ]; then
    echo "Cleaning n8n data directory to resolve encryption key conflicts..."
    rm -rf ./n8n_data/.n8n
    echo "Data cleaned. N8n will start fresh."
  fi
fi

# Always ensure the encryption key issue is handled
if [ -f "./n8n_data/.n8n/config" ] && [ -f ".env" ]; then
  # Check if there's a mismatch that could cause issues
  if ! grep -q "N8N_ENCRYPTION_KEY" .env; then
    echo "WARNING: No encryption key found in .env file!"
    echo "This will cause issues. Please add N8N_ENCRYPTION_KEY to your .env file"
    echo "or run with --clean flag to start fresh."
    exit 1
  fi
fi

# Stop any running containers first
echo "Stopping any existing n8n containers..."
docker compose --profile postgres down 2>/dev/null || true

# Handle PostgreSQL reset if requested
if [ "$RESET_POSTGRES" = true ]; then
  echo "Resetting PostgreSQL data..."
  # Force remove with -v flag to ensure volumes are removed
  docker compose --profile postgres down -v 2>/dev/null || true
  # Double-check and force remove the volume if it still exists
  docker volume rm mir-n8n_postgres_data -f 2>/dev/null || true
  echo "PostgreSQL data reset. A new database will be created."
fi

echo "Starting n8n with Docker Compose..."
if [ "$USE_POSTGRES" = true ] || grep -q "^DB_TYPE=postgresdb" .env 2>/dev/null; then
  echo "Starting with PostgreSQL..."
  docker compose --profile postgres up -d
else
  echo "Starting with SQLite..."
  docker compose up -d
fi

# Wait a moment for services to start
sleep 3

echo "n8n is now running at http://localhost:5678"
echo "Use Ctrl+C to stop viewing logs or run 'docker compose down' to stop n8n"
echo ""
echo "IMPORTANT: When you log in to n8n, you'll create credentials for services"
echo "like Google Drive, Notion, GitHub, and Miro through the n8n interface."
echo "These will be securely stored in n8n's encrypted database."

# Show logs
docker compose logs -f 