#!/usr/bin/env python3
import cgi
import html
import json
import mimetypes
import os
import secrets
import select
import shutil
import socket
import subprocess
import sys
import threading
import urllib.parse
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler


ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "/mnt/us")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
VENDOR_DIR = os.path.join(SCRIPT_DIR, "vendor")
if os.path.isdir(VENDOR_DIR) and VENDOR_DIR not in sys.path:
    sys.path.insert(0, VENDOR_DIR)
HOST = "0.0.0.0"
PORT = int(os.environ.get("KINDLEFETCH_AIRDROP_PORT", "8088"))
TOKEN = os.environ.get("KINDLEFETCH_AIRDROP_TOKEN") or secrets.token_urlsafe(8)
COMMAND_TIMEOUT = int(os.environ.get("KINDLEFETCH_AIRDROP_COMMAND_TIMEOUT", "20"))
COMMAND_OUTPUT_LIMIT = int(os.environ.get("KINDLEFETCH_AIRDROP_COMMAND_OUTPUT_LIMIT", "20000"))


def local_ips():
    override = os.environ.get("KINDLEFETCH_AIRDROP_HOST", "").strip()
    if override:
        return [override]

    candidates = []

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        candidates.append(sock.getsockname()[0])
    except OSError:
        pass
    finally:
        sock.close()

    try:
        hostname = socket.gethostname()
        for item in socket.getaddrinfo(hostname, None, socket.AF_INET):
            candidates.append(item[4][0])
    except OSError:
        pass

    for command in (["ip", "-4", "addr"], ["ifconfig"]):
        try:
            output = subprocess.check_output(command, stderr=subprocess.DEVNULL).decode("utf-8", "ignore")
        except Exception:
            continue
        for line in output.splitlines():
            stripped = line.strip()
            if "broadcast" in stripped and "inet " not in stripped:
                continue
            words = stripped.replace("/", " ").split()
            for idx, token in enumerate(words):
                if token != "inet" or idx + 1 >= len(words):
                    continue
                ip = words[idx + 1].split("/")[0]
                candidates.append(ip)

    filtered = []
    for ip in candidates:
        parts = ip.split(".")
        if len(parts) != 4 or not all(part.isdigit() and 0 <= int(part) <= 255 for part in parts):
            continue
        octets = [int(part) for part in parts]
        if ip.startswith("127.") or ip == "0.0.0.0" or octets[-1] in (0, 255):
            continue
        private = (
            octets[0] == 10 or
            (octets[0] == 172 and 16 <= octets[1] <= 31) or
            (octets[0] == 192 and octets[1] == 168)
        )
        if not private:
            continue
        if ip not in filtered:
            filtered.append(ip)

    return filtered or ["127.0.0.1"]


def safe_path(raw_path):
    raw_path = urllib.parse.unquote(raw_path or "")
    raw_path = raw_path.replace("\\", "/").lstrip("/")
    full = os.path.abspath(os.path.join(ROOT, raw_path))
    if full != ROOT and not full.startswith(ROOT + os.sep):
        raise ValueError("Path is outside the AirDrop root")
    return full


def rel_path(full_path):
    value = os.path.relpath(full_path, ROOT)
    return "" if value == "." else value


def read_json(handler):
    length = int(handler.headers.get("Content-Length", "0") or "0")
    if length <= 0:
        return {}
    return json.loads(handler.rfile.read(length).decode("utf-8"))


def token_from_query(path):
    parsed = urllib.parse.urlparse(path)
    params = urllib.parse.parse_qs(parsed.query)
    return params.get("token", [""])[0]


def make_urls():
    return ["http://%s:%s/?token=%s" % (ip, PORT, TOKEN) for ip in local_ips()]


def render_terminal_qr(matrix):
    if len(matrix) % 2:
        matrix.append([False] * len(matrix[0]))
    for row_index in range(0, len(matrix), 2):
        top = matrix[row_index]
        bottom = matrix[row_index + 1]
        line = []
        for upper, lower in zip(top, bottom):
            if upper and lower:
                line.append("█")
            elif upper:
                line.append("▀")
            elif lower:
                line.append("▄")
            else:
                line.append(" ")
        print("".join(line))


