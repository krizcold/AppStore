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
    ul{padding-left:20px;list-style:none}
    li{margin:10px 0}
    .copy-btn{background:#e94560;color:#fff;border:none;padding:2px 8px;border-radius:4px;cursor:pointer;font-size:12px;margin-right:8px}
    .copy-btn:hover{background:#ff6b6b}
    .copy-btn.copied{background:#34d399}
    .section-label{color:#888;font-size:12px;text-transform:uppercase;letter-spacing:1px;margin:15px 0 8px 0}
    .field-row{display:flex;align-items:center;margin:8px 0}
    .field-label{min-width:140px;color:#ccc}
    .field-value code{margin-left:5px}
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
    <a class="btn" href="https://mediafusionprotoapi-${REF_DOMAIN}/configure" target="_blank">Open Configure Page ↗</a>
    <p class="section-label">At the very top of the page:</p>
    <p style="color:#ccc">Click <strong>"Pro User"</strong> toggle to see all options</p>
  </div>

  <div class="step">
    <h3><span class="step-num">2</span>Configure Streaming Provider</h3>
    <p class="section-label">Section: "Streaming Provider" (2nd section from top)</p>
    <ul>
      <li class="field-row">
        <span class="field-label">Streaming Provider:</span>
        <span>Select <code>qBittorrent</code></span>
      </li>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('http://qbittorrent:80/qbittorrent/')">Copy</button>
        <span class="field-label">qBittorrent URL:</span>
        <code>http://qbittorrent:80/qbittorrent/</code>
      </li>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('admin')">Copy</button>
        <span class="field-label">Username:</span>
        <code>admin</code>
      </li>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('${PCS_DEFAULT_PASSWORD}')">Copy</button>
        <span class="field-label">Password:</span>
        <code>${PCS_DEFAULT_PASSWORD}</code>
      </li>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('http://qbittorrent:80/webdav/')">Copy</button>
        <span class="field-label">WebDAV URL:</span>
        <code>http://qbittorrent:80/webdav/</code>
      </li>
      <li class="field-row">
        <span class="field-label">WebDAV Username:</span>
        <span style="color:#888">(leave blank)</span>
      </li>
      <li class="field-row">
        <span class="field-label">WebDAV Password:</span>
        <span style="color:#888">(leave blank)</span>
      </li>
    </ul>
  </div>

  <div class="step">
    <h3><span class="step-num">3</span>Enable Live Search</h3>
    <p class="section-label">Section: "Live Search Streams" (scroll way down, near the END of the page)</p>
    <p style="color:#ccc">✅ Check <strong>"Enable on-demand search for movies & series streams"</strong></p>
    <p style="color:#fbbf24;margin-top:10px">⚠️ Without this, no torrents will be found!</p>
  </div>

  <div class="step">
    <h3><span class="step-num">4</span>Install Addon</h3>
    <p class="section-label">At the very bottom of the page:</p>
    <p style="color:#ccc">Click <strong>"Install in Stremio"</strong></p>
  </div>

  <div class="step">
    <h3><span class="step-num">5</span>Add Your Torrent Sources</h3>
    <a class="btn btn-secondary" href="https://mediafusionprotoprowlarr-${REF_DOMAIN}/" target="_blank">Open Prowlarr ↗</a>
    <p class="section-label" style="margin-top:15px">Login credentials:</p>
    <ul>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('admin')">Copy</button>
        <span class="field-label">Username:</span>
        <code>admin</code>
      </li>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('${PCS_DEFAULT_PASSWORD}')">Copy</button>
        <span class="field-label">Password:</span>
        <code>${PCS_DEFAULT_PASSWORD}</code>
      </li>
    </ul>
    <p class="section-label">In Prowlarr:</p>
    <p style="color:#ccc">Go to <strong>Indexers → Add Indexer</strong> and add your preferred torrent sites (e.g., 1337x, TorrentGalaxy)</p>
  </div>

  <p style="margin-top:30px;color:#888;font-size:13px">
    Port 6881 exposed on IPv6 for 10x better peer connectivity.
  </p>

  <script>
  function copyText(text) {
    navigator.clipboard.writeText(text).then(function() {
      event.target.textContent = 'Copied!';
      event.target.classList.add('copied');
      setTimeout(function() {
        event.target.textContent = 'Copy';
        event.target.classList.remove('copied');
      }, 1500);
    });
  }
  </script>
</body>
</html>
HTMLEOF

echo "MediaFusion Proto pre-install completed successfully"
