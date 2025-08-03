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

# Create certificate directory
mkdir -p /home/ubuntu/certs

# Install acme.sh and issue certificate
curl https://get.acme.sh | sh -s email="$MAIL"
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" \
  --fullchain-file "/home/ubuntu/certs/fullchain.pem" \
  --key-file "/home/ubuntu/certs/privkey.pem" \
  --force

# Check if certificate issuance was successful
if [ ! -f "/home/ubuntu/certs/fullchain.pem" ] || [ ! -f "/home/ubuntu/certs/privkey.pem" ]; then
    echo "Error: Certificate issuance failed."
    exit 1
fi

# Configure Nginx
cat > /etc/nginx/sites-available/vlessgrpc <<EOF
server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /home/ubuntu/certs/fullchain.pem;
    ssl_certificate_key /home/ubuntu/certs/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH;
    ssl_prefer_server_ciphers on;

    location /vless-service {
        if (\$http_content_type !~ "application/grpc") {
            return 400;
        }
        grpc_pass grpc://127.0.0.1:2025;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /health {
        return 200 'OK';
        default_type text/plain;
    }

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
chmod 600 /home/ubuntu/certs/privkey.pem

# Restart services
systemctl restart xray nginx

# Verify services are running
if systemctl is-active --quiet xray && systemctl is-active --quiet nginx; then
    echo "Xray and Nginx have been configured and started successfully."
    echo "vless://1f9b8529-d065-4ac2-a1f2-d56a2c2edbc1@$DOMAIN:443?encryption=none&security=tls&type=grpc&serviceName=vless-service&sni=$DOMAIN#vless-grpc"
else
    echo "Error: Failed to start Xray or Nginx."
    exit 1
fi
