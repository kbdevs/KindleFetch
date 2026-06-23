#!/bin/sh

BASE_DIR="${BASE_DIR:-/mnt/us}"
AIR_DROP_PORT="${KINDLEFETCH_AIRDROP_PORT:-8088}"
AIR_DROP_SSH_PORT="${KINDLEFETCH_AIRDROP_SSH_PORT:-2222}"
KOREADER_DIR="${KINDLEFETCH_KOREADER_DIR:-/mnt/us/koreader}"

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

find_dropbear() {
    if [ -x "$KOREADER_DIR/dropbear" ]; then
        echo "$KOREADER_DIR/dropbear"
        return 0
    fi
    if command -v dropbear >/dev/null 2>&1; then
        command -v dropbear
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

open_ssh_firewall() {
    iptables -A INPUT -p tcp --dport "$AIR_DROP_SSH_PORT" -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -A OUTPUT -p tcp --sport "$AIR_DROP_SSH_PORT" -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null || true
}

close_ssh_firewall() {
    iptables -D INPUT -p tcp --dport "$AIR_DROP_SSH_PORT" -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -p tcp --sport "$AIR_DROP_SSH_PORT" -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null || true
}

start_airdrop_ssh() {
    dropbear_cmd="$(find_dropbear)"
    [ -z "$dropbear_cmd" ] && return 1

    pid_file="/tmp/dropbear_koreader.pid"
    key_dir="$KOREADER_DIR/settings/SSH"
    mkdir -p "$key_dir" 2>/dev/null || true

    if netstat -ln 2>/dev/null | grep "[.:]$AIR_DROP_SSH_PORT " >/dev/null 2>&1; then
        return 0
    fi

    if [ -f "$pid_file" ]; then
        old_pid="$(cat "$pid_file" 2>/dev/null)"
        [ -n "$old_pid" ] && kill "$old_pid" 2>/dev/null || true
    fi

    open_ssh_firewall
    (
        cd "$KOREADER_DIR" 2>/dev/null || cd /mnt/us
        "$dropbear_cmd" -E -R -p "$AIR_DROP_SSH_PORT" -P "$pid_file" -n >/tmp/kindlefetch-airdrop-ssh.log 2>&1
    )
    sleep 1

    netstat -ln 2>/dev/null | grep "[.:]$AIR_DROP_SSH_PORT " >/dev/null 2>&1
}

stop_airdrop_ssh() {
    pid_file="/tmp/dropbear_koreader.pid"
    old_pid="$(cat "$pid_file" 2>/dev/null)"
    [ -n "$old_pid" ] && kill "$old_pid" 2>/dev/null || true
    rm -f "$pid_file"
    close_ssh_firewall
}

print_ssh_commands() {
    echo "From your Mac:"
    for ip in $(get_lan_ips); do
        echo "  ssh -p $AIR_DROP_SSH_PORT root@$ip"
        echo "  scp -P $AIR_DROP_SSH_PORT file.epub root@$ip:/mnt/us/documents/"
    done
}

ssh_menu() {
    if ! start_airdrop_ssh; then
        draw_header "SSH" "Failed"
        echo "Could not start KOReader Dropbear SSH."
        [ -s /tmp/kindlefetch-airdrop-ssh.log ] && {
            echo
            echo "Dropbear log:"
            head -8 /tmp/kindlefetch-airdrop-ssh.log
        }
        pause
        return 1
    fi

    draw_header "SSH" "Running"
    echo "SSH is running on port $AIR_DROP_SSH_PORT."
    echo
    print_ssh_commands
    echo
    if [ ! -s "$KOREADER_DIR/settings/SSH/authorized_keys" ]; then
        echo "No SSH public key is installed yet."
        echo "Add one to:"
        echo "  $KOREADER_DIR/settings/SSH/authorized_keys"
        echo
    fi
    echo "SSH will keep running after you leave this screen."
    pause
}

airdrop_ssh_menu() {
    if ! start_airdrop_ssh; then
        draw_header "AirDrop" "SSH failed"
        echo "Could not start KOReader Dropbear SSH."
        [ -s /tmp/kindlefetch-airdrop-ssh.log ] && {
            echo
            echo "Dropbear log:"
            head -8 /tmp/kindlefetch-airdrop-ssh.log
        }
        pause
        return 1
    fi

    draw_header "AirDrop" "SSH/SCP"
    echo "AirDrop is running through KOReader SSH."
    echo
    print_ssh_commands
    echo
    if [ ! -s "$KOREADER_DIR/settings/SSH/authorized_keys" ]; then
        echo "No SSH public key is installed yet."
        echo "Add one to:"
        echo "  $KOREADER_DIR/settings/SSH/authorized_keys"
        echo
    fi
    echo "Use SSH/SCP/SFTP to upload, delete, move, and create files."
    echo "Press q then Enter to stop AirDrop SSH."

    while true; do
        read -r choice
        case "$choice" in
            q|Q)
                stop_airdrop_ssh
                return 0
                ;;
        esac
    done
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

find_airdrop_pids() {
    ps 2>/dev/null | awk -v port="$AIR_DROP_PORT" '/[h]ttpd/ && $0 ~ port { print $1 }'
}

stop_airdrop_httpd() {
    if [ -f "$pid_file" ]; then
        old_pid="$(cat "$pid_file" 2>/dev/null)"
        [ -n "$old_pid" ] && kill "$old_pid" 2>/dev/null || true
    fi
    for old_pid in $(find_airdrop_pids); do
        kill "$old_pid" 2>/dev/null || true
    done
}

start_airdrop_httpd() {
    httpd_cmd="$1"
    web_root="$2"
    log_file="$3"

    : > "$log_file" 2>/dev/null || true

    $httpd_cmd -p "$AIR_DROP_PORT" -h "$web_root" >>"$log_file" 2>&1
    sleep 1
    fetch_local_airdrop
    if [ "$?" != "1" ]; then
        find_airdrop_pids | head -1 > "$pid_file"
        return 0
    fi

    $httpd_cmd -p "0.0.0.0:$AIR_DROP_PORT" -h "$web_root" >>"$log_file" 2>&1
    sleep 1
    fetch_local_airdrop
    if [ "$?" != "1" ]; then
        find_airdrop_pids | head -1 > "$pid_file"
        return 0
    fi

    $httpd_cmd -f -p "$AIR_DROP_PORT" -h "$web_root" >>"$log_file" 2>&1 &
    httpd_pid="$!"
    echo "$httpd_pid" > "$pid_file"
    sleep 1
    fetch_local_airdrop
    [ "$?" != "1" ] && return 0

    return 1
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
/bin/sh -c "$cmd" 2>&1
rc=$?
echo
echo "(exit $rc)"
EOF
    chmod +x "$cgi_dir/run"
}

airdrop_menu() {
    if [ -x "$KOREADER_DIR/dropbear" ]; then
        airdrop_ssh_menu
        return $?
    fi

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
    log_file="/tmp/kindlefetch-airdrop-httpd.log"

    if [ -f "$pid_file" ]; then
        stop_airdrop_httpd
    fi

    rm -rf "$web_root"
    write_airdrop_site "$web_root" || {
        echo "Failed to create AirDrop site."
        pause
        return 1
    }

    if ! start_airdrop_httpd "$httpd_cmd" "$web_root" "$log_file"; then
        stop_airdrop_httpd
        rm -rf "$web_root" "$pid_file"
        draw_header "AirDrop" "Server failed"
        echo "AirDrop httpd started but did not answer locally."
        echo "Tried: http://127.0.0.1:$AIR_DROP_PORT/"
        echo
        echo "httpd command: $httpd_cmd"
        echo "Diagnostics:"
        ps | grep '[h]ttpd' 2>/dev/null || true
        netstat -ln 2>/dev/null | grep "$AIR_DROP_PORT" || true
        [ -s "$log_file" ] && {
            echo
            echo "httpd log:"
            head -8 "$log_file"
        }
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
                stop_airdrop_httpd
                rm -rf "$web_root" "$pid_file"
                return 0
                ;;
        esac
    done
}
