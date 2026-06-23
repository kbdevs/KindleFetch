#!/bin/sh

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
BASE_DIR="${BASE_DIR:-/mnt/us}"
AIR_DROP_SERVER="$SCRIPT_DIR/airdrop_server.py"
VENDOR_DIR="$SCRIPT_DIR/vendor"
AIR_DROP_PORT="${KINDLEFETCH_AIRDROP_PORT:-8088}"

find_httpd() {
    if command -v httpd >/dev/null 2>&1; then
        echo "httpd"
        return 0
    fi
    if command -v busybox >/dev/null 2>&1; then
        echo "busybox httpd"
        return 0
    fi
    if [ -x /bin/busybox ]; then
        echo "/bin/busybox httpd"
        return 0
    fi
    return 1
}

get_lan_ips() {
    {
        ip addr 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1
        ifconfig 2>/dev/null | awk '/inet / {print $2}' | sed 's/addr://'
        hostname -I 2>/dev/null
    } | tr ' ' '\n' | awk '
        /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ &&
        $0 !~ /^127\./ &&
        $0 !~ /\.0$/ &&
        $0 !~ /\.255$/ &&
        !seen[$0]++ { print }
    '
}

make_token() {
    if command -v dd >/dev/null 2>&1 && [ -r /dev/urandom ]; then
        dd if=/dev/urandom bs=12 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
    else
        date +%s
    fi
}

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

start_busybox_airdrop() {
    httpd_cmd="$(find_httpd)" || return 1
    token="$(make_token)"
    web_root="/tmp/kindlefetch-airdrop-www"
    cgi_dir="$web_root/cgi-bin"
    pid_file="/tmp/kindlefetch-airdrop-httpd.pid"

    rm -rf "$web_root"
    mkdir -p "$cgi_dir" || return 1

    cat > "$web_root/index.html" <<EOF
<!doctype html>
<html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>KindleFetch AirDrop Lite</title>
<style>body{font-family:sans-serif;margin:20px;max-width:800px}textarea{width:100%;height:90px}pre{background:#111;color:#eee;padding:12px;white-space:pre-wrap;overflow:auto}button{padding:10px 14px}</style></head>
<body><h1>KindleFetch AirDrop Lite</h1><p>Root: $BASE_DIR</p>
<textarea id="cmd" placeholder="ls -la /mnt/us/documents"></textarea><br><button onclick="run()">Run</button><pre id="out"></pre>
<script>
var token="$token";
function run(){var c=document.getElementById('cmd').value;document.getElementById('out').textContent='Running...';fetch('/cgi-bin/run?token='+encodeURIComponent(token)+'&cmd='+encodeURIComponent(c)).then(r=>r.text()).then(t=>document.getElementById('out').textContent=t).catch(e=>document.getElementById('out').textContent=e)}
</script></body></html>
EOF

    cat > "$cgi_dir/run" <<EOF
#!/bin/sh
printf 'Content-Type: text/plain\r\n\r\n'
query="\$QUERY_STRING"
case "\$query" in
  token=$token\\&cmd=*) ;;
  *) echo "Bad token"; exit 0 ;;
esac
cmd=\$(printf '%s' "\$query" | sed 's/^token=$token&cmd=//' | sed 's/+/ /g;s/%20/ /g;s/%2F/\\//g;s/%2f/\\//g;s/%2D/-/g;s/%2d/-/g;s/%5F/_/g;s/%5f/_/g;s/%2E/./g;s/%2e/./g;s/%3A/:/g;s/%3a/:/g;s/%7C/|/g;s/%7c/|/g;s/%26/\\&/g')
cd "$BASE_DIR" 2>/dev/null || cd /mnt/us 2>/dev/null || cd /
echo "\$ \$cmd"
echo
/bin/sh -lc "\$cmd" 2>&1
echo
echo "(exit \$?)"
EOF
    chmod +x "$cgi_dir/run"

    $httpd_cmd -f -p "$AIR_DROP_PORT" -h "$web_root" &
    httpd_pid="$!"
    echo "$httpd_pid" > "$pid_file"

    draw_header "AirDrop Lite" "Command runner"
    echo "Python was not available, so AirDrop Lite is running with BusyBox httpd."
    echo "Open one of these URLs on another device on the same Wi-Fi:"
    for ip in $(get_lan_ips); do
        echo "http://$ip:$AIR_DROP_PORT/?token=$token"
    done
    echo
    echo "Press q then Enter to stop AirDrop Lite."
    while true; do
        read -r choice
        case "$choice" in
            q|Q)
                kill "$httpd_pid" 2>/dev/null || true
                rm -rf "$web_root" "$pid_file"
                return 0
                ;;
        esac
    done
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
        draw_header "AirDrop" "Starting"
        if start_busybox_airdrop; then
            return 0
        fi

        draw_header "AirDrop" "Installing Python"
        if install_python; then
            python_bin="$(find_python)"
        fi
    fi

    if [ -z "$python_bin" ]; then
        draw_header "AirDrop" "Python install needed"
        echo "AirDrop needs Python for the full file manager."
        echo "AirDrop Lite needs BusyBox httpd for command running."
        echo
        echo "I could not find Python, BusyBox httpd, or a supported package manager."
        echo "Run this in kterm and send the output if this still happens:"
        echo "  command -v python3; command -v python; command -v busybox; busybox httpd --help"
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
