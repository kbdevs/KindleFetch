#!/bin/sh

set -e

# Check if running on a Kindle
if ! { [ -f "/etc/prettyversion.txt" ] || [ -d "/mnt/us" ] || pgrep "lipc-daemon" >/dev/null; }; then
    echo -n "This script must run on a Kindle device. Do you want to run it anyway? [y/N]: "
    read -r kindle_override_choice
    if [ "$kindle_override_choice" = "y" ] || [ "$kindle_override_choice" = "Y" ]; then
        :
    else
        exit 1
    fi
fi

# Variables
KF_REPO_OWNER="${KF_REPO_OWNER:-kbdevs}"
KF_REPO_NAME="${KF_REPO_NAME:-kindlefetch}"
KF_REPO_BRANCH="${KF_REPO_BRANCH:-main}"
KF_REPO_SLUG="${KF_REPO_OWNER}/${KF_REPO_NAME}"
API_URL="https://api.github.com/repos/${KF_REPO_SLUG}/commits?per_page=1"
REPO_URL="https://github.com/${KF_REPO_SLUG}/archive/refs/heads/${KF_REPO_BRANCH}.zip"
ZIP_FILE="/mnt/us/repo.zip"
EXTRACTED_DIR="/mnt/us/${KF_REPO_NAME}-${KF_REPO_BRANCH}"
INSTALL_DIR="/mnt/us/extensions/kindlefetch"
CONFIG_FILE="$INSTALL_DIR/bin/kindlefetch_config"
TEMP_CONFIG="/mnt/us/kindlefetch_config"
ZLIB_COOKIES_FILE="$INSTALL_DIR/bin/zlib_cookies.txt"
TEMP_ZLIB_COOKIES_FILE="/mnt/us/zlib_cookies.txt"
VERSION_FILE="$INSTALL_DIR/bin/.version"

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

if [ -f "$CONFIG_FILE" ]; then
    echo "Backing up existing config..."
    cp -f "$CONFIG_FILE" "$TEMP_CONFIG"
fi

if [ -f "$ZLIB_COOKIES_FILE" ]; then
    echo "Backing up existing zlib cookies..."
    cp -f "$ZLIB_COOKIES_FILE" "$TEMP_ZLIB_COOKIES_FILE"
fi

echo "Downloading KindleFetch from ${KF_REPO_SLUG}/${KF_REPO_BRANCH}..."
curl -fsSL -o "$ZIP_FILE" "$REPO_URL"
echo "Download complete."

echo "Extracting files..."
unzip -o "$ZIP_FILE" -d "/mnt/us"
echo "Extraction complete."
rm -f "$ZIP_FILE"

echo "Removing old installation..."
rm -rf "$INSTALL_DIR"

echo "Installing KindleFetch..."
mkdir -p "$INSTALL_DIR"
mv -f "$EXTRACTED_DIR/kindlefetch"/* "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/run.sh" "$INSTALL_DIR"/bin/*.sh "$INSTALL_DIR"/bin/downloads/*.sh 2>/dev/null || true
echo "Installation successful."

echo "Creating version file..."
VERSION=$(get_version)
mkdir -p "$INSTALL_DIR/bin"
echo "$VERSION" > "$VERSION_FILE"

if [ -f "$TEMP_CONFIG" ]; then
    echo "Restoring configuration..."
    mv -f "$TEMP_CONFIG" "$CONFIG_FILE"
fi

if [ -f "$TEMP_ZLIB_COOKIES_FILE" ]; then
    echo "Restoring zlib cookies..."
    mv -f "$TEMP_ZLIB_COOKIES_FILE" "$ZLIB_COOKIES_FILE"
fi

echo "Cleaning up..."
rm -rf "$EXTRACTED_DIR"

echo "KindleFetch installation completed successfully. Version: $VERSION"
