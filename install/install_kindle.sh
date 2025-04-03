#!/bin/sh

set -e

# Constants
REPO="justrals/KindleFetch"
API_URL="https://api.github.com/repos/${REPO}/commits"
REPO_URL="https://github.com/${REPO}/archive/refs/heads/main.zip"
INSTALL_DIR="/mnt/us/extensions/kindlefetch"
BIN_DIR="${INSTALL_DIR}/bin"
CONFIG_FILE="${BIN_DIR}/kindlefetch_config"
VERSION_FILE="${BIN_DIR}/version"
TEMP_DIR="/tmp/kindlefetch_update"
TEMP_CONFIG="${TEMP_DIR}/config_backup"
ZIP_FILE="${TEMP_DIR}/repo.zip"
EXTRACTED_DIR="${TEMP_DIR}/KindleFetch-main"

# Check if running on a Kindle
is_kindle() {
    [ -f "/etc/prettyversion.txt" ] || [ -d "/mnt/us" ] || pgrep "lipc-daemon" >/dev/null
}

# Get version from GitHub commits
get_version() {
    api_response=$(curl -s -H "Accept: application/vnd.github.v3+json" "$API_URL") || {
        echo "Error: Failed to fetch commits from GitHub API" >&2
        return 1
    }

    commit_count=$(echo "$api_response" | grep -o '"sha":' | wc -l)
    latest_sha=$(echo "$api_response" | grep -m1 '"sha":' | cut -d'"' -f4 | cut -c1-7)

    if [ -n "$latest_sha" ]; then
        echo "${commit_count}-${latest_sha}"
    else
        echo "$commit_count"
    fi
}

# Create version file
create_version_file() {
    echo "Creating version file..."
    mkdir -p "$BIN_DIR"
    echo "$1" > "$VERSION_FILE"
    echo "Version file created at ${VERSION_FILE}"
}

# Backup existing config
backup_config() {
    mkdir -p "$TEMP_DIR"
    if [ -f "$CONFIG_FILE" ]; then
        echo "Backing up existing config..."
        cp -f "$CONFIG_FILE" "$TEMP_CONFIG"
    fi
}

# Restore config
restore_config() {
    if [ -f "$TEMP_CONFIG" ]; then
        echo "Restoring configuration..."
        mkdir -p "$BIN_DIR"
        mv -f "$TEMP_CONFIG" "$CONFIG_FILE"
    fi
}

# Cleanup temporary files
cleanup() {
    echo "Cleaning up..."
    rm -rf "$TEMP_DIR"
}

# Main installation process
install_kindlefetch() {
    echo "Starting KindleFetch installation..."
    
    mkdir -p "$TEMP_DIR"
    
    echo "Downloading KindleFetch..."
    if ! curl -L -o "$ZIP_FILE" "$REPO_URL"; then
        echo "Error: Failed to download repository" >&2
        return 1
    fi

    echo "Extracting files..."
    if ! unzip -o "$ZIP_FILE" -d "$TEMP_DIR"; then
        echo "Error: Failed to extract files" >&2
        return 1
    fi

    echo "Removing old installation..."
    rm -rf "$INSTALL_DIR"

    echo "Installing KindleFetch..."
    if ! mv -f "$EXTRACTED_DIR" "$INSTALL_DIR"; then
        echo "Error: Failed to move files to installation directory" >&2
        return 1
    fi

    echo "Installation successful."
}

# Verify Kindle environment
if ! is_kindle; then
    echo "Error: This script must run on a Kindle device." >&2
    exit 1
fi

# Get version
VERSION=$(get_version) || exit 1
echo "Installing KindleFetch version: $VERSION"

# Backup config before installation
backup_config

# Perform installation
if ! install_kindlefetch; then
    echo "Installation failed. Attempting to restore config..."
    restore_config
    cleanup
    exit 1
fi

# Create version file
create_version_file "$VERSION"

# Restore config after successful installation
restore_config

# Final cleanup
cleanup

echo "KindleFetch installation completed successfully."
echo "Version ${VERSION} installed at ${INSTALL_DIR}"