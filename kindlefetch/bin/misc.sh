#!/bin/sh

KF_REPO_OWNER="${KF_REPO_OWNER:-kbdevs}"
KF_REPO_NAME="${KF_REPO_NAME:-KindleFetch}"
KF_REPO_BRANCH="${KF_REPO_BRANCH:-main}"
configure_update_channel() {
    KF_REPO_OWNER="${KF_REPO_OWNER:-kbdevs}"
    KF_REPO_NAME="${KF_REPO_NAME:-KindleFetch}"
    KF_REPO_BRANCH="${KF_REPO_BRANCH:-main}"
    KF_REPO_SLUG="${KF_REPO_OWNER}/${KF_REPO_NAME}"
    KF_GITHUB_API="https://api.github.com/repos/${KF_REPO_SLUG}"
    KF_RAW_BASE="https://raw.githubusercontent.com/${KF_REPO_SLUG}/${KF_REPO_BRANCH}"
    KF_ARCHIVE_URL="https://github.com/${KF_REPO_SLUG}/archive/refs/heads/${KF_REPO_BRANCH}.zip"
}

configure_update_channel

draw_header() {
    title="$1"
    subtitle="$2"
    clear
    printf '%s\n' '================================================'
    printf ' KindleFetch'
    [ -n "$title" ] && printf ' - %s' "$title"
    printf '\n'
    [ -n "$subtitle" ] && printf ' %s\n' "$subtitle"
    printf '%s\n\n' '================================================'
}

pause() {
    printf '\nPress Enter to continue...'
    read -r _
}

yes_no() {
    prompt="$1"
    default="$2"
    if [ "$default" = "yes" ]; then
        suffix="[Y/n]"
    else
        suffix="[y/N]"
    fi

    printf '%s %s: ' "$prompt" "$suffix"
    read -r answer
    case "$answer" in
        y|Y|yes|YES) return 0 ;;
        n|N|no|NO) return 1 ;;
        "") [ "$default" = "yes" ] ;;
        *) return 1 ;;
    esac
}

change_dns () {
    RESOLV_FILE="/var/run/resolv.conf"
    
    if [ ! -f "$RESOLV_FILE" ]; then
        exit 1
    fi

    sed -i '/^nameserver/d' "$RESOLV_FILE"

    echo "nameserver 1.1.1.1" >> "$RESOLV_FILE"
    echo "nameserver 1.0.0.1" >> "$RESOLV_FILE"
}

load_config() {
    if [ -f "$LINK_CONFIG_FILE" ]; then
        eval "$(base64 -d < "$LINK_CONFIG_FILE" 2>/dev/null || base64 -D < "$LINK_CONFIG_FILE" 2>/dev/null || true)"
    fi
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    else
        first_time_setup
    fi
}

load_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        get_version
    fi
}

sanitize_filename() {
    echo "$1" | sed -e 's/[^[:alnum:]\._-]/_/g' -e 's/ /_/g'
}

get_json_value() {
    value="$(printf "%s\n" "$1" | sed -n "s/^$2=//p" | head -1)"
    if [ -n "$value" ]; then
        printf "%s\n" "$value"
        return 0
    fi

    echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\"/\1/" || \
    echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*[^,}]*" | sed "s/\"$2\"[[:space:]]*:[[:space:]]*\([^,}]*\)/\1/"
}

ensure_config_dir() {
    local config_dir="$(dirname "$CONFIG_FILE")"
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
    fi
}

cleanup() {
    rm -f "$TMP_DIR"/kindle_books.list \
          "$TMP_DIR"/kindle_folders.list \
          "$TMP_DIR"/search_results.json \
          "$TMP_DIR"/last_search_*
}

get_version() {
    local api_response="$(curl -s -H "Accept: application/vnd.github.v3+json" "${KF_GITHUB_API}/commits?per_page=1")" || {
        echo "Failed to fetch version from GitHub API" >&2
        echo "unknown"
        return
    }

    local latest_sha="$(echo "$api_response" | grep -m1 '"sha":' | cut -d'"' -f4 | cut -c1-7)"
    
    echo "$latest_sha" > "$VERSION_FILE"
    load_version
}

check_for_updates() {
    local current_sha="$(load_version)"
    
    local latest_sha="$(curl -s -H "Accept: application/vnd.github.v3+json" \
        -H "Cache-Control: no-cache" \
        "${KF_GITHUB_API}/commits?per_page=1" | \
        grep -oE '"sha": "[0-9a-f]+"' | head -1 | cut -d'"' -f4 | cut -c1-7)"
    
    if [ -n "$latest_sha" ] && [ "$current_sha" != "$latest_sha" ]; then
        UPDATE_AVAILABLE=true
        return 0
    else
        return 1
    fi
}

save_config() {
    {
        echo "KINDLE_DOCUMENTS=\"$KINDLE_DOCUMENTS\""
        echo "CREATE_SUBFOLDERS=\"$CREATE_SUBFOLDERS\""
        echo "DEBUG_MODE=\"$DEBUG_MODE\""
        echo "COMPACT_OUTPUT=\"$COMPACT_OUTPUT\""
        echo "ENFORCE_DNS=\"$ENFORCE_DNS\""
        echo "ZLIB_AUTH=\"$ZLIB_AUTH\""
        echo "ZLIB_USERNAME=\"$ZLIB_USERNAME\""
        echo "RESULTS_PER_PAGE=\"$RESULTS_PER_PAGE\""
        echo "ANNAS_URL=\"$ANNAS_URL\""
        echo "LGLI_URL=\"$LGLI_URL\""
        echo "ZLIB_URL=\"$ZLIB_URL\""
        echo "KF_REPO_OWNER=\"$KF_REPO_OWNER\""
        echo "KF_REPO_NAME=\"$KF_REPO_NAME\""
        echo "KF_REPO_BRANCH=\"$KF_REPO_BRANCH\""
    } > "$CONFIG_FILE"
}

zlib_login() {
    local zlib_login="$1"
    local zlib_password="$2"

    printf '\nLogging in to Z-Library...'

    local response="$(curl -s -c "$ZLIB_COOKIES_FILE" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Accept: application/json" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        -X POST -d "email=$zlib_login&password=$zlib_password" \
        "$ZLIB_URL/eapi/user/login")"

    local zlib_username="$(get_json_value "$response" "name" | tr -d '\r\n')"

    if [ -n "$zlib_username" ]; then
        printf "\nSuccessfully logged in as $zlib_username!"
        ZLIB_USERNAME="$zlib_username"
        sleep 2
    else
        printf "\nLogin failed." >&2
        printf "\n$response" | head -n1
        sleep 2
        return 1
    fi
}

find_working_url() {
    for url in "$@"; do
        code=$(curl -s -o /dev/null -w '%{http_code}' \
               --max-time 2 -L "$url")

        [ "$code" = "000" ] && continue
        [ "$code" -ge 500 ] && continue

        echo "$url"
        return 0
    done
    return 1
}
