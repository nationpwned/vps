#!/bin/bash

set -e
# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (e.g., with sudo su)" >&2
  exit 1
fi
# Define the domain for your pasarguard instance
read -p "Enter your domain for pasarguard: " DOMAIN
read -p "Enter your email for SSL certificate (inibudi@daouse.com): " MAIL
read -p "Enter your pasarguard admin username (admin): " ADMIN


# Update the system and install necessary packages
apt update -qq -y
apt install curl wget git ufw gnupg2 lsb-release socat tree idn net-tools vnstat iptables xz-utils apt-transport-https dnsutils cron bash-completion -y

# Install speedtest
echo "Checking for existing speedtest installation..."
if command -v speedtest >/dev/null 2>&1; then
    echo "speedtest is already installed. Skipping installation."
else
    echo "Installing speedtest..."
    wget -q https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz > /dev/null 2>&1
    tar xzf ookla-speedtest-1.2.0-linux-x86_64.tgz > /dev/null 2>&1
    mv speedtest /usr/bin/
    rm -f ookla-* speedtest.* > /dev/null 2>&1
fi

# Enable BBR
echo "Enabling BBR congestion control..."
modprobe tcp_bbr >/dev/null 2>&1
echo "tcp_bbr" | tee -a /etc/modules-load.d/modules.conf
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr
if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
  echo "BBR has been enabled."
else
  echo "Failed to enable BBR."
fi

sysctl -w net.mptcp.enabled=1
if sysctl net.mptcp.enabled | grep -q "net.mptcp.enabled = 1"; then
  echo "MPTCP has been enabled."
else
  echo "Failed to enable MPTCP."
fi

sysctl -p >/dev/null 2>&1

if command -v pasarguard >/dev/null 2>&1; then
  echo "Existing pasarguard installation detected. Uninstalling..."
  pasarguard uninstall
fi

bash -c "$(curl -sL http://raw.githubusercontent.com/nationpwned/vps/refs/heads/Pasarguard/install.sh)" @ install --pre-release
sleep 50

pasarguard cli admins --create $ADMIN
sleep 5
pasarguard cli admins --modify $ADMIN
sleep 5

# Install Certificate using acme.sh
bash -c "curl https://get.acme.sh | sh -s email=$MAIL"

bash -c "~/.acme.sh/acme.sh --issue --force --standalone -d \"$DOMAIN\" --fullchain-file \"/var/lib/pasarguard/fullchain.pem\" --key-file \"/var/lib/pasarguard/key.pem\""
pasarguard down

# Set proper permissions
chmod 600 "/var/lib/pasarguard/key.pem"
chmod 644 "/var/lib/pasarguard/fullchain.pem"

wget -O /opt/pasarguard/.env https://github.com/nationpwned/vps/raw/refs/heads/pasarguard/env

# Download docker-compose.yml
wget -O /opt/pasarguard/docker-compose.yml https://github.com/nationpwned/vps/raw/refs/heads/pasarguard/docker-compose.yml

# Download nginx.conf
wget -O /opt/pasarguard/nginx.conf https://github.com/nationpwned/vps/raw/refs/heads/pasarguard/nginx.conf

# Replace placeholders in nginx.conf with user input
sed -i "s/server_name \$DOMAIN;/server_name $DOMAIN;/" /opt/pasarguard/nginx.conf

# Download xray_config.json
wget -O /var/lib/pasarguard/xray_config.json https://github.com/nationpwned/vps/raw/refs/heads/pasarguard/xray_config.json

# Download the subscribers pasarguard
mkdir -p /var/lib/pasarguard/templates/subscription/
wget -N -P /var/lib/pasarguard/templates/subscription/ https://github.com/nationpwned/vps/raw/refs/heads/pasarguard/index.html

# pasarguard up
docker compose -f /opt/pasarguard/docker-compose.yml up -d

echo "pasarguard installation and configuration completed successfully!"
echo "You can access pasarguard at https://$DOMAIN"
echo "Make sure to configure your Xray clients with the provided Reality keys and UUID."
echo "==============================================="

read -p "Do you want to reboot now? [Y/n]: " answer
answer=${answer:-Y}
if [[ "$answer" =~ ^[Yy]$ ]]; then
  echo "Rebooting system..."
  reboot
else
  echo "Reboot cancelled. Please reboot manually if needed."
fi
