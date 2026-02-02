#!/bin/bash
# MediaFusion Proto Pre-Install Script
# Creates directories and generates pre-configured addon URL

APP_DIR="/DATA/AppData/mediafusionproto"

echo "Creating MediaFusion Proto directories..."
mkdir -p "$APP_DIR"/{qbittorrent/downloads,qbittorrent/config/qBittorrent/config,postgres,mongodb,redis,prowlarr,config}
chown -R 1000:1000 "$APP_DIR" 2>/dev/null || true
chmod -R 755 "$APP_DIR"

# Generate qBittorrent password hash (PBKDF2-SHA512, 100000 iterations)
# Uses environment variable to avoid shell injection with special characters
echo "Generating qBittorrent password hash..."
export QB_PASSWORD="${PCS_DEFAULT_PASSWORD}"
QB_PASS_HASH=$(python3 -c "
import hashlib, base64, os
salt = os.urandom(16)
password = os.environ['QB_PASSWORD']
dk = hashlib.pbkdf2_hmac('sha512', password.encode(), salt, 100000, dklen=64)
print('@ByteArray(' + base64.b64encode(salt).decode() + ':' + base64.b64encode(dk).decode() + ')')
")
unset QB_PASSWORD

# qBittorrent config with pre-set password
cat > "$APP_DIR/qbittorrent/config/qBittorrent/config/qBittorrent.conf" << QBTCONF
[BitTorrent]
Session\DefaultSavePath=/downloads
Session\Port=6881
Session\QueueingSystemEnabled=false

[Preferences]
WebUI\Username=admin
WebUI\Password_PBKDF2=$QB_PASS_HASH
WebUI\LocalHostAuth=false
WebUI\AuthSubnetWhitelistEnabled=true
WebUI\AuthSubnetWhitelist=0.0.0.0/0
QBTCONF

echo "Pre-configuring Prowlarr with known API key..."
# Fixed API key - Prowlarr is only accessible internally on Docker network
PROWLARR_API_KEY="a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"

# Create Prowlarr config.xml with pre-set API key (no auth for local)
cat > "$APP_DIR/prowlarr/config.xml" << PROWLARRCONF
<Config>
  <LogLevel>info</LogLevel>
  <UrlBase></UrlBase>
  <ApiKey>${PROWLARR_API_KEY}</ApiKey>
  <AuthenticationMethod>None</AuthenticationMethod>
  <AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>
  <InstanceName>Prowlarr</InstanceName>
</Config>
PROWLARRCONF
chmod 644 "$APP_DIR/prowlarr/config.xml"

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

echo "Creating nginx proxy config for qBittorrent API (duplicate torrent fix)..."
cat > "$APP_DIR/nginx-qbapi.conf" << 'NGINXCONF'
# Proxy for qBittorrent API that fixes duplicate torrent handling
# Problem: MediaFusion doesn't check if torrent exists before adding
#          qBittorrent returns "Fails." for duplicates, MediaFusion errors
# Solution: Use nginx mirror to fire-and-forget to qBittorrent, always return "Ok."

server {
    listen 80;
    resolver 127.0.0.11 valid=10s;

    # Intercept torrent add endpoint - mirror to qBittorrent, return Ok immediately
    location = /qbittorrent/api/v2/torrents/add {
        mirror /mirror_torrent_add;
        mirror_request_body on;
        default_type text/plain;
        return 200 "Ok.";
    }

    # Internal location for mirrored request (fire-and-forget to real qBittorrent)
    location = /mirror_torrent_add {
        internal;
        proxy_pass http://qbittorrent:8080/qbittorrent/api/v2/torrents/add;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_pass_request_body on;
        proxy_set_header Content-Type $content_type;
    }

    # All other qBittorrent API/WebUI requests pass through unchanged
    location / {
        proxy_pass http://qbittorrent:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
    }
}
NGINXCONF

echo "Creating nginx proxy config for WebDAV..."
cat > "$APP_DIR/nginx-webdav.conf" << 'NGINXCONF'
server {
    listen 80;
    location / {
        # CORS headers for Stremio web player
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, HEAD, OPTIONS";
        add_header Access-Control-Allow-Headers "Range, If-Range";
        add_header Access-Control-Expose-Headers "Content-Length, Content-Range, Accept-Ranges";

        # Handle preflight
        if ($request_method = OPTIONS) {
            return 204;
        }

        # Proxy to qBittorrent WebDAV (no /webdav/ suffix - MediaFusion adds it)
        proxy_pass http://qbittorrent:80/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Range $http_range;
        proxy_set_header If-Range $http_if_range;
        proxy_pass_header Accept-Ranges;
        proxy_pass_header Content-Range;
        proxy_pass_header Content-Length;
        proxy_pass_header Content-Type;
        proxy_buffering off;
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
    <p class="section-label">Section 1: "Configuration Mode"</p>
    <p style="color:#ccc">Click <strong>"Pro User"</strong> toggle to see all options</p>
  </div>

  <div class="step">
    <h3><span class="step-num">2</span>Configure Streaming Provider</h3>
    <p class="section-label">Section 2: "Streaming Provider Configuration"</p>
    <p style="color:#ccc;margin-bottom:10px">Select <strong>qBittorrent</strong> from the dropdown</p>

    <p class="section-label" style="margin-top:15px">Subsection: "qBittorrent Configuration" (appears after selecting qBittorrent)</p>
    <ul>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('http://qbittorrent-api:80/qbittorrent/', this)">Copy</button>
        <span class="field-label">qBittorrent URL:</span>
        <code>http://qbittorrent-api:80/qbittorrent/</code>
      </li>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('admin', this)">Copy</button>
        <span class="field-label">Username:</span>
        <code>admin</code>
      </li>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('${PCS_DEFAULT_PASSWORD}', this)">Copy</button>
        <span class="field-label">Password:</span>
        <code>${PCS_DEFAULT_PASSWORD}</code>
      </li>
    </ul>

    <p class="section-label">Subsection: "WebDAV Configuration"</p>
    <ul>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('https://mediafusionprotowebdav-${REF_DOMAIN}/', this)">Copy</button>
        <span class="field-label">WebDAV URL:</span>
        <code>https://mediafusionprotowebdav-${REF_DOMAIN}/</code>
      </li>
      <li class="field-row">
        <span class="field-label">Username:</span>
        <span style="color:#888">(leave blank)</span>
      </li>
      <li class="field-row">
        <span class="field-label">Password:</span>
        <span style="color:#888">(leave blank)</span>
      </li>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('/webdav/', this)">Copy</button>
        <span class="field-label">Downloads Path:</span>
        <code>/webdav/</code>
      </li>
    </ul>

    <p class="section-label" style="margin-top:15px">Section 3: "Catalog Configuration"</p>
    <p style="color:#888;font-size:14px"><strong>Skip</strong> - Choose which categories appear in Stremio. Defaults are fine.</p>

    <p class="section-label">Section 4: "Parental Guides"</p>
    <p style="color:#888;font-size:14px"><strong>Skip</strong> - Content rating filters. Defaults allow all content.</p>
  </div>

  <div class="step">
    <h3><span class="step-num">3</span>Enable Live Search</h3>
    <p class="section-label">Section 5: "Streaming Preferences"</p>
    <p style="color:#ccc">Find and check: <strong>"Enable on-demand search for movies & series streams"</strong></p>
    <p style="color:#fbbf24;margin-top:10px">⚠️ Without this, no torrents will be found!</p>
    <p style="color:#888;font-size:14px;margin-top:10px">This section also has resolution/quality filters and sorting options - <strong>optional</strong>, defaults work fine.</p>

    <p class="section-label" style="margin-top:15px">Section 6: "External Services Configuration"</p>
    <p style="color:#888;font-size:14px"><strong>Skip</strong> - For MediaFlow, RPDB, MDBList integration. Not needed.</p>
  </div>

  <div class="step">
    <h3><span class="step-num">4</span>Set Password & Install</h3>
    <p class="section-label">Section 7: "API Security Configuration" (bottom of page)</p>
    <ul>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('${PCS_DEFAULT_PASSWORD}', this)">Copy</button>
        <span class="field-label">API Password:</span>
        <code>${PCS_DEFAULT_PASSWORD}</code>
      </li>
    </ul>
    <p style="color:#ccc;margin-top:15px">Click <strong>"Copy Manifest URL"</strong> → paste into Stremio's search bar</p>
    <p style="color:#888;font-size:14px;margin-top:10px">⚠️ Don't share your manifest URL - it contains your configuration.</p>
  </div>

  <div class="step">
    <h3><span class="step-num">5</span>Add Your Torrent Sources</h3>
    <a class="btn btn-secondary" href="https://mediafusionprotoprowlarr-${REF_DOMAIN}/" target="_blank">Open Prowlarr ↗</a>
    <p class="section-label" style="margin-top:15px">Login credentials:</p>
    <ul>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('admin', this)">Copy</button>
        <span class="field-label">Username:</span>
        <code>admin</code>
      </li>
      <li class="field-row">
        <button class="copy-btn" onclick="copyText('${PCS_DEFAULT_PASSWORD}', this)">Copy</button>
        <span class="field-label">Password:</span>
        <code>${PCS_DEFAULT_PASSWORD}</code>
      </li>
    </ul>

    <p class="section-label" style="margin-top:15px">Cloudflare Bypass</p>
    <p style="color:#34d399;font-size:14px">✓ FlareSolverr (Byparr) is <strong>auto-configured</strong>. No manual setup needed.</p>

    <p class="section-label" style="margin-top:15px">Add Indexers</p>
    <p style="color:#ccc;font-size:14px">Go to <strong>Indexers → +</strong> → search for your site (e.g., 1337x, Nyaa)</p>
    <p style="color:#fbbf24;font-size:14px;margin-top:8px">⚠️ For sites with Cloudflare protection: scroll to bottom and add Tag: <code>cf</code></p>
    <p style="color:#888;font-size:14px">The tag routes the indexer through the Cloudflare bypass proxy (Byparr).</p>
  </div>

  <p style="margin-top:30px;color:#888;font-size:13px">
    Port 6881 exposed on IPv6 for 10x better peer connectivity.
  </p>

  <script>
  function copyText(text, btn) {
    navigator.clipboard.writeText(text).then(function() {
      btn.textContent = 'Copied!';
      btn.classList.add('copied');
      setTimeout(function() {
        btn.textContent = 'Copy';
        btn.classList.remove('copied');
      }, 1500);
    });
  }
  </script>
</body>
</html>
HTMLEOF

echo "MediaFusion Proto pre-install completed successfully"
