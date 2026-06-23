#!/bin/sh

set -e

KF_REPO_OWNER="${KF_REPO_OWNER:-kbdevs}"
KF_REPO_NAME="${KF_REPO_NAME:-KindleFetch}"
KF_REPO_BRANCH="${KF_REPO_BRANCH:-main}"
KF_REPO_SLUG="${KF_REPO_OWNER}/${KF_REPO_NAME}"
K_SCRIPT="/tmp/k.sh"
K_URL="https://github.com/${KF_REPO_SLUG}/raw/${KF_REPO_BRANCH}/k.sh"

echo "Starting Kindle command server..."
echo "Downloading: $K_URL"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$K_SCRIPT" "$K_URL"
elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$K_SCRIPT" "$K_URL"
else
    echo "Need curl or wget to download k.sh."
    exit 1
fi

chmod +x "$K_SCRIPT" 2>/dev/null || true
sh "$K_SCRIPT"
