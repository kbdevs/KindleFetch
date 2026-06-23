#!/bin/sh

set -e

KF_REPO_OWNER="${KF_REPO_OWNER:-kbdevs}"
KF_REPO_NAME="${KF_REPO_NAME:-KindleFetch}"
KF_REPO_BRANCH="${KF_REPO_BRANCH:-main}"
KF_REPO_SLUG="${KF_REPO_OWNER}/${KF_REPO_NAME}"
KF_REPO_REF="${KF_REPO_REF:-}"
INSTALL_SCRIPT="/tmp/kindlefetch-install-full.sh"

if [ -z "$KF_REPO_REF" ]; then
    if command -v curl >/dev/null 2>&1; then
        KF_REPO_REF="$(curl -fsSL "https://api.github.com/repos/${KF_REPO_SLUG}/commits/${KF_REPO_BRANCH}" | sed -n 's/.*"sha": *"\([0-9a-f][0-9a-f]*\)".*/\1/p' | head -1)"
    fi
fi
[ -z "$KF_REPO_REF" ] && KF_REPO_REF="$KF_REPO_BRANCH"

INSTALL_URL="https://raw.githubusercontent.com/${KF_REPO_SLUG}/${KF_REPO_REF}/install-full.sh"

echo "Installing KindleFetch from ${KF_REPO_SLUG}/${KF_REPO_REF}..."
echo "Downloading: $INSTALL_URL"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$INSTALL_SCRIPT" "$INSTALL_URL"
elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$INSTALL_SCRIPT" "$INSTALL_URL"
else
    echo "Need curl or wget to download KindleFetch."
    exit 1
fi

chmod +x "$INSTALL_SCRIPT" 2>/dev/null || true
sh "$INSTALL_SCRIPT"
