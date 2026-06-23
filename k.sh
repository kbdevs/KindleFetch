#!/bin/sh

PORT="${KINDLEFETCH_CMD_PORT:-8088}"
ROOT="${KINDLEFETCH_CMD_ROOT:-/mnt/us}"
CALLBACK_HOST="${KINDLEFETCH_CALLBACK_HOST:-192.168.4.47}"
CALLBACK_PORT="${KINDLEFETCH_CALLBACK_PORT:-8090}"
SSH_PORT="${KINDLEFETCH_SSH_PORT:-2222}"
KOREADER_DIR="${KINDLEFETCH_KOREADER_DIR:-/mnt/us/koreader}"
WWW="/tmp/kcmd-www"
PID="/tmp/kcmd.pid"
LOG="/tmp/kcmd.log"

say() { printf '%s\n' "$*"; }

lan_ips() {
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

find_applet() {
    name="$1"
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi
    if command -v busybox >/dev/null 2>&1 && busybox "$name" --help >/dev/null 2>&1; then
        echo "busybox $name"
        return 0
    fi
    if [ -x /bin/busybox ] && /bin/busybox "$name" --help >/dev/null 2>&1; then
        echo "/bin/busybox $name"
        return 0
    fi
    return 1
}

start_koreader_ssh() {
    [ -x "$KOREADER_DIR/dropbear" ] || return 1

    mkdir -p "$KOREADER_DIR/settings/SSH" 2>/dev/null || true
    if [ -n "$KINDLEFETCH_SSH_PUBKEY" ]; then
        printf '%s\n' "$KINDLEFETCH_SSH_PUBKEY" > "$KOREADER_DIR/settings/SSH/authorized_keys"
        chmod 600 "$KOREADER_DIR/settings/SSH/authorized_keys" 2>/dev/null || true
    fi

    old="$(cat /tmp/dropbear_koreader.pid 2>/dev/null)"
    [ -n "$old" ] && kill "$old" 2>/dev/null || true

    iptables -A INPUT -p tcp --dport "$SSH_PORT" -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -A OUTPUT -p tcp --sport "$SSH_PORT" -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null || true

    (
        cd "$KOREADER_DIR" 2>/dev/null || exit 1
        ./dropbear -E -R -p "$SSH_PORT" -P /tmp/dropbear_koreader.pid -n >/tmp/kcmd-dropbear.log 2>&1
    )
    sleep 1
    netstat -ln 2>/dev/null | grep "[.:]$SSH_PORT " >/dev/null 2>&1
}

decode_cmd() {
    printf '%s' "$1" | sed 's/^cmd=//;s/+/ /g;s/%20/ /g;s/%21/!/g;s/%22/"/g;s/%23/#/g;s/%24/$/g;s/%25/%/g;s/%26/\&/g;s/%27/'"'"'/g;s/%28/(/g;s/%29/)/g;s/%2A/*/g;s/%2a/*/g;s/%2B/+/g;s/%2b/+/g;s/%2C/,/g;s/%2c/,/g;s/%2D/-/g;s/%2d/-/g;s/%2E/./g;s/%2e/./g;s/%2F/\//g;s/%2f/\//g;s/%3A/:/g;s/%3a/:/g;s/%3B/;/g;s/%3b/;/g;s/%3D/=/g;s/%3d/=/g;s/%3F/?/g;s/%3f/?/g;s/%40/@/g;s/%5B/[/g;s/%5b/[/g;s/%5D/]/g;s/%5d/]/g;s/%5F/_/g;s/%5f/_/g;s/%7C/|/g;s/%7c/|/g'
}

write_www() {
    rm -rf "$WWW"
    mkdir -p "$WWW/cgi-bin" || return 1
    cat > "$WWW/index.html" <<EOF
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Kindle Command</title><style>
body{font-family:sans-serif;margin:18px;background:#f7f5ef;color:#111;max-width:760px}
textarea{width:100%;height:120px;font:16px monospace}button{font-size:18px;padding:10px 14px}
pre{background:#111;color:#eee;padding:12px;white-space:pre-wrap;overflow:auto;min-height:160px}
a{display:block;margin:10px 0}
</style></head><body>
<h1>Kindle Command</h1>
<p>Root: $ROOT</p>
<textarea id="cmd">ls -la /mnt/us</textarea><br><button onclick="run()">Run</button>
<pre id="out"></pre>
<a href="/cgi-bin/run?cmd=ls%20-la%20/mnt/us">List /mnt/us</a>
<a href="/cgi-bin/run?cmd=ps%20%7C%20grep%20httpd">Show httpd process</a>
<script>
function run(){var c=document.getElementById('cmd').value,o=document.getElementById('out');o.textContent='running...';fetch('/cgi-bin/run?cmd='+encodeURIComponent(c)).then(r=>r.text()).then(t=>o.textContent=t).catch(e=>o.textContent=e)}
</script></body></html>
EOF
    cat > "$WWW/cgi-bin/run" <<'EOF'
#!/bin/sh
printf 'Content-Type: text/plain\r\n\r\n'
cmd=$(printf '%s' "$QUERY_STRING" | sed 's/^cmd=//;s/+/ /g;s/%20/ /g;s/%7C/|/g;s/%7c/|/g;s/%2F/\//g;s/%2f/\//g;s/%3E/>/g;s/%3e/>/g;s/%3C/</g;s/%3c/</g;s/%26/\&/g')
cd /mnt/us 2>/dev/null || cd /
echo "$ $cmd"
echo
/bin/sh -c "$cmd" 2>&1
echo
echo "(exit $?)"
EOF
    chmod +x "$WWW/cgi-bin/run"
}

self_test() {
    if command -v wget >/dev/null 2>&1; then
        wget -q -O - "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --connect-timeout 3 --max-time 5 "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && return 0
    fi
    return 1
}

start_httpd() {
    HTTPD="$(find_applet httpd)" || return 1
    write_www || return 1
    : > "$LOG"
    $HTTPD -p "$PORT" -h "$WWW" >>"$LOG" 2>&1 && sleep 1 && self_test && return 0
    $HTTPD -p "0.0.0.0:$PORT" -h "$WWW" >>"$LOG" 2>&1 && sleep 1 && self_test && return 0
    $HTTPD -f -p "$PORT" -h "$WWW" >>"$LOG" 2>&1 &
    echo "$!" > "$PID"
    sleep 1
    self_test && return 0
    return 1
}

html_page() {
    cat <<EOF
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Kindle Command</title></head>
<body style="font-family:sans-serif;margin:18px;background:#f7f5ef"><h1>Kindle Command</h1>
<textarea id="c" style="width:100%;height:120px;font:16px monospace">ls -la /mnt/us</textarea><br>
<button style="font-size:18px;padding:10px" onclick="fetch('/?cmd='+encodeURIComponent(c.value)).then(r=>r.text()).then(t=>o.textContent=t)">Run</button>
<pre id="o" style="background:#111;color:#eee;padding:12px;white-space:pre-wrap;min-height:160px"></pre></body></html>
EOF
}

start_nc() {
    NC="$(find_applet nc)" || return 1
    say "Starting netcat fallback. Leave this open."
    while true; do
        req="$(mktemp /tmp/kcmd-req.XXXXXX)" || return 1
        pipe="/tmp/kcmd-pipe.$$"
        rm -f "$pipe"
        mkfifo "$pipe" || return 1
        $NC -l -p "$PORT" < "$pipe" > "$req" 2>>"$LOG" &
        nc_pid="$!"
        i=0
        while [ ! -s "$req" ] && kill -0 "$nc_pid" 2>/dev/null && [ "$i" -lt 20 ]; do
            sleep 1
            i=$((i + 1))
        done
        line="$(cat "$req" 2>/dev/null)"
        path="$(printf '%s\n' "$line" | awk '{print $2}')"
        if echo "$path" | grep -q '^/.*cmd='; then
            raw="${path#*cmd=}"
            raw="${raw%%&*}"
            cmd="$(decode_cmd "cmd=$raw")"
            body="$(mktemp /tmp/kcmd-body.XXXXXX)" || return 1
            { echo "$ $cmd"; echo; cd "$ROOT" 2>/dev/null || cd /; /bin/sh -c "$cmd" 2>&1; echo; echo "(exit $?)"; } > "$body"
            { printf 'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n'; cat "$body"; } > "$pipe"
            rm -f "$body"
        else
            { printf 'HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n'; html_page; } > "$pipe"
        fi
        wait "$nc_pid" 2>/dev/null || true
        rm -f "$req" "$pipe"
    done
}

start_reverse() {
    NC="$(find_applet nc)" || return 1
    say "Trying reverse command shell:"
    say "  Kindle -> $CALLBACK_HOST:$CALLBACK_PORT"
    say "Leave this open."
    fifo="/tmp/kcmd-rev.$$"
    rm -f "$fifo"
    mkfifo "$fifo" || return 1
    cd "$ROOT" 2>/dev/null || cd /
    /bin/sh -i < "$fifo" 2>&1 | $NC "$CALLBACK_HOST" "$CALLBACK_PORT" > "$fifo"
    rc=$?
    rm -f "$fifo"
    return "$rc"
}

say "Kindle command server"
say "Root: $ROOT"
say "Port: $PORT"
say "Reverse: $CALLBACK_HOST:$CALLBACK_PORT"
say "SSH: $SSH_PORT"
say

old="$(cat "$PID" 2>/dev/null)"
[ -n "$old" ] && kill "$old" 2>/dev/null || true

if start_koreader_ssh; then
    say "KOReader SSH OK. From your Mac:"
    for ip in $(lan_ips); do say "  ssh -p $SSH_PORT root@$ip"; done
    say
else
    say "KOReader SSH not available."
    [ -s /tmp/kcmd-dropbear.log ] && { say "Dropbear log:"; cat /tmp/kcmd-dropbear.log; }
    say
fi

if start_httpd; then
    say "HTTPD OK. Open:"
    for ip in $(lan_ips); do say "http://$ip:$PORT/"; done
    say
    say "Local self-test passed. Press Enter to stop."
    read _
    pkill httpd 2>/dev/null || true
    exit 0
fi

say "HTTPD did not answer locally."
say "Diagnostics:"
say "httpd: $(find_applet httpd 2>/dev/null || echo missing)"
say "nc: $(find_applet nc 2>/dev/null || echo missing)"
say "ip(s): $(lan_ips | tr '\n' ' ')"
say "ps:"
ps | grep '[h]ttpd' 2>/dev/null || true
say "netstat:"
netstat -ln 2>/dev/null | grep "$PORT" || true
[ -s "$LOG" ] && { say "log:"; cat "$LOG"; }
say
start_reverse || true
say
say "Trying netcat fallback. Open:"
for ip in $(lan_ips); do say "http://$ip:$PORT/"; done
say
start_nc
