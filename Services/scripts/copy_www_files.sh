#!/bin/bash

# Check if Docker container name is provided
if [ -z "$1" ]; then
    echo "Error: No Docker container name provided."
    echo "Usage: $0 <docker_container_name> <www_directory>"
    exit 1
fi

# Check if the www directory is provided
if [ -z "$2" ]; then
    echo "Error: No www directory provided."
    echo "Assuming there are no files to copy."
    exit 0
fi

# Set Docker container name and www directory path
DOCKER_CONTAINER="$1"
WWW_DIR="$2"

# Ensure the www directory exists
if [ ! -d "$WWW_DIR" ]; then
    echo "Error: www directory '$WWW_DIR' not found."
    exit 1
fi

# Copy all files and folders from the www directory to /var/www/ in the container
echo "Copying contents of $WWW_DIR to /var/www/ in Docker container $DOCKER_CONTAINER..."
docker cp "$WWW_DIR/." "$DOCKER_CONTAINER:/var/www/"

echo "All www files and folders copied successfully."
