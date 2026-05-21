#!/bin/bash
set -euxo pipefail

# Log everything for debugging
exec > >(tee /var/log/inference-userdata.log | logger -t userdata ) 2>&1
echo "=== Inference worker userdata started: $(date) ==="

GATEWAY_IP="${gateway_private_ip}"

##############################################################################
# 1. System packages
##############################################################################
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl git jq python3 python3-pip python3-venv netcat-openbsd

##############################################################################
# Extra swap for memory-constrained free-tier instance
##############################################################################
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

##############################################################################
# 2. Install iii CLI
##############################################################################

export HOME=/root

curl -fsSL https://install.iii.dev/iii/main/install.sh | sh

export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> /root/.bashrc

/root/.local/bin/iii --version

##############################################################################
# 3. Clone your repo
##############################################################################
git clone ${github_repo} /opt/iii-inference
cd /opt/iii-inference

##############################################################################
# 4. Python virtual environment + dependencies
##############################################################################
python3 -m venv /opt/iii-venv
source /opt/iii-venv/bin/activate

pip install --upgrade pip
pip install --no-cache-dir -r /opt/iii-inference/workers/inference-worker/requirements.txt

deactivate

##############################################################################
# 5. Wait for iii engine on gateway to be ready
#    Without this the worker starts before the engine and fails silently
##############################################################################
echo "=== Waiting for iii engine at $GATEWAY_IP:49134 ==="
until nc -z "$GATEWAY_IP" 49134; do
  echo "Engine not ready yet - retrying in 10s..."
  sleep 10
done
echo "=== Engine is ready ==="

##############################################################################
# 6. systemd — inference worker
##############################################################################
cat > /etc/systemd/system/inference-worker.service << EOF
[Unit]
Description=iii Inference Worker (Python)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/iii-inference/workers/inference-worker
Environment=III_URL=ws://${gateway_private_ip}:49134
Environment=HOME=/root
ExecStart=/opt/iii-venv/bin/python inference_worker.py
Restart=on-failure
RestartSec=15
StandardOutput=journal
StandardError=journal
SyslogIdentifier=inference-worker

[Install]
WantedBy=multi-user.target
EOF

##############################################################################
# 7. Start inference worker
#    Model downloads on first start — takes 3-5 mins
##############################################################################
systemctl daemon-reload
systemctl enable inference-worker
systemctl start  inference-worker

##############################################################################
# 8. Health check
##############################################################################
sleep 30
systemctl is-active inference-worker && \
  echo "=== Inference worker running ===" || \
  echo "=== WARNING: inference worker not active - check logs ==="

echo "=== Inference userdata complete: $(date) ==="