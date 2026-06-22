#!/bin/sh

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
BASE_DIR="${BASE_DIR:-/mnt/us}"
AIR_DROP_SERVER="$SCRIPT_DIR/airdrop_server.py"
VENDOR_DIR="$SCRIPT_DIR/vendor"

find_python() {
    for python_bin in python3 python /mnt/us/extensions/python/bin/python3 /mnt/us/extensions/python/bin/python /mnt/us/opt/bin/python3 /mnt/us/opt/bin/python /opt/bin/python3 /opt/bin/python; do
        if command -v "$python_bin" >/dev/null 2>&1; then
            echo "$python_bin"
            return 0
        elif [ -x "$python_bin" ]; then
            echo "$python_bin"
            return 0
        fi
    done
    return 1
}

install_python() {
    echo "Python was not found. Trying to install it..."
    echo

    if command -v opkg >/dev/null 2>&1; then
        opkg update && opkg install python3 && return 0
    fi

    if [ -x /mnt/us/opt/bin/opkg ]; then
        /mnt/us/opt/bin/opkg update && /mnt/us/opt/bin/opkg install python3 && return 0
    fi

    if [ -x /opt/bin/opkg ]; then
        /opt/bin/opkg update && /opt/bin/opkg install python3 && return 0
    fi

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y python3 && return 0
    fi

    if command -v apk >/dev/null 2>&1; then
        apk add --no-cache python3 && return 0
    fi

    if command -v yum >/dev/null 2>&1; then
        yum install -y python3 && return 0
    fi

    return 1
}

ensure_qr_support() {
    python_bin="$1"

    if PYTHONPATH="$VENDOR_DIR${PYTHONPATH:+:$PYTHONPATH}" "$python_bin" -c 'import qrcode' >/dev/null 2>&1; then
        return 0
    fi

    echo "QR support was not found. Installing it into KindleFetch..."
    mkdir -p "$VENDOR_DIR" 2>/dev/null || return 1

    if "$python_bin" -m pip --version >/dev/null 2>&1; then
        "$python_bin" -m pip install --target "$VENDOR_DIR" qrcode >/dev/null 2>&1 && return 0
    fi

    "$python_bin" -m ensurepip --user >/dev/null 2>&1 || true
    if "$python_bin" -m pip --version >/dev/null 2>&1; then
        "$python_bin" -m pip install --target "$VENDOR_DIR" qrcode >/dev/null 2>&1 && return 0
    fi

    if command -v opkg >/dev/null 2>&1; then
        opkg update && { opkg install python3-qrcode || opkg install py3-qrcode; } && return 0
    fi

    if [ -x /mnt/us/opt/bin/opkg ]; then
        /mnt/us/opt/bin/opkg update && { /mnt/us/opt/bin/opkg install python3-qrcode || /mnt/us/opt/bin/opkg install py3-qrcode; } && return 0
    fi

    if [ -x /opt/bin/opkg ]; then
        /opt/bin/opkg update && { /opt/bin/opkg install python3-qrcode || /opt/bin/opkg install py3-qrcode; } && return 0
    fi

    return 1
}

airdrop_menu() {
    python_bin="$(find_python)"
    if [ -z "$python_bin" ]; then
        draw_header "AirDrop" "Installing Python"
        if install_python; then
            python_bin="$(find_python)"
        fi
    fi

    if [ -z "$python_bin" ]; then
        draw_header "AirDrop" "Python install needed"
        echo "AirDrop needs Python to host uploads from another device."
        echo
        echo "I could not find or auto-install Python because no supported package manager was found."
        echo "Install Python for your jailbreak/Entware setup, then open AirDrop again."
        pause
        return 1
    fi

    ensure_qr_support "$python_bin" || {
        echo "Could not auto-install QR support. AirDrop will still show the URL."
        sleep 2
    }

    draw_header "AirDrop" "Local file manager"
    echo "Starting a temporary web file manager rooted at $BASE_DIR."
    echo "Anyone with the QR link can manage files until you stop this screen."
    echo
    echo "Press Ctrl+C to stop AirDrop."
    echo

    PYTHONPATH="$VENDOR_DIR${PYTHONPATH:+:$PYTHONPATH}" "$python_bin" "$AIR_DROP_SERVER" "$BASE_DIR"
    pause
}