def print_qr_hint(urls):
    print("AirDrop is running.")
    print("Scan a QR code, or open one of these URLs from another device on the same Wi-Fi:")
    for url in urls:
        print(url)
    print("")

    try:
        import qrcode
        for index, url in enumerate(urls[:3], 1):
            if len(urls) > 1:
                print("QR %d:" % index)
            qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=4)
            qr.add_data(url)
            qr.make(fit=True)
            render_terminal_qr(qr.get_matrix())
            print("")
    except Exception as exc:
        print("QR rendering failed: %s" % exc)
        print("Use one of the URLs above.")
    print("")
    print("Press q then Enter to stop AirDrop.")
    sys.stdout.flush()


HTML_PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>KindleFetch AirDrop</title>
<style>
:root { color-scheme: light; --ink:#202124; --muted:#686f76; --line:#d9dde1; --bg:#f6f4ef; --panel:#fffdfa; --accent:#1f6f64; --danger:#9f2d24; }
* { box-sizing:border-box; }
body { margin:0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background:var(--bg); color:var(--ink); }
header { display:flex; align-items:center; justify-content:space-between; gap:16px; padding:18px 22px; border-bottom:1px solid var(--line); background:var(--panel); position:sticky; top:0; z-index:1; }
h1 { margin:0; font-size:20px; letter-spacing:0; }
main { max-width:980px; margin:0 auto; padding:20px; }
.toolbar, .crumbs, .dropzone, .table-wrap, .command-panel { background:var(--panel); border:1px solid var(--line); border-radius:8px; }
.toolbar { display:grid; grid-template-columns:1fr auto auto; gap:10px; padding:12px; align-items:center; }
.crumbs { margin:14px 0; padding:12px; color:var(--muted); overflow-wrap:anywhere; }
.dropzone { margin-bottom:14px; padding:18px; text-align:center; border-style:dashed; color:var(--muted); }
.dropzone.drag { border-color:var(--accent); color:var(--accent); background:#edf6f3; }
input, button { font:inherit; }
input[type=text] { width:100%; padding:10px 11px; border:1px solid var(--line); border-radius:6px; background:white; color:var(--ink); }
textarea { width:100%; min-height:76px; padding:10px 11px; border:1px solid var(--line); border-radius:6px; background:white; color:var(--ink); font:13px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; resize:vertical; }
input[type=file] { max-width:100%; }
button, .button { border:1px solid var(--line); background:#fff; color:var(--ink); padding:9px 11px; border-radius:6px; cursor:pointer; text-decoration:none; display:inline-flex; align-items:center; min-height:38px; }
button.primary { background:var(--accent); color:white; border-color:var(--accent); }
button.danger { color:var(--danger); }
button:disabled { opacity:.45; cursor:not-allowed; }
table { width:100%; border-collapse:collapse; table-layout:fixed; }
th, td { text-align:left; padding:11px 12px; border-bottom:1px solid var(--line); vertical-align:middle; }
th { font-size:12px; text-transform:uppercase; color:var(--muted); background:#fbfaf7; }
tr:last-child td { border-bottom:0; }
.name { overflow-wrap:anywhere; }
.actions { display:flex; gap:8px; flex-wrap:wrap; justify-content:flex-end; }
.status { min-height:24px; color:var(--muted); margin-top:12px; }
.empty { padding:28px; text-align:center; color:var(--muted); }
.command-panel { margin-top:14px; padding:12px; }
.command-row { display:grid; grid-template-columns:1fr auto; gap:10px; align-items:start; }
.command-output { margin:12px 0 0; padding:12px; min-height:54px; max-height:320px; overflow:auto; background:#111; color:#f3f5f4; border-radius:6px; white-space:pre-wrap; font:12px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
@media (max-width:720px) {
  header { align-items:flex-start; flex-direction:column; }
  .toolbar, .command-row { grid-template-columns:1fr; }
  th.size, td.size { display:none; }
  .actions { justify-content:flex-start; }
}
</style>
</head>
<body>
<header><h1>KindleFetch AirDrop</h1><button id="refresh" type="button">Refresh</button></header>
<main>
  <section class="toolbar">
    <input id="folder-name" data-testid="folder-name-input" type="text" placeholder="New folder name">
    <button id="create-folder" data-testid="create-folder-btn" class="primary" type="button">Create Folder</button>
    <input id="file-input" data-testid="file-input" type="file" multiple>
  </section>
  <section class="crumbs" data-testid="current-path">/</section>
  <section id="dropzone" class="dropzone">Drop files here to upload to the current folder</section>
  <section class="table-wrap">
    <table aria-label="Files">
      <thead><tr><th>Name</th><th class="size">Size</th><th>Modified</th><th></th></tr></thead>
      <tbody id="files" data-testid="files-body"></tbody>
    </table>
    <div id="empty" class="empty" hidden>No files here yet.</div>
  </section>
  <section class="command-panel" data-testid="command-panel">
    <div class="command-row">
      <textarea id="command-input" data-testid="command-input" placeholder="Run a Kindle shell command, e.g. ls -la /mnt/us/documents"></textarea>
      <button id="run-command" data-testid="run-command-btn" class="primary" type="button">Run</button>
    </div>
    <pre id="command-output" data-testid="command-output" class="command-output"></pre>
  </section>
  <div id="status" class="status" role="status"></div>
</main>
<script>
const token = new URLSearchParams(location.search).get("token") || "";
let currentPath = "";
const $ = (id) => document.getElementById(id);
function setStatus(text) { $("status").textContent = text || ""; }
function apiUrl(path, params = {}) {
  const url = new URL(path, location.origin);
  url.searchParams.set("token", token);
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  return url;
}
async function request(path, body) {
  const res = await fetch(apiUrl(path), { method:"POST", headers:{ "Content-Type":"application/json" }, body:JSON.stringify(body || {}) });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || res.statusText);
  return data;
}
function humanSize(bytes) {
  if (bytes === null || bytes === undefined) return "-";
  const units = ["B","KB","MB","GB"]; let size = bytes; let i = 0;
  while (size >= 1024 && i < units.length - 1) { size /= 1024; i++; }
  return `${size.toFixed(i ? 1 : 0)} ${units[i]}`;
}
function joinPath(base, name) { return base ? `${base}/${name}` : name; }
async function load(path = currentPath) {
  const res = await fetch(apiUrl("/api/list", { path }));
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || "Failed to list files");
  currentPath = data.path || "";
  $("current-path").textContent = "/" + currentPath;
  render(data.items || []);
}
function render(items) {
  const tbody = $("files");
  tbody.innerHTML = "";
  $("empty").hidden = items.length !== 0;
  if (currentPath) {
    const tr = document.createElement("tr");
    tr.innerHTML = `<td class="name"><button type="button" data-testid="parent-dir-btn">..</button></td><td class="size"></td><td></td><td></td>`;
    tr.querySelector("button").onclick = () => load(currentPath.split("/").slice(0, -1).join("/"));
    tbody.appendChild(tr);
  }
  for (const item of items) {
    const path = joinPath(currentPath, item.name);
    const tr = document.createElement("tr");
    tr.dataset.testid = "file-row";
    tr.innerHTML = `
      <td class="name">${item.type === "dir" ? "▸ " : ""}${escapeHtml(item.name)}</td>
      <td class="size">${item.type === "dir" ? "-" : humanSize(item.size)}</td>
      <td>${escapeHtml(item.modified)}</td>
      <td><div class="actions"></div></td>`;
    const actions = tr.querySelector(".actions");
    if (item.type === "dir") actions.append(button("Open", () => load(path), "open-btn"));
    else actions.append(link("Download", apiUrl("/download", { path }), "download-link"));
    actions.append(button("Rename", async () => {
      const name = prompt("New name", item.name);
      if (!name || name === item.name) return;
      await request("/api/move", { from:path, to:joinPath(currentPath, name) });
      await load();
    }, "rename-btn"));
    actions.append(button("Move", async () => {
      const dest = prompt("Move to path", path);
      if (!dest || dest === path) return;
      await request("/api/move", { from:path, to:dest.replace(/^\\/+/, "") });
      await load();
    }, "move-btn"));
    actions.append(button("Delete", async () => {
      if (!confirm(`Delete ${item.name}?`)) return;
      await request("/api/delete", { path });
      await load();
    }, "delete-btn", "danger"));
    tbody.appendChild(tr);
  }
}
function button(label, onClick, testId, className = "") {
  const el = document.createElement("button");
  el.type = "button"; el.textContent = label; el.dataset.testid = testId; el.className = className;
  el.onclick = async () => { try { setStatus(""); await onClick(); setStatus("Done."); } catch (e) { setStatus(e.message); } };
  return el;
}
function link(label, href, testId) {
  const el = document.createElement("a");
  el.textContent = label; el.href = href; el.dataset.testid = testId; el.className = "button";
  return el;
}
function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, ch => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#039;" }[ch]));
}
async function upload(files) {
  if (!files || files.length === 0) return;
  const form = new FormData();
  form.append("path", currentPath);
  for (const file of files) form.append("files", file);
  const res = await fetch(apiUrl("/api/upload"), { method:"POST", body:form });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || "Upload failed");
  setStatus(`Uploaded ${data.count} file(s).`);
  await load();
}
$("create-folder").onclick = async () => {
  try {
    const name = $("folder-name").value.trim();
    if (!name) return setStatus("Enter a folder name.");
    await request("/api/mkdir", { path:joinPath(currentPath, name) });
    $("folder-name").value = "";
    await load();
    setStatus("Folder created.");
  } catch (e) { setStatus(e.message); }
};
$("file-input").onchange = (e) => upload(e.target.files).catch(err => setStatus(err.message));
$("refresh").onclick = () => load().catch(err => setStatus(err.message));
$("run-command").onclick = async () => {
  const command = $("command-input").value.trim();
  if (!command) return setStatus("Enter a command.");
  $("command-output").textContent = "Running...";
  try {
    const data = await request("/api/command", { command });
    $("command-output").textContent = `$ ${command}\n\n${data.output || ""}`;
    setStatus(`Command exited ${data.returncode}.`);
  } catch (e) {
    $("command-output").textContent = e.message;
    setStatus(e.message);
  }
};
const dz = $("dropzone");
dz.ondragover = (e) => { e.preventDefault(); dz.classList.add("drag"); };
dz.ondragleave = () => dz.classList.remove("drag");
dz.ondrop = (e) => { e.preventDefault(); dz.classList.remove("drag"); upload(e.dataTransfer.files).catch(err => setStatus(err.message)); };
load().catch(err => setStatus(err.message));
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    server_version = "KindleFetchAirDrop/1.0"

    def log_message(self, fmt, *args):
        sys.stdout.write("%s - %s\n" % (self.address_string(), fmt % args))

    def authorized(self):
        return token_from_query(self.path) == TOKEN

    def send_json(self, status, payload):
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_error_json(self, status, message):
        self.send_json(status, {"error": message})

    def require_auth(self):
        if self.authorized():
            return True
        self.send_error_json(403, "Invalid AirDrop token")
        return False

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/":
            if not self.authorized():
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b"Invalid AirDrop token")
                return
            body = HTML_PAGE.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if not self.require_auth():
            return
        if parsed.path == "/api/list":
            params = urllib.parse.parse_qs(parsed.query)
            self.list_dir(params.get("path", [""])[0])
        elif parsed.path == "/download":
            params = urllib.parse.parse_qs(parsed.query)
            self.download(params.get("path", [""])[0])
        elif parsed.path == "/run":
            params = urllib.parse.parse_qs(parsed.query)
            command = params.get("cmd", [""])[0]
            self.run_command(command, as_json=False)
        else:
            self.send_error_json(404, "Not found")

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if not self.require_auth():
            return
        try:
            if parsed.path == "/api/mkdir":
                data = read_json(self)
                os.makedirs(safe_path(data.get("path", "")), exist_ok=True)
                self.send_json(200, {"ok": True})
            elif parsed.path == "/api/delete":
                data = read_json(self)
                target = safe_path(data.get("path", ""))
                if target == ROOT:
                    raise ValueError("Refusing to delete the AirDrop root")
                if os.path.isdir(target):
                    shutil.rmtree(target)
                else:
                    os.remove(target)
                self.send_json(200, {"ok": True})
            elif parsed.path == "/api/move":
                data = read_json(self)
                src = safe_path(data.get("from", ""))
                dst = safe_path(data.get("to", ""))
                if src == ROOT:
                    raise ValueError("Refusing to move the AirDrop root")
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.move(src, dst)
                self.send_json(200, {"ok": True})
            elif parsed.path == "/api/upload":
                self.upload()
            elif parsed.path == "/api/command":
                data = read_json(self)
                self.run_command(data.get("command", ""), as_json=True)
            else:
                self.send_error_json(404, "Not found")
        except Exception as exc:
            self.send_error_json(400, str(exc))

    def list_dir(self, requested):
        target = safe_path(requested)
        if not os.path.isdir(target):
            self.send_error_json(404, "Directory not found")
            return
        items = []
        for name in sorted(os.listdir(target), key=lambda x: (not os.path.isdir(os.path.join(target, x)), x.lower())):
            full = os.path.join(target, name)
            stat = os.stat(full)
            items.append({
                "name": name,
                "type": "dir" if os.path.isdir(full) else "file",
                "size": None if os.path.isdir(full) else stat.st_size,
                "modified": __import__("datetime").datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M"),
            })
        self.send_json(200, {"path": rel_path(target), "items": items})

    def download(self, requested):
        target = safe_path(requested)
        if not os.path.isfile(target):
            self.send_error_json(404, "File not found")
            return
        content_type = mimetypes.guess_type(target)[0] or "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(os.path.getsize(target)))
        self.send_header("Content-Disposition", "attachment; filename=\"%s\"" % os.path.basename(target).replace('"', ""))
        self.end_headers()
        with open(target, "rb") as fh:
            shutil.copyfileobj(fh, self.wfile)

    def upload(self):
        form = cgi.FieldStorage(fp=self.rfile, headers=self.headers, environ={
            "REQUEST_METHOD": "POST",
            "CONTENT_TYPE": self.headers.get("Content-Type", ""),
        })
        target_dir = safe_path(form.getfirst("path", ""))
        os.makedirs(target_dir, exist_ok=True)
        fields = form["files"] if "files" in form else []
        if not isinstance(fields, list):
            fields = [fields]
        count = 0
        for field in fields:
            if not getattr(field, "filename", None):
                continue
            filename = os.path.basename(field.filename)
            dest = safe_path(os.path.join(rel_path(target_dir), filename))
            with open(dest, "wb") as out:
                shutil.copyfileobj(field.file, out)
            count += 1
        self.send_json(200, {"ok": True, "count": count})

    def run_command(self, command, as_json=True):
        command = (command or "").strip()
        if not command:
            if as_json:
                self.send_error_json(400, "Command is empty")
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Command is empty")
            return

        try:
            completed = subprocess.run(
                ["/bin/sh", "-lc", command],
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=COMMAND_TIMEOUT,
            )
            output = completed.stdout.decode("utf-8", "replace")
            if len(output) > COMMAND_OUTPUT_LIMIT:
                output = output[-COMMAND_OUTPUT_LIMIT:]
                output = "[output truncated]\n" + output
            payload = {"ok": completed.returncode == 0, "returncode": completed.returncode, "output": output}
        except subprocess.TimeoutExpired as exc:
            output = (exc.stdout or b"").decode("utf-8", "replace")
            payload = {"ok": False, "returncode": 124, "output": output + "\nCommand timed out."}

        if as_json:
            self.send_json(200, payload)
        else:
            body = ("$ %s\n\n%s\n(exit %s)\n" % (command, payload["output"], payload["returncode"])).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)


if __name__ == "__main__":
    if not os.path.isdir(ROOT):
        os.makedirs(ROOT)
    urls = make_urls()
    print_qr_hint(urls)
    server = ThreadingHTTPServer((HOST, PORT), Handler)

    def watch_stdin():
        while True:
            try:
                ready, _, _ = select.select([sys.stdin], [], [], 0.5)
                if ready and sys.stdin.readline().strip().lower() == "q":
                    server.shutdown()
                    return
            except Exception:
                return

    threading.Thread(target=watch_stdin, daemon=True).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
