#!/bin/bash
# MediaFusion Proto Pre-Install Script
# Creates directories and generates pre-configured addon URL

APP_DIR="/DATA/AppData/mediafusion-proto"

echo "Creating MediaFusion Proto directories..."
mkdir -p "$APP_DIR"/{qbittorrent/downloads,qbittorrent/config/qBittorrent,postgres,mongodb,redis,prowlarr,config}
chown -R 1000:1000 "$APP_DIR" 2>/dev/null || true
chmod -R 755 "$APP_DIR"

echo "Pre-configuring qBittorrent with known password..."
# Generate PBKDF2 hash for qBittorrent password (using PCS_DEFAULT_PASSWORD)
QBT_PASSWORD_HASH=$(docker run --rm -e PASSWORD="${PCS_DEFAULT_PASSWORD}" python:3.11-alpine sh -c '
pip install -q passlib 2>/dev/null
python3 -c "
import os, base64, hashlib
password = os.environ[\"PASSWORD\"]
salt = os.urandom(16)
iterations = 100000
dk = hashlib.pbkdf2_hmac(\"sha512\", password.encode(), salt, iterations, dklen=64)
hash_str = base64.b64encode(salt + dk).decode()
print(f\"@ByteArray({hash_str})\")
"' 2>/dev/null)

# Create qBittorrent config with pre-set password
cat > "$APP_DIR/qbittorrent/config/qBittorrent/qBittorrent.conf" << QBTCONF
[BitTorrent]
Session\DefaultSavePath=/downloads
Session\Port=6881
Session\QueueingSystemEnabled=false

[Preferences]
WebUI\Username=admin
WebUI\Password_PBKDF2=${QBT_PASSWORD_HASH}
WebUI\LocalHostAuth=false
WebUI\AuthSubnetWhitelistEnabled=true
WebUI\AuthSubnetWhitelist=0.0.0.0/0
QBTCONF

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

# Configure URL points to MediaFusion configure page
CONFIGURE_URL="https://mfprotoapi-${REF_DOMAIN}/configure"
echo "$CONFIGURE_URL" > "$APP_DIR/config/addon-url.txt"

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

  <div class="step">
    <h3>Step 1: Configure Addon</h3>
    <p>Click below to configure your streaming settings:</p>
    <a class="btn" id="u" href="#">Open Configure Page</a>
    <p style="font-size:14px;color:#888;margin-top:10px">API Password: Your PCS password</p>
  </div>

  <div class="step">
    <h3>Step 2: qBittorrent Settings</h3>
    <p>In the configure page, set:</p>
    <ul style="font-size:14px;color:#ccc">
      <li><strong>Streaming Provider:</strong> qBittorrent</li>
      <li><strong>qBittorrent URL:</strong> http://qbittorrent:80/qbittorrent/</li>
      <li><strong>Username:</strong> admin</li>
      <li><strong>Password:</strong> (your PCS password)</li>
      <li><strong>WebDAV URL:</strong> http://qbittorrent:80/webdav/</li>
      <li><strong>WebDAV credentials:</strong> leave blank</li>
    </ul>
  </div>

  <div class="step">
    <h3>Step 3: Add to Stremio</h3>
    <p>Generate the addon URL and add it to Stremio.</p>
  </div>

  <p style="margin-top:30px;color:#888;font-size:13px">
    Port 6881 exposed on IPv6 for incoming peer connections.
  </p>

  <script>fetch('/addon-url.txt').then(r=>r.text()).then(t=>{document.getElementById('u').href=t.trim()})</script>
</body>
</html>
HTMLEOF

echo "MediaFusion Proto pre-install completed successfully"
