#!/bin/bash

# Check if Docker container name is provided
if [ -z "$1" ]; then
    echo "Error: No Docker container name provided."
    echo "Usage: $0 <docker_container_name> <config_directory> <ssl_directory>" 
    exit 1
fi

# Check if the config directory is provided
if [ -z "$2" ]; then
    echo "Error: No config directory name provided."
    echo "Usage: $0 <docker_container_name> <config_directory> <ssl_directory>"
    exit 1
fi

# Check if the config directory is provided
if [ -z "$3" ]; then
    echo "Error: No ssl directory name provided."
    echo "Usage: $0 <docker_container_name> <config_directory> <ssl_directory>"
    exit 1
fi

# Set Docker container name and SSL directories
DOCKER_CONTAINER="$1"
CONF_DIR="$2"
SSL_DIR="$3"

# Ensure the directories exist
if [ ! -d "$CONF_DIR" ]; then
    echo "Error: Configuration directory '$CONF_DIR' not found."
    exit 1
fi

if [ ! -d "$SSL_DIR" ]; then
    echo "Error: SSL directory '$SSL_DIR' not found."
    exit 1
fi

# Find all .crt and .key files referenced in the .conf files
cert_paths=$(grep -hoE 'ssl_client_certificate\s+/etc/ssl/certs/[^;]+\.crt|ssl_certificate\s+/etc/ssl/certs/[^;]+\.crt|ssl_certificate_key\s+/etc/ssl/certs/[^;]+\.key' "$CONF_DIR"/*.conf | awk '{print $2}')

# Check if grep found any certificates
if [ -z "$cert_paths" ]; then
    echo "No SSL certificates found in the configuration files."
    exit 0
fi

cert_files=$(echo "$cert_paths" | xargs -n1 basename | sort | uniq)

# Process each certificate file found in .conf files
for cert_path in $cert_files; do
    # Strip off the "/etc/ssl/certs/" prefix to get just the filename
    cert_file=$(basename "$cert_path")
    
    # Search for the certificate file in the SSL directory or its subdirectories
    found_file=$(find "$SSL_DIR" -type f -name "$cert_file" | head -1)
    
    if [ -n "$found_file" ]; then
        echo "Copying $found_file to Docker container $DOCKER_CONTAINER..."
        docker cp "$found_file" "$DOCKER_CONTAINER:/etc/ssl/certs/$cert_file"
    else
        echo "Error: Required certificate file '$cert_file' not found in '$SSL_DIR' or its subdirectories."
    fi
done

echo "SSL files copied successfully (or noted if missing)."
