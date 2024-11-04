#!/bin/bash

# Trap termination signals and handle them gracefully
trap 'terminate' SIGTERM SIGINT

terminate() {
    echo "Caught termination signal! Stopping Openfire..."
    # Send SIGTERM to Openfire process
    kill -SIGTERM "$child" 2>/dev/null
    wait "$child"
    echo "Openfire stopped."
    exit 0
}

# Start Openfire in the background
echo "Starting Openfire..."
/usr/share/openfire/bin/openfire.sh -debug &

# Capture the Openfire process PID
child=$!
wait "$child"
