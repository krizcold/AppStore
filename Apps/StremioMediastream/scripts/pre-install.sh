#!/bin/bash
# MediaFusion Pre-Install Script
# Creates directories and generates pre-configured addon URL

set -e

APP_DIR="/DATA/AppData/mediafusion"

echo "Creating MediaFusion directories..."
mkdir -p "$APP_DIR"/{qbittorrent/downloads,qbittorrent/config,postgres,mongodb,redis,prowlarr,config}
chown -R 1000:1000 "$APP_DIR" 2>/dev/null || true
chmod -R 755 "$APP_DIR"

echo "Generating pre-configured addon URL..."
docker run --rm \
  -e SECRET_KEY="${PCS_DEFAULT_PASSWORD}!mfkey!!" \
  -e HOST_URL="https://mediafusion-api-${REF_DOMAIN}" \
  python:3.11-alpine sh -c '
pip install -q cryptography 2>/dev/null
python3 << "PYSCRIPT"
import os, json, zlib, base64, hashlib
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

sk = os.environ["SECRET_KEY"]
hu = os.environ["HOST_URL"]
key = hashlib.sha256(sk.encode()).digest()

# UserData with qBittorrent-WebDAV config (MediaFusion schema aliases)
ud = {
    "sp": {
        "sps": "qbittorrent",
        "qbc": {
            "qur": "http://172.18.0.1:8081",
            "qus": "", "qpw": "",
            "stl": 1440, "srl": 1.0, "pva": 100,
            "cat": "MediaFusion",
            "wur": "http://172.18.0.1:8081/webdav/",
            "wus": "", "wpw": "", "wdp": "/downloads"
        }
    }
}

# Compress and encrypt
c = zlib.compress(json.dumps(ud, separators=(",", ":")).encode())
iv = os.urandom(16)
cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
enc = cipher.encryptor()
pad_len = 16 - (len(c) % 16)
encrypted = iv + enc.update(c + bytes([pad_len] * pad_len)) + enc.finalize()
config_str = "D-" + base64.urlsafe_b64encode(encrypted).decode().rstrip("=")

print(f"{hu}/{config_str}/manifest.json")
PYSCRIPT
' > "$APP_DIR/config/addon-url.txt"

# Extract domain for Prowlarr URL
PROWLARR_URL="https://prowlarr-${REF_DOMAIN}/"

echo "Creating landing page..."
cat > "$APP_DIR/config/index.html" << HTMLEOF
<!DOCTYPE html>
<html>
<head>
  <title>MediaFusion Setup</title>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <style>
    body{font-family:system-ui;max-width:650px;margin:50px auto;padding:20px;background:#1a1a2e;color:#eee}
    h1{color:#e94560}
    .url{background:#16213e;padding:15px;border-radius:8px;word-break:break-all;margin:20px 0;font-family:monospace;font-size:11px}
    .btn{display:inline-block;background:#e94560;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;margin:10px 10px 10px 0;cursor:pointer;border:none;font-size:16px}
    .btn:hover{background:#ff6b6b}
    .btn-s{background:#0f3460}
    .warn{color:#fbbf24;background:#422006;padding:15px;border-radius:8px;margin:20px 0}
    .step{background:#16213e;padding:20px;border-radius:8px;margin:15px 0}
    .step h3{margin-top:0;color:#e94560}
    ol{padding-left:20px}
    li{margin:10px 0}
    a{color:#60a5fa}
  </style>
</head>
<body>
  <h1>MediaFusion</h1>

  <div class="warn">
    <strong>⚠️ Setup Required:</strong> You must add your own indexers before this addon will work.
    We provide the infrastructure - you provide the sources.
  </div>

  <div class="step">
    <h3>Step 1: Configure Prowlarr</h3>
    <p>Add your preferred torrent indexers:</p>
    <a href="${PROWLARR_URL}" target="_blank" class="btn">Open Prowlarr</a>
    <p style="font-size:14px;color:#888">Go to Indexers → Add Indexer → Select your sources</p>
  </div>

  <div class="step">
    <h3>Step 2: Add to Stremio</h3>
    <p>Once you've added indexers, copy this URL to Stremio:</p>
    <div class="url" id="u">Loading...</div>
    <button class="btn" onclick="location.href='stremio://'+u.replace(/^https?:\/\//,'')">Install in Stremio</button>
    <button class="btn btn-s" onclick="navigator.clipboard.writeText(u).then(()=>alert('Copied!'))">Copy URL</button>
  </div>

  <div class="step">
    <h3>How it works</h3>
    <ol>
      <li>You search in Stremio</li>
      <li>MediaFusion queries YOUR Prowlarr indexers</li>
      <li>qBittorrent downloads with proper peer connectivity</li>
      <li>Stream via WebDAV - 10x more peers than Stremio's engine</li>
    </ol>
  </div>

  <p style="margin-top:30px;color:#888;font-size:13px">
    Port 6881 exposed on IPv6 for incoming peer connections.
    <br>We provide tools, you provide sources.
  </p>

  <script>fetch('/addon-url.txt').then(r=>r.text()).then(t=>{u=t.trim();document.getElementById('u').textContent=u})</script>
</body>
</html>
HTMLEOF

echo "MediaFusion pre-install completed successfully"
