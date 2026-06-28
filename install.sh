#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "[-] Script ini harus dijalankan sebagai root (gunakan sudo)."
  exit 1
fi

ufw allow 22/tcp
ufw allow 22/udp
ufw allow 80/tcp
ufw allow 80/udp
ufw allow 443/tcp
ufw allow 443/udp

echo "[+] 1. Setting Timezone ke Asia/Jakarta..."
timedatectl set-timezone Asia/Jakarta

echo "Memulai konfigurasi ZRAM sebesar 4G..."
modprobe zram num_devices=1
echo "zram" > /etc/modules-load.d/zram.conf

cat <<EOF > /etc/systemd/system/zram.service
[Unit]
Description=Enable ZRAM swap
After=multi-user.target

[Service]
Type=oneshot
# Pastikan modul dimuat
ExecStartPre=/sbin/modprobe zram
# Set algoritma kompresi ke lz4 (sangat cepat), set ukuran 512MB, dan aktifkan swap dengan prioritas tinggi
ExecStart=/bin/bash -c 'echo lz4 > /sys/block/zram0/comp_algorithm; echo 4G > /sys/block/zram0/disksize; mkswap /dev/zram0; swapon -p 100 /dev/zram0'
# Bersihkan saat service dimatikan
ExecStop=/bin/bash -c 'swapoff /dev/zram0; echo 1 > /sys/block/zram0/reset'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zram.service
systemctl start zram.service

echo "========================================="
echo "ZRAM berhasil diinstal dan diaktifkan!"
echo "Status ZRAM saat ini:"
zramctl

echo "[+] 2. Configuring systemd-resolved DNS..."
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/dns-custom.conf <<EOF
[Resolve]
DNS=8.8.8.8 8.8.4.4
FallbackDNS=1.1.1.1 1.0.0.1
EOF
systemctl restart systemd-resolved

echo "[+] 3. Configuring Netplan dynamically..."
DEFAULT_IF=$(ip route show default | awk '/default/ {print $5}')
MAC_ADDR=$(cat "/sys/class/net/$DEFAULT_IF/address")

cat > /etc/netplan/50-cloud-init.yaml <<EOF
network:
  version: 2
  ethernets:
    $DEFAULT_IF:
      match:
        macaddress: "$MAC_ADDR"
      set-name: "$DEFAULT_IF"
      dhcp4: true
      dhcp6: true
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
EOF

netplan generate
netplan apply

sleep 3

echo "[+] 4. Updating packages..."
apt-get update
apt-get install -y curl wget jq openssl gawk

echo "[+] 5. Installing sing-box..."
bash <(curl -fsSL https://sing-box.app/install.sh)

echo "[+] 6. Generating UUID, Keys, and Short ID..."
UUID=$(sing-box generate uuid)

KEYS=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | awk '/PrivateKey/ {print $2}')
PUBLIC_KEY=$(echo "$KEYS" | awk '/PublicKey/ {print $2}')

SHORT_ID=$(openssl rand -hex 8)

IP=$(curl -4s ifconfig.me || curl -4s icanhazip.com)

echo "[+] 7. Configuring sing-box..."
mkdir -p /etc/sing-box

cat >/etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.apple.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.apple.com",
            "server_port": 443
          },
          "private_key": "$PRIVATE_KEY",
          "short_id": [
            "$SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

echo "[+] 8. Starting and enabling sing-box service..."
systemctl enable sing-box
systemctl restart sing-box

echo "[+] 9. Saving credentials..."
cat >"$HOME/cred.txt" <<EOF
IP=$IP
UUID=$UUID
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
GENERATED_AT=$(date -Iseconds)
EOF

echo
echo "========================================"
echo "       SING-BOX VLESS REALITY SETUP     "
echo "========================================"
echo "IP          : $IP"
echo "UUID        : $UUID"
echo "Short ID    : $SHORT_ID"
echo "Private Key : $PRIVATE_KEY"
echo "Public Key  : $PUBLIC_KEY"
echo "========================================"
echo "Credential saved to: $HOME/cred.txt"
echo
echo "========================================"
echo "  CLIENT CONFIG (Clash Meta / Mihomo)   "
echo "========================================"
cat <<EOF
proxies:
  - name: Reality
    type: vless
    server: $IP
    port: 443
    uuid: $UUID
    network: tcp
    udp: true
    tls: true
    servername: www.apple.com
    flow: xtls-rprx-vision
    client-fingerprint: chrome
    reality-opts:
      public-key: $PUBLIC_KEY
      short-id: $SHORT_ID
EOF
echo "========================================"
