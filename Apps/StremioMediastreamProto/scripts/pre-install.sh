#!/bin/bash
# MediaFusion Proto Pre-Install Script
# Creates directories and generates pre-configured addon URL

APP_DIR="/DATA/AppData/mediafusionproto"

echo "Creating MediaFusion Proto directories..."
mkdir -p "$APP_DIR"/{qbittorrent/downloads,qbittorrent/config/qBittorrent/config,postgres,mongodb,redis,prowlarr,config}
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
cat > "$APP_DIR/qbittorrent/config/qBittorrent/config/qBittorrent.conf" << QBTCONF
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
CONFIGURE_URL="https://mediafusionprotoapi-${REF_DOMAIN}/configure"
echo "$CONFIGURE_URL" > "$APP_DIR/config/addon-url.txt"

echo "Creating landing page..."
cat > "$APP_DIR/config/index.html" << HTMLEOF
<!DOCTYPE html>
<html>
<head>
  <title>MediaFusion (Prototype)</title>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <style>
    body{font-family:system-ui;max-width:700px;margin:50px auto;padding:20px;background:#1a1a2e;color:#eee}
    h1{color:#e94560}
    .btn{display:inline-block;background:#e94560;color:#fff;padding:12px 24px;text-decoration:none;border-radius:6px;margin:10px 10px 10px 0;cursor:pointer;border:none;font-size:16px}
    .btn:hover{background:#ff6b6b}
    .btn-secondary{background:#0f3460}
    .btn-secondary:hover{background:#1a4a7e}
    .warn{color:#fbbf24;background:#422006;padding:15px;border-radius:8px;margin:20px 0}
    .password-box{background:#064e3b;border:2px solid #34d399;padding:15px;border-radius:8px;margin:20px 0;font-family:monospace;font-size:18px;text-align:center;color:#34d399}
    .step{background:#16213e;padding:20px;border-radius:8px;margin:15px 0;border-left:4px solid #e94560}
    .step h3{margin-top:0;color:#e94560}
    .step-num{display:inline-block;background:#e94560;color:#fff;width:28px;height:28px;border-radius:50%;text-align:center;line-height:28px;margin-right:10px;font-weight:bold}
    code{background:#0f3460;padding:2px 8px;border-radius:4px;font-family:monospace}
    ul{padding-left:20px}
    li{margin:8px 0}
  </style>
</head>
<body>
  <h1>MediaFusion (Prototype)</h1>

  <div class="warn">
    <strong>⚠️ PROTOTYPE - FOR TESTING ONLY ⚠️</strong><br>
    Follow the steps below to set up MediaFusion with your own torrent sources.
  </div>

  <div class="password-box">
    <strong>Password:</strong> ${PCS_DEFAULT_PASSWORD}
  </div>

  <div class="step">
    <h3><span class="step-num">1</span>Open Configure Page</h3>
    <p>Click to open the MediaFusion configuration page:</p>
    <a class="btn" href="https://mediafusionprotoapi-${REF_DOMAIN}/configure" target="_blank">Open Configure Page ↗</a>
    <p style="font-size:14px;color:#888;margin-top:10px">• Click <strong>"Pro User"</strong> to see all options</p>
  </div>

  <div class="step">
    <h3><span class="step-num">2</span>Enable Live Search</h3>
    <p>Scroll down to <strong>"Streaming Preferences"</strong> section:</p>
    <ul style="font-size:14px;color:#ccc">
      <li>✅ Check <strong>"Enable on-demand search for movies & series streams"</strong></li>
    </ul>
    <p style="font-size:14px;color:#fbbf24;margin-top:10px">Without this, no torrents will be found!</p>
  </div>

  <div class="step">
    <h3><span class="step-num">3</span>Configure Streaming Provider</h3>
    <p>In the configuration page, set these values:</p>
    <ul style="font-size:14px;color:#ccc">
      <li><strong>Streaming Provider:</strong> <code>qBittorrent</code></li>
      <li><strong>qBittorrent URL:</strong> <code>http://qbittorrent:80/qbittorrent/</code></li>
      <li><strong>Username:</strong> <code>admin</code></li>
      <li><strong>Password:</strong> <code>${PCS_DEFAULT_PASSWORD}</code></li>
      <li><strong>WebDAV URL:</strong> <code>http://qbittorrent:80/webdav/</code></li>
      <li><strong>WebDAV Username:</strong> (leave blank)</li>
      <li><strong>WebDAV Password:</strong> (leave blank)</li>
    </ul>
  </div>

  <div class="step">
    <h3><span class="step-num">4</span>Generate & Install Addon</h3>
    <p>Scroll down and click <strong>"Install in Stremio"</strong></p>
    <p style="font-size:14px;color:#ccc;margin-top:10px">Or copy the addon URL and paste it in Stremio manually.</p>
  </div>

  <div class="step">
    <h3><span class="step-num">5</span>Add Your Torrent Sources</h3>
    <p>Open Prowlarr to add your preferred torrent indexers:</p>
    <a class="btn btn-secondary" href="https://mediafusionprotoprowlarr-${REF_DOMAIN}/" target="_blank">Open Prowlarr ↗</a>
    <ul style="font-size:14px;color:#ccc;margin-top:15px">
      <li><strong>Username:</strong> <code>admin</code></li>
      <li><strong>Password:</strong> <code>${PCS_DEFAULT_PASSWORD}</code></li>
    </ul>
    <p style="font-size:14px;color:#ccc;margin-top:10px">In Prowlarr: <strong>Settings → Indexers → Add Indexer</strong></p>
    <p style="font-size:14px;color:#888;margin-top:5px">Add your preferred torrent indexers (e.g., 1337x, RARBG, etc.)</p>
  </div>

  <p style="margin-top:30px;color:#888;font-size:13px">
    Port 6881 exposed on IPv6 for 10x better peer connectivity.
  </p>
</body>
</html>
HTMLEOF

echo "MediaFusion Proto pre-install completed successfully"
