#!/bin/bash

# Configuration
DOMAIN="nextgen.sibondt.my.id"
EMAIL="admin@${DOMAIN}"
MARZNESHIN_VERSION="0.7.4"
MARZNESHIN_TAR="v${MARZNESHIN_VERSION}.tar.gz"
MARZNESHIN_URL="https://github.com/marzneshin/marzneshin/archive/refs/tags/${MARZNESHIN_TAR}"
INSTALL_DIR="/opt"
CERT_PARENT_DIR="/home/$(ls /home | head -n 1)"
CERT_DIR="${CERT_PARENT_DIR}/certs"

# Exit on error and trace commands
set -e
set -o xtrace

# Helper function to print status messages
info() {
    echo -e "[INFO] $1"
}

# Update system and install dependencies
info "Updating system and installing dependencies"
apt-get update
apt-get install -y python3-full net-tools tree nodejs npm make nginx curl wget socat 
apt install -y make-guile

# Create installation directory
info "Creating installation directory at ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# Download and extract Marzneshin
info "Downloading Marzneshin ${MARZNESHIN_VERSION}"
wget "${MARZNESHIN_URL}" -O "${MARZNESHIN_TAR}"
tar xzf "${MARZNESHIN_TAR}"
rm "${MARZNESHIN_TAR}"
mv "marzneshin-${MARZNESHIN_VERSION}" marzneshin
cd marzneshin

# Setup Python virtual environment
info "Setting up Python virtual environment"
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

# Install Node.js dependencies
info "Installing Node.js dependencies"
npm install -g pnpm
make dashboard-deps

# Stop Nginx if running
info "Stopping Nginx service"
systemctl stop nginx >/dev/null 2>&1 || true

# Setup SSL certificates
info "Setting up SSL certificates"
mkdir -p "${CERT_DIR}"

if [ -f "${CERT_DIR}/server.key" ]; then
    info "Certificate already exists, skipping generation"
else
    info "Installing acme.sh and generating certificates"
    curl https://get.acme.sh | sh -s email="${EMAIL}"
    ~/.acme.sh/acme.sh --issue --standalone -d "${DOMAIN}" \
        --key-file "${CERT_DIR}/server.key" \
        --fullchain-file "${CERT_DIR}/server.cert" \
        --force
fi

# Configure Nginx
info "Configuring Nginx"
cat > /etc/nginx/sites-available/marzneshin <<EOF
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate      ${CERT_DIR}/server.cert;
    ssl_certificate_key  ${CERT_DIR}/server.key;

    location / {
        proxy_pass http://0.0.0.0:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    return 301 https://\$host\$request_uri;
}
EOF

# Create systemd service file
info "Creating systemd service"
cat > /etc/systemd/system/marzneshin.service <<EOF
[Unit]
Description=Marzneshin Service
Documentation=https://docs.marzneshin.org
After=network.target nss-lookup.target

[Service]
ExecStart=${INSTALL_DIR}/marzneshin/.venv/bin/python ${INSTALL_DIR}/marzneshin/main.py
Restart=on-failure
WorkingDirectory=${INSTALL_DIR}/marzneshin

[Install]
WantedBy=multi-user.target
EOF

cp /opt/marzneshin/.env.example /opt/marzneshin/.env
# Enable and start services
info "Enabling and starting services"
systemctl daemon-reload
systemctl enable marzneshin.service

# Configure Nginx
ln -sf /etc/nginx/sites-available/marzneshin /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Build dashboard and restart services
info "Building dashboard and restarting services"
make dashboard-build
systemctl restart nginx
systemctl restart marzneshin.service

info "Installation completed successfully!"
