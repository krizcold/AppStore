#!/bin/bash
# MediaFusion Proto Pre-Install Script
# Creates directories and generates pre-configured addon URL

APP_DIR="/DATA/AppData/mediafusion-proto"

echo "Creating MediaFusion Proto directories..."
mkdir -p "$APP_DIR"/{qbittorrent/downloads,qbittorrent/config,postgres,mongodb,redis,prowlarr,config}
chown -R 1000:1000 "$APP_DIR" 2>/dev/null || true
chmod -R 755 "$APP_DIR"

echo "Creating nginx proxy config for API..."
cat > "$APP_DIR/nginx-api.conf" << 'NGINXCONF'
server {
    listen 80;
    location / {
        proxy_pass http://mediafusion:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINXCONF

echo "Generating pre-configured addon URL..."
ADDON_URL=$(docker run --rm \
  -e SECRET_KEY="${PCS_DEFAULT_PASSWORD}!mfkey!!" \
  -e HOST_URL="https://mfprotoapi-${REF_DOMAIN}" \
  python:3.11-alpine sh -c '
pip install -q cryptography 2>/dev/null
python3 << "PYSCRIPT"
import os, json, zlib, base64, hashlib
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

sk = os.environ["SECRET_KEY"]
hu = os.environ["HOST_URL"]
key = hashlib.sha256(sk.encode()).digest()

ud = {
    "sp": {
        "sps": "qbittorrent",
        "qbc": {
            "qur": "http://172.18.0.1:8082",
            "qus": "", "qpw": "",
            "stl": 1440, "srl": 1.0, "pva": 100,
            "cat": "MediaFusion",
            "wur": "http://172.18.0.1:8082/webdav/",
            "wus": "", "wpw": "", "wdp": "/downloads"
        }
    }
}

c = zlib.compress(json.dumps(ud, separators=(",", ":")).encode())
iv = os.urandom(16)
cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
enc = cipher.encryptor()
pad_len = 16 - (len(c) % 16)
encrypted = iv + enc.update(c + bytes([pad_len] * pad_len)) + enc.finalize()
config_str = "D-" + base64.urlsafe_b64encode(encrypted).decode().rstrip("=")

print(f"{hu}/{config_str}/manifest.json")
PYSCRIPT
' 2>/dev/null)

# Fallback if docker run failed
if [ -z "$ADDON_URL" ]; then
  echo "Warning: Could not generate encrypted URL, using fallback"
  ADDON_URL="https://mediafusion-proto-api-${REF_DOMAIN}/configure"
fi

echo "$ADDON_URL" > "$APP_DIR/config/addon-url.txt"

echo "Creating landing page..."
cat > "$APP_DIR/config/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
  <title>MediaFusion (Prototype)</title>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <style>
    body{font-family:system-ui;max-width:650px;margin:50px auto;padding:20px;background:#1a1a2e;color:#eee}
    h1{color:#e94560}
    .url{background:#16213e;padding:15px;border-radius:8px;word-break:break-all;margin:20px 0;font-family:monospace;font-size:11px}
    .btn{display:inline-block;background:#e94560;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;margin:10px 10px 10px 0;cursor:pointer;border:none;font-size:16px}
    .btn:hover{background:#ff6b6b}
    .btn-s{background:#0f3460}
    .warn{color:#fbbf24;background:#422006;padding:15px;border-radius:8px;margin:20px 0}
    .success{color:#34d399;background:#064e3b;padding:15px;border-radius:8px;margin:20px 0}
    .step{background:#16213e;padding:20px;border-radius:8px;margin:15px 0}
    .step h3{margin-top:0;color:#e94560}
    ol{padding-left:20px}
    li{margin:10px 0}
  </style>
</head>
<body>
  <h1>MediaFusion (Prototype)</h1>

  <div class="warn">
    <strong>⚠️ PROTOTYPE - FOR TESTING ONLY ⚠️</strong><br>
    This version has automatic torrent sources enabled (BT4G, YTS).<br>
    Do NOT use in production - for internal testing only.
  </div>

  <div class="success">
    <strong>✓ Zero Config Required</strong><br>
    Automatic sources are pre-configured. Just copy the URL below to Stremio.
  </div>

  <div class="step">
    <h3>Add to Stremio</h3>
    <p>Copy this URL to Stremio:</p>
    <div class="url" id="u">Loading...</div>
    <button class="btn" onclick="location.href='stremio://'+u.replace(/^https?:\/\//,'')">Install in Stremio</button>
    <button class="btn btn-s" onclick="navigator.clipboard.writeText(u).then(()=>alert('Copied!'))">Copy URL</button>
  </div>

  <div class="step">
    <h3>How it works</h3>
    <ol>
      <li>You search in Stremio</li>
      <li>MediaFusion queries BT4G and YTS automatically</li>
      <li>qBittorrent downloads with proper peer connectivity</li>
      <li>Stream via WebDAV - 10x more peers than Stremio's engine</li>
    </ol>
  </div>

  <p style="margin-top:30px;color:#888;font-size:13px">
    Port 6881 exposed on IPv6 for incoming peer connections.
  </p>

  <script>fetch('/addon-url.txt').then(r=>r.text()).then(t=>{u=t.trim();document.getElementById('u').textContent=u})</script>
</body>
</html>
HTMLEOF

echo "MediaFusion Proto pre-install completed successfully"
