#!/bin/bash

echo "========================"
echo "   VLESS Reality Xray   "
echo "========================"

# Prompt user for Domain or IP
read -p "Enter your Domain or VPS IP : " DOMAIN

# Validation: Ensure input is not empty
if [ -z "$DOMAIN" ]; then
    echo "ERROR: Domain/IP cannot be empty! Aborted."
    exit 1
fi

echo "-> Stopping Xray service..."
systemctl stop xray

echo "-> Generating New X25519 Keys..."
# Save output to temporary files to ensure accuracy
/usr/local/bin/xray uuid > /tmp/xray_uuid.txt 2>&1
/usr/local/bin/xray x25519 > /tmp/xray_keys.txt 2>&1

# Extract and remove all spaces/newlines/carriage returns
UUID=$(cat /tmp/xray_uuid.txt | tr -d ' ' | tr -d '\r' | tr -d '\n')
PRIV_KEY=$(grep -i "Private" /tmp/xray_keys.txt | awk -F ':' '{print $2}' | tr -d ' ' | tr -d '\r')
PUB_KEY=$(grep -i "Public" /tmp/xray_keys.txt | awk -F ':' '{print $2}' | tr -d ' ' | tr -d '\r')
SHORT_ID=$(openssl rand -hex 8)

# Strict validation
if [ -z "$PRIV_KEY" ] || [ -z "$PUB_KEY" ]; then
    echo "==================================================="
    echo "CRITICAL ERROR: Xray failed to generate keys!"
    echo "Here is the raw log showing the exact cause:"
    cat /tmp/xray_keys.txt
    echo "==================================================="
    exit 1
fi

echo "-> Inserting Private Key into config.json..."
cat <<EOF > /usr/local/etc/xray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.apple.com:443",
          "xver": 0,
          "serverNames": [
            "www.apple.com"
          ],
          "privateKey": "$PRIV_KEY",
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

echo "-> Restarting Xray Server..."
systemctl start xray
systemctl enable xray &> /dev/null

echo ""
echo "==============================================="
echo "        XRAY SERVER IS BACK TO NORMAL!         "
echo "==============================================="
echo " Xray Status :" $(systemctl is-active xray)
echo "==============================================="
echo " Copy the text below into your Mihomo app:"
echo "==============================================="
cat <<EOF
proxies:
  - name: VLESS-Reality-Auto
    type: vless
    server: $DOMAIN
    port: 443
    uuid: $UUID
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: www.apple.com
    client-fingerprint: chrome
    reality-opts:
      public-key: "$PUB_KEY"
      short-id: "$SHORT_ID"
EOF
echo "==============================================="

rm -f /tmp/xray_keys.txt /tmp/xray_uuid.txt
