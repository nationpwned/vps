#!/bin/bash

# Stop on any error
set -e

# --- Functions ---

# Function to display colored text
print_color() {
  case $1 in
    "green") echo -e "\033[32m$2\033[0m" ;;
    "red") echo -e "\033[31m$2\033[0m" ;;
    "yellow") echo -e "\033[33m$2\033[0m" ;;
    *) echo "$2" ;;
  esac
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# --- Main Script ---

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
  print_color "red" "This script must be run as root. Please use sudo."
  exit 1
fi

# --- User Input ---

print_color "yellow" "Welcome to the Hysteria2 with Nginx Reverse Proxy Installer!"
read -p "Enter your domain name (e.g., yourdomain.com): " DOMAIN
read -p "Enter your email address (for Let's Encrypt) inibudi@daouse.com: " EMAIL
read -s -p "Enter a password for Hysteria2 (InibapakBudi2025): " HYSTERIA_PASSWORD
echo
read -s -p "Enter a password for obfuscation (optional, press Enter to skip) (IniibuBudi2025): " OBFS_PASSWORD
echo

# --- Install Dependencies ---

print_color "green" "Updating system and installing dependencies..."
apt-get update && apt-get upgrade -y
apt-get install -y curl wget socat jq certbot python3-certbot-nginx

# --- Install Hysteria2 ---

print_color "green" "Installing Hysteria2..."
bash <(curl -fsSL https://get.hy2.sh/)

# --- Configure Hysteria2 ---

print_color "green" "Configuring Hysteria2..."
mkdir -p /etc/hysteria

# Base config
cat > /etc/hysteria/config.yaml <<EOF
listen: :443

acme:
  domains:
    - $DOMAIN
  email: $EMAIL

auth:
  type: password
  password: $HYSTERIA_PASSWORD
EOF

# Add obfs to server config if password is set
if [ -n "$OBFS_PASSWORD" ]; then
cat >> /etc/hysteria/config.yaml <<EOF

obfs:
  type: salamander
  password: $OBFS_PASSWORD
EOF
fi

# Add masquerade
cat >> /etc/hysteria/config.yaml <<EOF

listen: :443

tls:
  cert: /etc/letsencrypt/live/$DOMAIN/fullchain.pem
  key: /etc/letsencrypt/live/$DOMAIN/privkey.pem

auth:
  type: password
  password: inibapakbudi

masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOF

# --- Stop Nginx for Certificate Generation ---

print_color "yellow" "Stopping Nginx to generate SSL certificate..."
if systemctl is-active --quiet nginx; then
    systemctl stop nginx
fi

# --- Generate SSL Certificate ---

print_color "green" "Generating SSL certificate with Certbot..."
certbot certonly --standalone --agree-tos --no-eff-email --email "$EMAIL" -d "$DOMAIN"

# --- Configure Nginx as Reverse Proxy ---
sudo chown root:hysteria /etc/letsencrypt/live/$DOMAIN/privkey.pem
sudo chmod 640 /etc/letsencrypt/live/$DOMAIN/privkey.pem
sudo chmod 644 /etc/letsencrypt/live/$DOMAIN/fullchain.pem

print_color "green" "Configuring Nginx as a reverse proxy..."
cat > /etc/nginx/sites-available/hysteria <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Redirect HTTP to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:8080; # Assuming Hysteria's masquerade is on 8080
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF


# firewall configuration
print_color "green" "Configuring UFW firewall..."
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

# Enable the Nginx configuration, avoiding error if it already exists
if [ ! -L /etc/nginx/sites-enabled/hysteria ]; then
  ln -s /etc/nginx/sites-available/hysteria /etc/nginx/sites-enabled/
fi

# --- Start Services ---

print_color "green" "Starting Nginx and Hysteria2 services..."
systemctl start nginx
systemctl restart hysteria-server.service

# --- Display Client Configuration ---

print_color "yellow" "Installation complete! Client configurations below."

# --- Standard Client Config (JSON) ---
print_color "yellow" "\nStandard Hysteria2 Client Configuration (config.json):"
print_color "green" "========================================================"

# Base client config
CLIENT_CONFIG_JSON=$(cat <<EOF
{
  "server": "$DOMAIN:443",
  "auth": "$HYSTERIA_PASSWORD",
  "tls": {
    "sni": "$DOMAIN",
    "insecure": false
  }
}
EOF
)

# Add obfs to client config if password is set
if [ -n "$OBFS_PASSWORD" ]; then
  CLIENT_CONFIG_JSON=$(echo "$CLIENT_CONFIG_JSON" | jq --arg obfs_pass "$OBFS_PASSWORD" '. + {obfs: {type: "salamander", password: $obfs_pass}}')
fi

# Pretty print the final JSON
echo "$CLIENT_CONFIG_JSON" | jq .
print_color "green" "========================================================"

# --- Clash Meta (mihomo) Client Config (YAML) ---
print_color "yellow" "\nClash Meta (mihomo) Client Configuration (YAML snippet):"
print_color "green" "========================================================"
# Base YAML config
cat <<EOF
proxies:
  - name: "Hysteria2"
    type: hysteria2
    server: $DOMAIN
    port: 443
    password: "$PASSWORD"
    sni: $DOMAIN
    skip-cert-verify: false
    alpn: [h3]
    protocol: udp
    up: "100 Mbps"
    down: "500 Mbps"
EOF

# Conditionally add obfuscation to YAML
if [ -n "$OBFS_PASSWORD" ]; then
cat <<EOF
    obfs: salamander
    obfs-password: $OBFS_PASSWORD
EOF
fi
print_color "green" "========================================================"
print_color "yellow" "Add the YAML snippet to your Clash Meta configuration file."
