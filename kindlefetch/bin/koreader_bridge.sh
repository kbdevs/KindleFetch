#!/bin/sh

SCRIPT_DIR="${SCRIPT_DIR:-/mnt/us/extensions/kindlefetch/bin}"
TMP_DIR="${TMP_DIR:-/tmp}"
BASE_DIR="${BASE_DIR:-/mnt/us}"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/kindlefetch_config}"
LINK_CONFIG_FILE="${LINK_CONFIG_FILE:-$SCRIPT_DIR/link_config}"
VERSION_FILE="${VERSION_FILE:-$SCRIPT_DIR/.version}"
ZLIB_COOKIES_FILE="${ZLIB_COOKIES_FILE:-$SCRIPT_DIR/zlib_cookies.txt}"

clear() {
    :
}

. "$SCRIPT_DIR/misc.sh" || exit 1
. "$SCRIPT_DIR/filters.sh" || exit 1
. "$SCRIPT_DIR/search.sh" || exit 1
. "$SCRIPT_DIR/downloads/lgli_download.sh" || exit 1
. "$SCRIPT_DIR/downloads/zlib_download.sh" || exit 1
. "$SCRIPT_DIR/setup.sh" || exit 1
. "$SCRIPT_DIR/settings.sh" || exit 1
. "$SCRIPT_DIR/local_books.sh" || exit 1
. "$SCRIPT_DIR/update.sh" || exit 1

load_config

command="$1"
shift || true

case "$command" in
    search)
        query="$*"
        [ -n "$query" ] || {
            echo "Missing search query" >&2
            exit 1
        }
        COMPACT_OUTPUT=true
        printf 'q\n' | search_books "$query" 1
        ;;
    download)
        choice="$1"
        case "$choice" in
            *[!0-9]*|"")
                echo "Invalid result number" >&2
                exit 1
                ;;
        esac
        [ -f "$TMP_DIR/search_results.json" ] || {
            echo "Search first, then download." >&2
            exit 1
        }
        index="$(selection_to_download_index "$choice" "$TMP_DIR/search_results.json")"
        [ -n "$index" ] || {
            echo "Invalid result number" >&2
            exit 1
        }
        printf '\n' | lgli_download "$index"
        ;;
    *)
        echo "Usage: $0 search QUERY | download NUMBER" >&2
        exit 1
        ;;
esac
