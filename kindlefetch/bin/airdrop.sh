#!/bin/sh

BASE_DIR="${BASE_DIR:-/mnt/us}"
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

fetch_local_airdrop() {
    url="http://127.0.0.1:$AIR_DROP_PORT/"
    tried=false
    if command -v curl >/dev/null 2>&1; then
        tried=true
        curl -fsS --connect-timeout 3 --max-time 5 "$url" >/dev/null 2>&1 && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        tried=true
        wget -q -O - "$url" >/dev/null 2>&1 && return 0
    fi
    [ "$tried" = true ] && return 1
    return 2
}

write_airdrop_site() {
    web_root="$1"
    cgi_dir="$web_root/cgi-bin"
    mkdir -p "$cgi_dir" || return 1

    cat > "$web_root/index.html" <<EOF
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>KindleFetch AirDrop</title>
<style>
body{font-family:sans-serif;margin:20px;max-width:850px;background:#f7f5ef;color:#1f2328}
textarea{width:100%;height:92px;font-family:monospace;font-size:15px}
pre{background:#111;color:#eee;padding:12px;white-space:pre-wrap;overflow:auto;min-height:120px}
button{padding:10px 14px;margin-top:8px}
input{width:100%;padding:9px;margin:6px 0}
a{display:block;margin:8px 0}
</style>
</head>
<body>
<h1>KindleFetch AirDrop</h1>
<p>Root: $BASE_DIR</p>
<h2>Run Command</h2>
<textarea id="cmd" placeholder="ls -la /mnt/us/documents"></textarea><br>
<button onclick="run()">Run</button>
<pre id="out"></pre>
<h2>Files</h2>
<a href="/cgi-bin/run?cmd=ls%20-la%20/mnt/us">List /mnt/us</a>
<a href="/cgi-bin/run?cmd=ls%20-la%20/mnt/us/documents">List documents</a>
<script>
function run(){
  var c=document.getElementById('cmd').value;
  document.getElementById('out').textContent='Running...';
  fetch('/cgi-bin/run?cmd='+encodeURIComponent(c))
    .then(r=>r.text())
    .then(t=>document.getElementById('out').textContent=t)
    .catch(e=>document.getElementById('out').textContent=e);
}
</script>
</body>
</html>
EOF

    cat > "$cgi_dir/run" <<'EOF'
#!/bin/sh
printf 'Content-Type: text/plain\r\n\r\n'
cmd=$(printf '%s' "$QUERY_STRING" | sed 's/^cmd=//' | sed 's/+/ /g;s/%20/ /g;s/%21/!/g;s/%22/"/g;s/%23/#/g;s/%24/$/g;s/%25/%/g;s/%26/\&/g;s/%27/'"'"'/g;s/%28/(/g;s/%29/)/g;s/%2A/*/g;s/%2a/*/g;s/%2B/+/g;s/%2b/+/g;s/%2C/,/g;s/%2c/,/g;s/%2D/-/g;s/%2d/-/g;s/%2E/./g;s/%2e/./g;s/%2F/\//g;s/%2f/\//g;s/%3A/:/g;s/%3a/:/g;s/%3B/;/g;s/%3b/;/g;s/%3D/=/g;s/%3d/=/g;s/%3F/?/g;s/%3f/?/g;s/%40/@/g;s/%5B/[/g;s/%5b/[/g;s/%5D/]/g;s/%5d/]/g;s/%5E/^/g;s/%5e/^/g;s/%5F/_/g;s/%5f/_/g;s/%60/`/g;s/%7B/{/g;s/%7b/{/g;s/%7C/|/g;s/%7c/|/g;s/%7D/}/g;s/%7d/}/g;s/%7E/~/g;s/%7e/~/g')
cd /mnt/us 2>/dev/null || cd /
echo "$ $cmd"
echo
/bin/sh -lc "$cmd" 2>&1
rc=$?
echo
echo "(exit $rc)"
EOF
    chmod +x "$cgi_dir/run"
}

airdrop_menu() {
    httpd_cmd="$(find_httpd)"
    if [ -z "$httpd_cmd" ]; then
        draw_header "AirDrop" "Unavailable"
        echo "Could not find httpd or busybox httpd on this Kindle."
        echo "Run this in kterm and send the output:"
        echo "  command -v httpd; command -v busybox; ls -l /bin/busybox"
        pause
        return 1
    fi

    web_root="/tmp/kindlefetch-airdrop-www"
    pid_file="/tmp/kindlefetch-airdrop-httpd.pid"

    if [ -f "$pid_file" ]; then
        old_pid="$(cat "$pid_file" 2>/dev/null)"
        [ -n "$old_pid" ] && kill "$old_pid" 2>/dev/null || true
    fi

    rm -rf "$web_root"
    write_airdrop_site "$web_root" || {
        echo "Failed to create AirDrop site."
        pause
        return 1
    }

    $httpd_cmd -f -p "0.0.0.0:$AIR_DROP_PORT" -h "$web_root" &
    httpd_pid="$!"
    echo "$httpd_pid" > "$pid_file"
    sleep 1

    fetch_local_airdrop
    selftest_rc="$?"
    if [ "$selftest_rc" = "1" ]; then
        kill "$httpd_pid" 2>/dev/null || true
        rm -rf "$web_root" "$pid_file"
        draw_header "AirDrop" "Server failed"
        echo "AirDrop httpd started but did not answer locally."
        echo "Tried: http://127.0.0.1:$AIR_DROP_PORT/"
        echo
        echo "Run this in kterm and send the output:"
        echo "  ps | grep httpd; netstat -ln | grep $AIR_DROP_PORT"
        pause
        return 1
    fi

    draw_header "AirDrop" "Command runner"
    echo "Open one of these URLs on another device on the same Wi-Fi:"
    ips="$(get_lan_ips)"
    if [ -z "$ips" ]; then
        echo "http://KINDLE_IP:$AIR_DROP_PORT/"
    else
        for ip in $ips; do
            echo "http://$ip:$AIR_DROP_PORT/"
        done
    fi
    echo
    echo "Press q then Enter to stop AirDrop."

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
