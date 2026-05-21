#!/bin/bash
set -euo pipefail

# Log everything for debugging
exec > /var/log/gateway-userdata.log 2>&1
echo "=== Gateway userdata started: $(date) ==="

##############################################################################
# 1. System packages
##############################################################################
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl git nginx nodejs npm

# Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

##############################################################################
# 2. Install iii CLI
##############################################################################
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> /root/.bashrc
iii --version

##############################################################################
# 3. Clone your repo
##############################################################################
git clone ${github_repo} /opt/iii-inference
cd /opt/iii-inference

##############################################################################
# 4. Install caller-worker dependencies
##############################################################################
cd /opt/iii-inference/workers/caller-worker
npm install

##############################################################################
# 5. Write iii engine config
##############################################################################
cat > /opt/iii-inference/config.yaml << 'EOF'
workers:
  - name: iii-observability
    config:
      enabled: true
      service_name: iii
      exporter: memory
      memory_max_spans: 10000
      metrics_enabled: true
      metrics_exporter: memory
      logs_enabled: true
      logs_exporter: memory
      logs_console_output: true
      sampling_ratio: 1.0
  - name: iii-queue
    config:
      adapter:
        name: builtin
  - name: iii-state
    config:
      adapter:
        name: kv
        config:
          store_method: file_based
          file_path: ./data/state_store.db
  - name: iii-http
    config:
      port: 3111
      host: 0.0.0.0
      default_timeout: 300000
      concurrency_request_limit: 1024
      cors:
        allowed_origins:
          - '*'
        allowed_methods:
          - GET
          - POST
          - PUT
          - DELETE
          - OPTIONS
EOF

##############################################################################
# 6. systemd — iii engine
##############################################################################
cat > /etc/systemd/system/iii-engine.service << 'EOF'
[Unit]
Description=iii Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/iii-inference
ExecStart=/root/.local/bin/iii --config config.yaml
Restart=on-failure
RestartSec=5
Environment=HOME=/root
StandardOutput=journal
StandardError=journal
SyslogIdentifier=iii-engine

[Install]
WantedBy=multi-user.target
EOF

##############################################################################
# 7. systemd — caller-worker
##############################################################################
cat > /etc/systemd/system/caller-worker.service << 'EOF'
[Unit]
Description=iii Caller Worker (TypeScript)
After=iii-engine.service
Requires=iii-engine.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/iii-inference/workers/caller-worker
Environment=III_URL=ws://localhost:49134
Environment=HOME=/root
ExecStart=/usr/bin/npx tsx src/worker.ts
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=caller-worker

[Install]
WantedBy=multi-user.target
EOF

##############################################################################
# 8. nginx config
##############################################################################
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/iii-inference << 'EOF'
server {
    listen 80 default_server;
    server_name _;

    # Inference API
    location /v1/ {
        proxy_pass         http://127.0.0.1:3111;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_read_timeout    300s;
        proxy_connect_timeout 10s;
        proxy_send_timeout    300s;
    }

    # Health check
    location /health {
        proxy_pass http://127.0.0.1:3111;
    }

    # Block everything else
    location / {
        return 404 '{"error":"not found"}';
        add_header Content-Type application/json always;
    }
}
EOF

ln -sf /etc/nginx/sites-available/iii-inference \
       /etc/nginx/sites-enabled/iii-inference
nginx -t

##############################################################################
# 9. Start all services
##############################################################################
systemctl daemon-reload
systemctl enable iii-engine caller-worker nginx
systemctl start  iii-engine
sleep 8
systemctl start  caller-worker
systemctl start  nginx

echo "=== Gateway userdata complete: $(date) ==="