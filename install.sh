#!/bin/bash

# Update and install required packages
apt update && apt install -y socat tree net-tools nginx curl wget

# Install Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Prompt for domain name and validate
read -p "Enter your domain name: " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo "Error: Domain name cannot be empty."
    exit 1
fi

# Prompt for email and validate
read -p "Enter your email for Let's Encrypt (e.g., inibudi@daouse.com): " MAIL
if [ -z "$MAIL" ]; then
    echo "Error: Email cannot be empty."
    exit 1
fi

systemctl stop nginx
# Create certificate directory
mkdir -p /home/ubuntu/certs

# Install acme.sh and issue certificate
curl https://get.acme.sh | sh -s email="$MAIL"
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" \
  --fullchain-file "/home/ubuntu/certs/fullchain.pem" \
  --key-file "/home/ubuntu/certs/key.pem" \
  --force

# Check if certificate issuance was successful
if [ ! -f "/home/ubuntu/certs/fullchain.pem" ] || [ ! -f "/home/ubuntu/certs/key.pem" ]; then
    echo "Error: Certificate issuance failed."
    exit 1
fi

# Configure Nginx
cat > /etc/nginx/sites-available/vlessgrpc <<EOF
# Upstream for the VLESS gRPC service running on port 2025
upstream vless_grpc_backend {
    server 127.0.0.1:2025;
    keepalive 16;
}

# Upstream for the Trojan gRPC service running on port 2026
upstream trojan_grpc_backend {
    server 127.0.0.1:2026;
    keepalive 16;
}

# Main server block to handle incoming HTTPS traffic
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    # --- SSL Certificate Configuration ---
    ssl_certificate /home/ubuntu/certs/fullchain.pem;
    ssl_certificate_key /home/ubuntu/certs/key.pem;
    ssl_trusted_certificate /home/ubuntu/certs/fullchain.pem;
    
    # --- SSL Performance and Security Enhancements ---
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_stapling on;
    ssl_stapling_verify on;

    # --- Location Blocks for Routing ---

    # Location for VLESS gRPC service
    # The 'if' block has been removed for simplicity. 
    # Xray will handle any non-gRPC requests.
    location /vless-service {
        grpc_read_timeout 300s;
        grpc_send_timeout 300s;
        grpc_pass grpc://vless_grpc_backend;
    }

    # Location for Trojan gRPC service
    # The 'if' block has been removed for simplicity.
    location /trojan-service {
        grpc_read_timeout 300s;
        grpc_send_timeout 300s;
        grpc_pass grpc://trojan_grpc_backend;
    }

    # Default location to block any other requests
    location / {
        return 403;
    }
}
EOF

# Remove default Nginx site and enable new configuration
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/vlessgrpc /etc/nginx/sites-enabled/vlessgrpc

# Configure Xray
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "debug"
  },
  "dns": {
    "servers": [
      "1.1.1.1",
      "1.0.0.1"
    ]
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "outboundTag": "block",
        "domain": [
          "geosite:category-ads-all"
        ]
      }
    ]
  },
  "inbounds": [
    {
      "port": 2025,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "1f9b8529-d065-4ac2-a1f2-d56a2c2edbc1",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": {
          "serviceName": "vless-service"
        }
      }
    },
    {
      "port": 2026,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "ec0a721c3be5d839",
            "level": 0
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": {
          "serviceName": "trojan-service"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

# Set proper permissions for certificates
chown -R www-data:www-data /home/ubuntu/certs
chmod 600 /home/ubuntu/certs/key.pem

# Firewall configuration
echo "Configuring firewall..."
ufw allow 8000/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 22/tcp
ufw allow 2222/tcp
ufw allow 2021/tcp
ufw allow 2022/tcp
ufw allow 2023/tcp
ufw allow 2024/tcp
ufw allow 2025/tcp
ufw allow 2026/tcp
ufw allow 2027/tcp
ufw allow 2028/tcp
ufw allow 51820/tcp
ufw allow 51821/tcp
ufw allow 51822/tcp
ufw allow 51823/tcp
ufw allow 51824/tcp
ufw allow 51825/tcp
ufw allow 8443/tcp
ufw allow 9443/tcp
ufw allow 62050/tcp
ufw allow 62051/tcp

ufw --force enable

# Restart services
systemctl restart xray nginx

# Verify services are running
if systemctl is-active --quiet xray && systemctl is-active --quiet nginx; then
    echo "Xray and Nginx have been configured and started successfully."
    echo "vless://1f9b8529-d065-4ac2-a1f2-d56a2c2edbc1@$DOMAIN:443?encryption=none&security=tls&type=grpc&serviceName=vless-service&sni=$DOMAIN#vless-grpc"
    echo "trojan://ec0a721c3be5d839@$DOMAIN:443?security=tls&type=grpc&serviceName=trojan-service&sni=$DOMAIN#Trojan-gRPC"
else
    echo "Error: Failed to start Xray or Nginx."
    exit 1
fi
