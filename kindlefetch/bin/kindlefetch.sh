#!/bin/sh

# KindleFetch

# Variables
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CONFIG_FILE="$SCRIPT_DIR/kindlefetch_config"
LINK_CONFIG_FILE="$SCRIPT_DIR/link_config"
VERSION_FILE="$SCRIPT_DIR/.version"
ZLIB_COOKIES_FILE="$SCRIPT_DIR/zlib_cookies.txt"
TMP_DIR="/tmp"
BASE_DIR="/mnt/us"

UPDATE_AVAILABLE=false
CREATE_SUBFOLDERS=false
COMPACT_OUTPUT=false
RESULTS_PER_PAGE=10

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

# Script imports
. "$SCRIPT_DIR/downloads/zlib_download.sh"
. "$SCRIPT_DIR/downloads/lgli_download.sh"
. "$SCRIPT_DIR/filters.sh"
. "$SCRIPT_DIR/search.sh"
. "$SCRIPT_DIR/misc.sh"
. "$SCRIPT_DIR/local_books.sh"
. "$SCRIPT_DIR/airdrop.sh"
. "$SCRIPT_DIR/update.sh"
. "$SCRIPT_DIR/setup.sh"
. "$SCRIPT_DIR/settings.sh"

load_config
configure_update_channel
check_for_updates

[ -z "$LGLI_URL" ] && LGLI_URL=$(find_working_url $LGLI_MIRROR_URLS)
[ -z "$ZLIB_URL" ] && ZLIB_URL=$(find_working_url $ZLIB_MIRROR_URLS)

save_config

main_menu() {
    if [ "${ENFORCE_DNS}" = true ];
    	then change_dns
    fi
    
    while true; do
        draw_header "Main Menu" "$(load_version) | https://github.com/${KF_REPO_SLUG}"
        if $UPDATE_AVAILABLE; then
            echo "[!] Update available. Use option 7 to install it."
            echo
        fi
        echo "1. Search and download"
        echo "2. Filters"
        echo "3. My books"
        echo "4. AirDrop"
        echo "5. Settings"
        echo "6. Start SSH"
        if $UPDATE_AVAILABLE; then
            echo
            echo "7. Install update"
        fi
        echo
        echo "q. Exit"
        echo
        echo -n "Choose option: "
        read -r choice
        
        case "$choice" in
            1)
                search_books
                ;;
            2)
                filters_menu
                ;;
            3)
                list_local_books
                ;;
            4)
                airdrop_menu
                ;;
            5)
                settings_menu
                ;;
            6)
                ssh_menu
                ;;
            [qQ])
                cleanup
                exit 0
                ;;
            7)
                if $UPDATE_AVAILABLE; then
                    update
                fi
                ;;
            *)
                echo "Invalid option"
                sleep 2
                ;;
        esac
    done
}

trap cleanup EXIT
main_menu
