#!/bin/bash

# Trap termination signals and handle them gracefully
trap 'terminate' SIGTERM SIGINT

terminate() {
    echo "Caught termination signal! Stopping Nginx..."
    # Send SIGTERM to Nginx process
    kill -SIGTERM "$child" 2>/dev/null
    wait "$child"
    echo "Nginx stopped."
    exit 0
}

# Start Nginx in the background
echo "Starting Nginx..."
/nginx/nginx -g daemon off &

# Capture the Nginx process PID
child=$!
wait "$child"
