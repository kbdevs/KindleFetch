#!/bin/sh

set -e

# Check if running on a Kindle
if ! { [ -f "/etc/prettyversion.txt" ] || [ -d "/mnt/us" ] || pgrep "lipc-daemon" >/dev/null; }; then
    echo "Error: This script must run on a Kindle device." >&2
    exit 1
fi

# Variables
API_URL="https://api.github.com/repos/justrals/KindleFetch/commits"
REPO_URL="https://github.com/justrals/KindleFetch/archive/refs/heads/dev.zip"
ZIP_FILE="/mnt/us/repo.zip"
EXTRACTED_DIR="/mnt/us/KindleFetch-dev"
INSTALL_DIR="/mnt/us/extensions/kindlefetch"
CONFIG_FILE="$INSTALL_DIR/bin/kindlefetch_config"
VERSION_FILE="$INSTALL_DIR/bin/version"
TEMP_CONFIG="/mnt/us/kindlefetch_config_backup"

get_version() {
    api_response=$(curl -s -H "Accept: application/vnd.github.v3+json" "$API_URL") || {
        echo "Warning: Failed to fetch version from GitHub API" >&2
        echo "unknown"
        return
    }

    latest_sha=$(echo "$api_response" | grep -m1 '"sha":' | cut -d'"' -f4 | cut -c1-7)
    
    if [ -n "$latest_sha" ]; then
        echo "${latest_sha}"
    fi
}

# Backup existing config
if [ -f "$CONFIG_FILE" ]; then
    echo "Backing up existing config..."
    cp -f "$CONFIG_FILE" "$TEMP_CONFIG"
fi

# Download repository
echo "Downloading KindleFetch..."
curl -s -L -o "$ZIP_FILE" "$REPO_URL"
echo "Download complete."

# Extract files
echo "Extracting files..."
unzip -o "$ZIP_FILE" -d "/mnt/us"
echo "Extraction complete."
rm -f "$ZIP_FILE"

# Remove old installation
echo "Removing old installation..."
rm -rf "$INSTALL_DIR"

# Install
echo "Installing KindleFetch..."
mkdir -p "$INSTALL_DIR"
mv -f "$EXTRACTED_DIR/kindlefetch"/* "$INSTALL_DIR/"
echo "Installation successful."

# Create version file
echo "Creating version file..."
VERSION=$(get_version)
mkdir -p "$INSTALL_DIR/bin"
echo "$VERSION" > "$VERSION_FILE"

# Restore config
if [ -f "$TEMP_CONFIG" ]; then
    echo "Restoring configuration..."
    mv -f "$TEMP_CONFIG" "$CONFIG_FILE"
fi

# Cleanup
echo "Cleaning up..."
rm -rf "$EXTRACTED_DIR"

echo "KindleFetch installation completed successfully. Version: $VERSION"
