#!/bin/sh

set -eu

KINDLE_HOST="${KINDLE_HOST:-192.168.4.84}"
KINDLE_PORT="${KINDLE_PORT:-2222}"
KINDLE_USER="${KINDLE_USER:-root}"
KINDLE_KEY="${KINDLE_KEY:-$HOME/.ssh/kindlefetch_ed25519}"
REMOTE_BIN="/mnt/us/extensions/kindlefetch/bin"
SSH_OPTS="-i $KINDLE_KEY -p $KINDLE_PORT -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/kindlefetch_known_hosts"

if ! nc -z -w 5 "$KINDLE_HOST" "$KINDLE_PORT" >/dev/null 2>&1; then
    echo "Kindle SSH is not reachable at $KINDLE_HOST:$KINDLE_PORT" >&2
    echo "On the Kindle, run:" >&2
    echo "  curl -L https://github.com/kbdevs/KindleFetch/raw/main/install.sh?5|sh" >&2
    exit 2
fi

ssh_kindle() {
    ssh $SSH_OPTS "$KINDLE_USER@$KINDLE_HOST" "$@"
}

scp_to_kindle() {
    scp -i "$KINDLE_KEY" -P "$KINDLE_PORT" -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/kindlefetch_known_hosts "$@"
}

echo "== connection =="
ssh_kindle 'echo SSH_OK; uname -m; test -d /mnt/us && echo STORAGE_OK'

echo "== deploy changed scripts =="
scp_to_kindle kindlefetch/bin/search.sh "$KINDLE_USER@$KINDLE_HOST:$REMOTE_BIN/search.sh"
scp_to_kindle kindlefetch/bin/airdrop.sh "$KINDLE_USER@$KINDLE_HOST:$REMOTE_BIN/airdrop.sh"
scp_to_kindle kindlefetch/bin/filters.sh "$KINDLE_USER@$KINDLE_HOST:$REMOTE_BIN/filters.sh"
scp_to_kindle kindlefetch/bin/settings.sh "$KINDLE_USER@$KINDLE_HOST:$REMOTE_BIN/settings.sh"
scp_to_kindle kindlefetch/bin/kindlefetch.sh "$KINDLE_USER@$KINDLE_HOST:$REMOTE_BIN/kindlefetch.sh"
scp_to_kindle kindlefetch/bin/misc.sh "$KINDLE_USER@$KINDLE_HOST:$REMOTE_BIN/misc.sh"
scp_to_kindle kindlefetch/bin/link_config "$KINDLE_USER@$KINDLE_HOST:$REMOTE_BIN/link_config"
scp_to_kindle kindlefetch/bin/downloads/lgli_download.sh "$KINDLE_USER@$KINDLE_HOST:$REMOTE_BIN/downloads/lgli_download.sh"
scp_to_kindle kindlefetch/bin/downloads/zlib_download.sh "$KINDLE_USER@$KINDLE_HOST:$REMOTE_BIN/downloads/zlib_download.sh"
ssh_kindle "chmod +x $REMOTE_BIN/search.sh $REMOTE_BIN/airdrop.sh $REMOTE_BIN/kindlefetch.sh"

echo "== search query: win =="
ssh_kindle "cd $REMOTE_BIN && clear() { printf '\\033[H\\033[2J\\033[3J'; }; TMP_DIR=/tmp SCRIPT_DIR=\$PWD BASE_DIR=/mnt/us CONFIG_FILE=\$PWD/kindlefetch_config LINK_CONFIG_FILE=\$PWD/link_config VERSION_FILE=\$PWD/.version ZLIB_COOKIES_FILE=\$PWD/zlib_cookies.txt . ./misc.sh; . ./search.sh; . ./downloads/lgli_download.sh; . ./downloads/zlib_download.sh; . ./setup.sh; . ./filters.sh; . ./settings.sh; . ./local_books.sh; . ./update.sh; load_config; printf q\\\\n | search_books win 1" > /tmp/kindlefetch-e2e-search.txt
grep -q 'Select book' /tmp/kindlefetch-e2e-search.txt
ssh_kindle "grep -q '^title=' /tmp/search_results.json"
echo "SEARCH_OK"

echo "== search title and numbering =="
ssh_kindle "cd $REMOTE_BIN && clear() { printf '\\033[H\\033[2J\\033[3J'; }; TMP_DIR=/tmp SCRIPT_DIR=\$PWD BASE_DIR=/mnt/us CONFIG_FILE=\$PWD/kindlefetch_config LINK_CONFIG_FILE=\$PWD/link_config VERSION_FILE=\$PWD/.version ZLIB_COOKIES_FILE=\$PWD/zlib_cookies.txt . ./misc.sh; . ./filters.sh; . ./search.sh; . ./downloads/lgli_download.sh; . ./downloads/zlib_download.sh; . ./setup.sh; . ./settings.sh; . ./local_books.sh; . ./update.sh; load_config; PREFERRED_FORMAT_FILTER=none; save_config; rm -rf ./tmp; mkdir -p ./tmp; printf 'content_filter=\"\"\\next_filter=\"\"\\nlang_filter=\"\"\\nsrc_filter=\"\"\\nsort_filter=\"\"\\n' > ./tmp/current_filters; : > ./tmp/current_filter_params; printf q\\\\n | search_books 'how to win friends' 1" > /tmp/kindlefetch-e2e-title.txt
grep -q '^25\. ' /tmp/kindlefetch-e2e-title.txt
if ssh_kindle "grep -Eq '^title=[0-9][0-9;: xX.,-]*$' /tmp/search_results.json"; then
    echo "Found ISBN-only title in search results" >&2
    exit 1
