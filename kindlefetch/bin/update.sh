#!/bin/sh

update() {
	if [ "$UPDATE_AVAILABLE" = true ]; then
        if yes_no "Install update from ${KF_REPO_SLUG}/${KF_REPO_BRANCH}?" "yes"; then
            echo "Installing update..."
            if curl -fsSL "${KF_RAW_BASE}/install-full.sh" | sh; then
                echo "Update installed successfully!"
                UPDATE_AVAILABLE=false
                VERSION=$(load_version)
                exit 0
            else
                echo "Failed to install update"
                pause
            fi
        fi
    else
        echo "You're up-to-date!"
        pause
    fi
}
