#!/bin/bash

# Check if the Docker Image Path is provided as argument 1
if [ -z "$1" ]; then
    echo "Error: No Docker image file path provided."
    echo "Usage: $0 <path_to_image_file> <docker_image_name>"
    exit 1
fi

# Check if the Docker Image Name is provided as argument 2
if [ -z "$2" ]; then
    echo "Error: No Docker image name provided."
    echo "Usage: $0 <path_to_image_file> <docker_image_name>"
    exit 1
fi

# Set variables for image file and Docker image name
IMAGE_FILE="$1"
DOCKER_IMAGE="$2"

# Check if the Docker image is already loaded
if docker image inspect "$DOCKER_IMAGE" > /dev/null 2>&1; then
    echo "Docker image '$DOCKER_IMAGE' is already loaded."
    exit 0
fi

# Try to locate the Docker image file up to 2 levels up if not found
if [ ! -f "$IMAGE_FILE" ]; then
    IMAGE_FILE="$(find .. ../.. -type f -name "$(basename "$IMAGE_FILE")" -print -quit)"
    if [ -z "$IMAGE_FILE" ]; then
        echo "Error: Docker image file not found in current directory or up to 2 levels up."
        exit 1
    else
        echo "Found Docker image file at: $IMAGE_FILE"
    fi
else
    echo "Docker image file found: $IMAGE_FILE"
fi

# Attempt to load the Docker image from the file
if (sudo docker image load -i "$IMAGE_FILE"); then
    echo "Docker image loaded successfully from file."
else
    echo "Failed to load Docker image from file."
    echo "Attempting to pull Docker image from Docker Hub..."

    # Try pulling the image from Docker Hub if loading from file fails
    if docker pull "$DOCKER_IMAGE"; then
        echo "Docker image pulled successfully from Docker Hub."
    else
        echo "Error: Failed to load Docker image from file and failed to pull from Docker Hub."
        exit 1
    fi
fi