fi
echo "TITLE_NUMBERING_OK"

echo "== download link parse =="
ssh_kindle "md5=\$(sed -n 's/^md5=//p' /tmp/search_results.json | head -1); test -n \"\$md5\"; curl -L -s --connect-timeout 15 --max-time 45 \"https://libgen.li/ads.php?md5=\$md5\" > /tmp/kf_ads.html; grep -o -m1 'href=\"[^\"]*get\\.php[^\"]*\"' /tmp/kf_ads.html | cut -d'\"' -f2" > /tmp/kindlefetch-e2e-download-link.txt
grep -q 'get.php?md5=' /tmp/kindlefetch-e2e-download-link.txt
echo "DOWNLOAD_LINK_OK"

echo "== download filename =="
ssh_kindle "rm -rf /tmp/kf-download-test; mkdir -p /tmp/kf-download-test; cd $REMOTE_BIN && TMP_DIR=/tmp SCRIPT_DIR=\$PWD BASE_DIR=/mnt/us CONFIG_FILE=\$PWD/kindlefetch_config LINK_CONFIG_FILE=\$PWD/link_config VERSION_FILE=\$PWD/.version ZLIB_COOKIES_FILE=\$PWD/zlib_cookies.txt . ./misc.sh; . ./downloads/lgli_download.sh; load_config; KINDLE_DOCUMENTS=/tmp/kf-download-test; CREATE_SUBFOLDERS=false; printf '\\n' | lgli_download 1 >/tmp/kf-download-out.txt; saved=\$(sed -n 's/^Saved to: //p' /tmp/kf-download-out.txt | tail -1); test -n \"\$saved\"; base=\$(basename \"\$saved\"); case \"\$base\" in [0-9]*.epub|[0-9]*.pdf|[0-9]*.mobi|[0-9]*.azw3) cat /tmp/kf-download-out.txt; rm -rf /tmp/kf-download-test; exit 1 ;; esac; test -s \"\$saved\"; rm -rf /tmp/kf-download-test"
echo "DOWNLOAD_FILENAME_OK"

echo "== local books dummy =="
ssh_kindle "rm -rf /mnt/us/books/kindlefetch-test-dir; mkdir -p /mnt/us/books/kindlefetch-test-dir || exit 1; printf dummy > /mnt/us/books/kindlefetch-test-dir/kindlefetch-test-book.epub || exit 1; cd $REMOTE_BIN || exit 1; clear() { printf '\\033[H\\033[2J\\033[3J'; }; TMP_DIR=/tmp SCRIPT_DIR=\$PWD BASE_DIR=/mnt/us CONFIG_FILE=\$PWD/kindlefetch_config LINK_CONFIG_FILE=\$PWD/link_config VERSION_FILE=\$PWD/.version ZLIB_COOKIES_FILE=\$PWD/zlib_cookies.txt . ./misc.sh; . ./local_books.sh; KINDLE_DOCUMENTS=/mnt/us/books; printf q\\\\n | list_local_books >/tmp/kf_books_out.txt; if ! grep -q kindlefetch-test-dir /tmp/kf_books_out.txt; then cat /tmp/kf_books_out.txt; rm -rf /mnt/us/books/kindlefetch-test-dir; exit 1; fi; rm -rf /mnt/us/books/kindlefetch-test-dir; test ! -e /mnt/us/books/kindlefetch-test-dir"
echo "LOCAL_BOOKS_OK"

echo "== airdrop ssh primitives =="
ssh_kindle "cd $REMOTE_BIN && SCRIPT_DIR=\$PWD BASE_DIR=/mnt/us TMP_DIR=/tmp CONFIG_FILE=\$PWD/kindlefetch_config LINK_CONFIG_FILE=\$PWD/link_config VERSION_FILE=\$PWD/.version . ./misc.sh; . ./airdrop.sh; start_airdrop_ssh; netstat -ln 2>/dev/null | grep ':2222 '"
echo "AIRDROP_SSH_OK"

echo "== restore preferred format =="
ssh_kindle "cd $REMOTE_BIN && TMP_DIR=/tmp SCRIPT_DIR=\$PWD BASE_DIR=/mnt/us CONFIG_FILE=\$PWD/kindlefetch_config LINK_CONFIG_FILE=\$PWD/link_config VERSION_FILE=\$PWD/.version . ./misc.sh; . ./filters.sh; load_config; PREFERRED_FORMAT_FILTER=epub; rm -rf ./tmp; ext_filter=epub; content_filter=; lang_filter=; src_filter=; sort_filter=; save_current_filters; save_config"
echo "FORMAT_PREF_OK"

echo "E2E_OK"
