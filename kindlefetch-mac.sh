#!/bin/sh

set -u

KINDLE_HOST="${KINDLE_HOST:-192.168.4.75}"
KINDLE_PORT="${KINDLE_PORT:-2222}"
KINDLE_USER="${KINDLE_USER:-root}"
KINDLE_KEY="${KINDLE_KEY:-/tmp/kindlefetch_ssh_key}"
REMOTE_BIN="${REMOTE_BIN:-/mnt/us/extensions/kindlefetch/bin}"
KF_INSTALL_URL="${KF_INSTALL_URL:-https://github.com/kbdevs/KindleFetch/raw/main/install.sh}"

SSH_OPTS="-i $KINDLE_KEY -p $KINDLE_PORT -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/kindlefetch_known_hosts"

usage() {
    cat <<EOF
KindleFetch Mac CLI

Usage:
  ./kindlefetch-mac.sh search "query" [page]
  ./kindlefetch-mac.sh download "query" [page]
  ./kindlefetch-mac.sh update
  ./kindlefetch-mac.sh ssh

Defaults:
  KINDLE_HOST=$KINDLE_HOST
  KINDLE_PORT=$KINDLE_PORT
  KINDLE_KEY=$KINDLE_KEY

Override example:
  KINDLE_HOST=192.168.4.75 ./kindlefetch-mac.sh download "win"
EOF
}

shell_quote() {
    printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

ssh_kindle() {
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "$KINDLE_USER@$KINDLE_HOST" "$@"
}

check_connection() {
    if command -v nc >/dev/null 2>&1; then
        if ! nc -z -w 5 "$KINDLE_HOST" "$KINDLE_PORT" >/dev/null 2>&1; then
            echo "Kindle SSH is not reachable at $KINDLE_HOST:$KINDLE_PORT" >&2
            echo "Start SSH from KindleFetch option 6 or KOReader, then retry." >&2
            return 1
        fi
    fi

    if ! ssh_kindle 'test -d /mnt/us && echo OK' >/dev/null; then
        echo "Could not connect to $KINDLE_USER@$KINDLE_HOST:$KINDLE_PORT" >&2
        return 1
    fi
}

remote_kf_prefix() {
    cat <<'EOF'
TMP_DIR=/tmp
SCRIPT_DIR=$PWD
BASE_DIR=/mnt/us
CONFIG_FILE=$PWD/kindlefetch_config
LINK_CONFIG_FILE=$PWD/link_config
VERSION_FILE=$PWD/.version
ZLIB_COOKIES_FILE=$PWD/zlib_cookies.txt
clear() {
    printf '\033[H\033[2J\033[3J'
}
. ./misc.sh || exit 1
. ./search.sh || exit 1
. ./downloads/lgli_download.sh || exit 1
. ./downloads/zlib_download.sh || exit 1
. ./setup.sh || exit 1
. ./filters.sh || exit 1
. ./settings.sh || exit 1
. ./local_books.sh || exit 1
. ./update.sh || exit 1
load_config
EOF
}

search_remote() {
    query="$1"
    page="${2:-1}"
    check_connection || return 1

    q_query="$(shell_quote "$query")"
    q_page="$(shell_quote "$page")"
    q_remote_bin="$(shell_quote "$REMOTE_BIN")"

    {
        printf 'QUERY=%s\n' "$q_query"
        printf 'PAGE=%s\n' "$q_page"
        printf 'cd %s || exit 1\n' "$q_remote_bin"
        remote_kf_prefix
        printf "printf 'q\\\\n' | search_books \"\$QUERY\" \"\$PAGE\"\n"
    } | ssh_kindle 'sh -s'
}

download_remote_choice() {
    choice="$1"
    check_connection || return 1

    q_choice="$(shell_quote "$choice")"
    q_remote_bin="$(shell_quote "$REMOTE_BIN")"

    {
        printf 'CHOICE=%s\n' "$q_choice"
        printf 'cd %s || exit 1\n' "$q_remote_bin"
        remote_kf_prefix
        cat <<'EOF'
COUNT="$(grep -E '"title"[[:space:]]*:|^title=' "$TMP_DIR/search_results.json" | wc -l | tr -d ' ')"
case "$CHOICE" in
    *[!0-9]*|"") echo "Invalid result number" >&2; exit 1 ;;
esac
DOWNLOAD_INDEX="$(awk -v choice="$CHOICE" 'BEGIN { RS="\\{"; FS="\\}"; pos=0 } NR > 1 { pos++; if ($1 ~ "(^|\n)source_rank=" choice "(\n|$)") { print pos; exit } }' "$TMP_DIR/search_results.json")"
if [ -z "$DOWNLOAD_INDEX" ]; then
    shown="$(sed -n 's/^source_rank=//p' "$TMP_DIR/search_results.json" | tr '\n' ' ')"
    echo "Invalid result number. Choose one of: $shown" >&2
    exit 1
fi
printf '\n' | lgli_download "$DOWNLOAD_INDEX"
EOF
    } | ssh_kindle 'sh -s'
}

download_interactive() {
    query="${1:-}"
    page="${2:-1}"

    if [ -z "$query" ]; then
        printf 'Search query: '
        read -r query
    fi
    [ -n "$query" ] || {
        echo "Search query cannot be empty" >&2
        return 1
    }

    search_remote "$query" "$page" || return 1

    printf '\nEnter result number to download to the Kindle, or q to quit: '
    read -r choice
    case "$choice" in
        q|Q|"") return 0 ;;
        *[!0-9]*)
            echo "Invalid result number" >&2
            return 1
            ;;
    esac

    download_remote_choice "$choice"
}

update_remote() {
    check_connection || return 1
    q_url="$(shell_quote "$KF_INSTALL_URL")"
    ssh_kindle "curl -L $q_url | sh"
}

cmd="${1:-download}"
[ "$#" -gt 0 ] && shift || true

case "$cmd" in
    search)
        [ "${1:-}" ] || {
            usage
            exit 1
        }
        search_remote "$1" "${2:-1}"
        ;;
    download)
        download_interactive "${1:-}" "${2:-1}"
        ;;
    update|install)
        update_remote
        ;;
    ssh)
        check_connection || exit 1
        # shellcheck disable=SC2086
        ssh $SSH_OPTS "$KINDLE_USER@$KINDLE_HOST"
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
