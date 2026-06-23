#!/bin/sh

set -eu

KINDLE_HOST="${KINDLE_HOST:-192.168.4.75}"
KINDLE_PORT="${KINDLE_PORT:-2222}"
KINDLE_USER="${KINDLE_USER:-root}"
KINDLE_KEY="${KINDLE_KEY:-/tmp/kindlefetch_ssh_key}"
REMOTE_BIN="/mnt/us/extensions/kindlefetch/bin"
SSH_OPTS="-i $KINDLE_KEY -p $KINDLE_PORT -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/kindlefetch_known_hosts"

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
    scp -i "$KINDLE_KEY" -P "$KINDLE_PORT" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/kindlefetch_known_hosts "$@"
}

echo "== connection =="
ssh_kindle 'echo SSH_OK; uname -m; test -d /mnt/us && echo STORAGE_OK'

echo "== deploy changed scripts =="
scp_to_kindle kindlefetch/bin/search.sh "$KINDLE_USER@$KINDLE_HOST:$REMOTE_BIN/search.sh"
scp_to_kindle kindlefetch/bin/airdrop.sh "$KINDLE_USER@$KINDLE_HOST:$REMOTE_BIN/airdrop.sh"
ssh_kindle "chmod +x $REMOTE_BIN/search.sh $REMOTE_BIN/airdrop.sh"

echo "== search query: win =="
ssh_kindle "cd $REMOTE_BIN && TMP_DIR=/tmp SCRIPT_DIR=\$PWD BASE_DIR=/mnt/us CONFIG_FILE=\$PWD/kindlefetch_config LINK_CONFIG_FILE=\$PWD/link_config VERSION_FILE=\$PWD/.version ZLIB_COOKIES_FILE=\$PWD/zlib_cookies.txt . ./misc.sh; . ./search.sh; . ./downloads/lgli_download.sh; . ./downloads/zlib_download.sh; . ./setup.sh; . ./filters.sh; . ./settings.sh; . ./local_books.sh; . ./update.sh; load_config; printf q\\\\n | search_books win 1" > /tmp/kindlefetch-e2e-search.txt
grep -q '1-25: Select book' /tmp/kindlefetch-e2e-search.txt
echo "SEARCH_OK"

echo "== download link parse =="
ssh_kindle "md5=\$(sed -n 's/^md5=//p' /tmp/search_results.json | head -1); test -n \"\$md5\"; curl -L -s --connect-timeout 15 --max-time 45 \"https://libgen.li/ads.php?md5=\$md5\" > /tmp/kf_ads.html; grep -o -m1 'href=\"[^\"]*get\\.php[^\"]*\"' /tmp/kf_ads.html | cut -d'\"' -f2" > /tmp/kindlefetch-e2e-download-link.txt
grep -q 'get.php?md5=' /tmp/kindlefetch-e2e-download-link.txt
echo "DOWNLOAD_LINK_OK"

echo "== local books dummy =="
ssh_kindle "rm -rf /mnt/us/books/kindlefetch-test-dir; mkdir -p /mnt/us/books/kindlefetch-test-dir || exit 1; printf dummy > /mnt/us/books/kindlefetch-test-dir/kindlefetch-test-book.epub || exit 1; cd $REMOTE_BIN || exit 1; TMP_DIR=/tmp SCRIPT_DIR=\$PWD BASE_DIR=/mnt/us CONFIG_FILE=\$PWD/kindlefetch_config LINK_CONFIG_FILE=\$PWD/link_config VERSION_FILE=\$PWD/.version ZLIB_COOKIES_FILE=\$PWD/zlib_cookies.txt . ./misc.sh; . ./local_books.sh; KINDLE_DOCUMENTS=/mnt/us/books; printf q\\\\n | list_local_books >/tmp/kf_books_out.txt; if ! grep -q kindlefetch-test-dir /tmp/kf_books_out.txt; then cat /tmp/kf_books_out.txt; rm -rf /mnt/us/books/kindlefetch-test-dir; exit 1; fi; rm -rf /mnt/us/books/kindlefetch-test-dir; test ! -e /mnt/us/books/kindlefetch-test-dir"
echo "LOCAL_BOOKS_OK"

echo "== airdrop ssh primitives =="
ssh_kindle "cd $REMOTE_BIN && SCRIPT_DIR=\$PWD BASE_DIR=/mnt/us TMP_DIR=/tmp CONFIG_FILE=\$PWD/kindlefetch_config LINK_CONFIG_FILE=\$PWD/link_config VERSION_FILE=\$PWD/.version . ./misc.sh; . ./airdrop.sh; start_airdrop_ssh; netstat -ln 2>/dev/null | grep ':2222 '"
echo "AIRDROP_SSH_OK"

echo "E2E_OK"
