#!/bin/bash

# Resolve the base directory where the script is located
SCRIPT_DIR=$(dirname "$(realpath "$0")")
BASE_DIR=$(realpath "$SCRIPT_DIR/..")

# Define SSL input and output directories
CA_DIR="$BASE_DIR/ssl/ca"
BUNDLE_DIR="$BASE_DIR/ssl/ca-bundle"
BUNDLE_FILE="$BUNDLE_DIR/ca-certificates.crt"

# Ensure the input directory exists
if [ ! -d "$CA_DIR" ]; then
    echo "Error: Directory '$CA_DIR' does not exist."
    exit 1
fi

# Create the output directory if it doesn't exist
mkdir -p "$BUNDLE_DIR"

# Combine all .crt and .pem files into a single bundle with proper formatting
echo "Compiling CA files from '$CA_DIR' into '$BUNDLE_FILE'..."
> "$BUNDLE_FILE" # Create or clear the bundle file
for cert in "$CA_DIR"/*.cer "$CA_DIR"/*.crt "$CA_DIR"/*.pem; do
    echo "Adding '$cert' to the bundle..."
    if [ -f "$cert" ]; then
        cat "$cert" >> "$BUNDLE_FILE"
        echo "" >> "$BUNDLE_FILE" # Ensure a newline after each certificate
    fi
done

# Remove blank lines from the bundle file
sed -i '/^$/d' "$BUNDLE_FILE"

# Check if the bundle file was created
if [ -f "$BUNDLE_FILE" ]; then
    echo "CA bundle created successfully at '$BUNDLE_FILE'."
else
    echo "Error: No CA files found in '$CA_DIR'. Bundle not created."
    exit 1
fi
