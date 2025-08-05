#!/bin/bash

# Enhanced Hysteria2 Installer with Auto-Generated Passwords
# Version 2.1 - Automatic secure password generation

# --- Configuration ---
DEFAULT_HYSTERIA_PORT=443
DEFAULT_MASQUERADE_PORT=8080
PASSWORD_LENGTH=16  # Length for auto-generated passwords
TEMP_DIR="/tmp/hysteria-installer"

# --- Functions ---

# Color output
print_color() {
  case "$1" in
    "green") echo -e "\033[32m$2\033[0m" ;;
    "red") echo -e "\033[31m$2\033[0m" ;;
    "yellow") echo -e "\033[33m$2\033[0m" ;;
    "blue") echo -e "\033[34m$2\033[0m" ;;
    *) echo -e "$2" ;;
  esac
}

# Generate secure password
generate_password() {
  tr -dc 'A-Za-z0-9!@#$%^&*()_+=' < /dev/urandom | head -c "$1"
  echo
}

# Validate domain
validate_domain() {
  local domain_regex='^([a-zA-Z0-9](([a-zA-Z0-9-]){0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
  [[ "$1" =~ $domain_regex ]]
}

# --- Main Script ---

# Check root
[ "$(id -u)" -ne 0 ] && { print_color "red" "Run as root with sudo"; exit 1; }

# Setup
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR" || exit 1

# --- User Input ---
clear
print_color "yellow" "┌──────────────────────────────────────────────────────┐"
print_color "yellow" "│      Hysteria2 Auto-Installer with Secure Passwords    │"
print_color "yellow" "└──────────────────────────────────────────────────────┘"

# Domain input
while true; do
  read -p "Enter your domain (e.g., example.com): " DOMAIN
  validate_domain "$DOMAIN" && break
  print_color "red" "Invalid domain format"
done

# Email input
while true; do
  read -p "Enter your email (for Let's Encrypt, example inibudi@daouse.com): " EMAIL
  [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && break
  print_color "red" "Invalid email format"
done

# Auto-generate passwords
HYSTERIA_PASSWORD=$(generate_password "$PASSWORD_LENGTH")
OBFS_PASSWORD=$(generate_password "$PASSWORD_LENGTH")

print_color "green" "\nAuto-generated Hysteria Password: $HYSTERIA_PASSWORD"
print_color "green" "Auto-generated Obfs Password: $OBFS_PASSWORD"

# --- Installation ---
print_color "green" "\nInstalling dependencies..."
apt-get update && apt-get install -y curl wget socat jq certbot python3-certbot-nginx ufw qrencode nginx

# Install Hysteria2
print_color "green" "\nInstalling Hysteria2..."
bash <(curl -fsSL https://get.hy2.sh/)

# --- Configuration ---
mkdir -p /etc/hysteria

# Server config
cat > /etc/hysteria/config.yaml <<EOF
listen: :$DEFAULT_HYSTERIA_PORT
tls:
  cert: /etc/letsencrypt/live/$DOMAIN/fullchain.pem
  key: /etc/letsencrypt/live/$DOMAIN/privkey.pem

auth:
  type: password
  password: "$HYSTERIA_PASSWORD"

masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
    listenHTTP: :$DEFAULT_MASQUERADE_PORT

obfs:
  type: salamander
  salamander:
    password: "$OBFS_PASSWORD"
EOF

# Certificate setup
systemctl stop nginx 2>/dev/null
certbot certonly --standalone --agree-tos --no-eff-email --email "$EMAIL" -d "$DOMAIN"

# Set permissions
chown root:hysteria /etc/letsencrypt/live/$DOMAIN/privkey.pem
chmod 640 /etc/letsencrypt/live/$DOMAIN/privkey.pem
chmod 644 /etc/letsencrypt/live/$DOMAIN/fullchain.pem


# Nginx config
cat > /etc/nginx/sites-available/hysteria <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:$DEFAULT_MASQUERADE_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf /etc/nginx/sites-available/hysteria /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# Firewall
ufw allow ssh
ufw allow http
ufw allow https
ufw allow $DEFAULT_HYSTERIA_PORT/udp
ufw --force enable

# Start services
systemctl enable --now hysteria-server

# --- Client Config ---
CLIENT_CONFIG_JSON="/root/hysteria_client_$DOMAIN.json"
cat > "$CLIENT_CONFIG_JSON" <<EOF
{
  "server": "$DOMAIN:$DEFAULT_HYSTERIA_PORT",
  "auth": "$HYSTERIA_PASSWORD",
  "tls": {
    "sni": "$DOMAIN",
    "insecure": false
  },
  "obfs": {
    "type": "salamander",
    "password": "$OBFS_PASSWORD"
  }
}
EOF

# --- Client Config ---
CLIENT_CONFIG_YAML="/root/hysteria_client_$DOMAIN.yaml"
cat > "$CLIENT_CONFIG_YAML" <<EOF
proxies:
  - name: "Hysteria2-$DOMAIN"
    type: hysteria2
    server: $DOMAIN
    port: $DEFAULT_HYSTERIA_PORT
    password: "$HYSTERIA_PASSWORD"
    sni: $DOMAIN
    skip-cert-verify: false
    alpn: [h3]
    up: "100 Mbps"
    down: "500 Mbps"
    obfs: salamander
    obfs-password: "$OBFS_PASSWORD"
EOF

# --- Final Output ---
print_color "yellow" "\n┌──────────────────────────────────────────────────────┐"
print_color "yellow" "│               Installation Complete!                  │"
print_color "yellow" "└──────────────────────────────────────────────────────┘"

print_color "green" "\nServer Address: $DOMAIN"
print_color "green" "Hysteria Password: $HYSTERIA_PASSWORD"
print_color "green" "Obfuscation Password: $OBFS_PASSWORD"

print_color "blue" "\nClient config saved to: $CLIENT_CONFIG_JSON"
print_color "blue" "Client config saved to: $CLIENT_CONFIG_YAML"

echo "=========================="
print_color "blue" "\nClient JSON Config:"
cat <<EOF
{
  "server": "$DOMAIN:$DEFAULT_HYSTERIA_PORT",
  "auth": "$HYSTERIA_PASSWORD",
  "tls": {
    "sni": "$DOMAIN",
    "insecure": false
  },
  "obfs": {
    "type": "salamander",
    "password": "$OBFS_PASSWORD"
  }
}
EOF

echo "=========================="
print_color "blue" "\nClient YAML Config:"

cat <<EOF
proxies:
  - name: "Hysteria2-$DOMAIN"
    type: hysteria2
    server: $DOMAIN
    port: $DEFAULT_HYSTERIA_PORT
    password: "$HYSTERIA_PASSWORD"
    sni: $DOMAIN
    skip-cert-verify: false
    alpn: [h3]
    up: "100 Mbps"
    down: "500 Mbps"
    obfs: salamander
    obfs-password: "$OBFS_PASSWORD"
EOF

echo "=========================="
# QR code if available
if command -v qrencode >/dev/null; then
  print_color "green" "\nQR Code for client config:"
  qrencode -t ANSIUTF8 < "$CLIENT_CONFIG_YAML"
fi

# Cleanup
rm -rf "$TEMP_DIR"
