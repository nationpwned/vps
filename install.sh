#!/bin/bash

set -e

# ── Install remnawave CLI ─────────────────────────────────────
bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/remnawave.sh) @ install-script

# ── Full interactive install (one set of prompts, handles Caddy) ──
remnawave install

# ── Patch Caddy for gRPC support ─────────────────────────────
CADDY_DIR="/opt/caddy-remnawave"
CADDY_ENV="$CADDY_DIR/.env"
CADDYFILE="$CADDY_DIR/Caddyfile"

if [ ! -f "$CADDY_ENV" ]; then
    echo ""
    echo "⚠️  Caddy was not installed during setup."
    echo "   You can install it later with: remnawave caddy install"
    echo "   After installing Caddy, re-run this script to apply the gRPC patch."
    exit 0
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo " Patching Caddyfile for Trojan gRPC / VLESS gRPC support"
echo "═══════════════════════════════════════════════════════"

# Back up original Caddyfile
cp "$CADDYFILE" "${CADDYFILE}.bak.$(date +%Y%m%d_%H%M%S)"

cat > "$CADDYFILE" << 'EOF'
# Remnawave — full proxy routing
# Trojan WS | Trojan gRPC | Trojan HTTPUpgrade
# VLESS  WS | VLESS  gRPC | VLESS  HTTPUpgrade | VLESS XHTTP
# TLS terminated by Caddy; xray inbounds use security:none

{
    servers {
        protocols h1 h2 h3
    }
}

# ── Panel + proxy domain ──────────────────────────────────────
https://{$PANEL_DOMAIN} {
    encode zstd gzip

    # ── Trojan gRPC  (serviceName: TrGRPC) ──────────────────
    @trojan-grpc {
        protocol grpc
        path /TrGRPC/*
    }
    handle @trojan-grpc {
        reverse_proxy host.docker.internal:10003 {
            transport http {
                versions h2c 2
            }
            flush_interval -1
        }
    }

    # ── VLESS gRPC  (serviceName: VlGRPC) ───────────────────
    @vless-grpc {
        protocol grpc
        path /VlGRPC/*
    }
    handle @vless-grpc {
        reverse_proxy host.docker.internal:10004 {
            transport http {
                versions h2c 2
            }
            flush_interval -1
        }
    }

    # ── Trojan WebSocket  (path: /trws) ──────────────────────
    @trojan-ws {
        path /trws
        header Connection *Upgrade*
        header Upgrade websocket
    }
    handle @trojan-ws {
        reverse_proxy host.docker.internal:10001 {
            header_up X-Real-IP         {remote_host}
            header_up X-Forwarded-For   {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up Host              {host}
        }
    }

    # ── VLESS WebSocket  (path: /vlws) ───────────────────────
    @vless-ws {
        path /vlws
        header Connection *Upgrade*
        header Upgrade websocket
    }
    handle @vless-ws {
        reverse_proxy host.docker.internal:10002 {
            header_up X-Real-IP         {remote_host}
            header_up X-Forwarded-For   {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up Host              {host}
        }
    }

    # ── Trojan HTTPUpgrade  (path: /trhup) ───────────────────
    @trojan-httpupgrade {
        path /trhup
    }
    handle @trojan-httpupgrade {
        reverse_proxy host.docker.internal:10005 {
            header_up X-Real-IP         {remote_host}
            header_up X-Forwarded-For   {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up Host              {host}
            header_up Connection        {>Connection}
            header_up Upgrade           {>Upgrade}
        }
    }

    # ── VLESS HTTPUpgrade  (path: /vlhup) ────────────────────
    @vless-httpupgrade {
        path /vlhup
    }
    handle @vless-httpupgrade {
        reverse_proxy host.docker.internal:10006 {
            header_up X-Real-IP         {remote_host}
            header_up X-Forwarded-For   {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up Host              {host}
            header_up Connection        {>Connection}
            header_up Upgrade           {>Upgrade}
        }
    }

    # ── VLESS XHTTP  (path: /vlxhttp) ────────────────────────
    @vless-xhttp {
        path /vlxhttp*
    }
    handle @vless-xhttp {
        reverse_proxy host.docker.internal:10007 {
            header_up X-Real-IP         {remote_host}
            header_up X-Forwarded-For   {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up Host              {host}
            flush_interval              -1
        }
    }

    # ── Remnawave panel API/UI (everything else) ─────────────
    handle {
        reverse_proxy remnawave:{$PANEL_PORT} {
            header_up X-Real-IP         {remote_host}
            header_up X-Forwarded-For   {remote_host}
            header_up X-Forwarded-Proto {scheme}
            header_up Host              {host}
        }
    }

    log {
        output file /var/log/caddy/panel.log {
            roll_size 30mb
            roll_keep 10
            roll_keep_for 720h
        }
    }
}

# ── Subscription sub-domain ───────────────────────────────────
https://{$SUB_DOMAIN} {
    encode zstd gzip

    reverse_proxy remnawave-subscription-page:{$SUB_PORT} {
        header_up X-Real-IP         {remote_host}
        header_up X-Forwarded-For   {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up Host              {host}
    }

    log {
        output file /var/log/caddy/sub.log {
            roll_size 10mb
            roll_keep 5
        }
    }
}

# Silently reject all other TLS handshakes
:443 {
    tls internal
    respond 204
}
EOF

DC="$CADDY_DIR/docker-compose.yml"
if ! grep -q 'host-gateway' "$DC" 2>/dev/null; then
    echo "Patching Caddy docker-compose.yml for host.docker.internal..."
    sed -i '/networks:/a\    extra_hosts:\n      - "host.docker.internal:host-gateway"' "$DC"
fi

# ── Reload Caddy ──────────────────────────────────────────────
echo "Restarting Caddy to apply new Caddyfile..."
cd "$CADDY_DIR" && docker compose down && docker compose up -d

# ── Read domains for final summary ───────────────────────────
PANEL_DOMAIN=$(grep "^PANEL_DOMAIN=" "$CADDY_ENV" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
SUB_DOMAIN=$(grep   "^SUB_DOMAIN="   "$CADDY_ENV" | cut -d'=' -f2 | tr -d '"' | tr -d "'")

echo ""
# ── Write xray node config ───────────────────────────────────
XRAY_CONFIG="/opt/remnawave/xray-config.json"
cat > "$XRAY_CONFIG" << 'XEOF'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "Trojan-WS",
      "listen": "0.0.0.0",
      "port": 10001,
      "protocol": "trojan",
      "settings": {
        "clients": [],
        "fallbacks": []
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/trws",
          "headers": {}
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "VLESS-WS",
      "listen": "0.0.0.0",
      "port": 10002,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vlws",
          "headers": {}
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "Trojan-gRPC",
      "listen": "0.0.0.0",
      "port": 10003,
      "protocol": "trojan",
      "settings": {
        "clients": [],
        "fallbacks": []
      },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": {
          "serviceName": "TrGRPC",
          "multiMode": false
        }
      },
      "sniffing": {
        "enabled": false
      }
    },
    {
      "tag": "VLESS-gRPC",
      "listen": "0.0.0.0",
      "port": 10004,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": {
          "serviceName": "VlGRPC",
          "multiMode": false
        }
      },
      "sniffing": {
        "enabled": false
      }
    },
    {
      "tag": "Trojan-HTTPUpgrade",
      "listen": "0.0.0.0",
      "port": 10005,
      "protocol": "trojan",
      "settings": {
        "clients": [],
        "fallbacks": []
      },
      "streamSettings": {
        "network": "httpupgrade",
        "security": "none",
        "httpupgradeSettings": {
          "path": "/trhup",
          "host": ""
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "VLESS-HTTPUpgrade",
      "listen": "0.0.0.0",
      "port": 10006,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "httpupgrade",
        "security": "none",
        "httpupgradeSettings": {
          "path": "/vlhup",
          "host": ""
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "VLESS-XHTTP",
      "listen": "0.0.0.0",
      "port": 10007,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "path": "/vlxhttp",
          "mode": "auto"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "DIRECT",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "BLOCK",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "BLOCK"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads-all"],
        "outboundTag": "BLOCK"
      }
    ]
  }
}
XEOF

# ufw rules 
ufw allow 22/tcp
ufw allow 2222/tcp
ufw allow 443/tcp
ufw allow 10001/tcp
ufw allow 10002/tcp
ufw allow 10003/tcp
ufw allow 10004/tcp
ufw allow 10005/tcp
ufw allow 10006/tcp
ufw allow 10007/tcp
echo y | ufw enable
ufw status numbered

echo ""
echo "═══════════════════════════════════════════════════════"
echo " Done! Caddy is running with gRPC + WebSocket support."
echo "  Panel:        https://$PANEL_DOMAIN"
echo "  Subscription: https://$SUB_DOMAIN"
echo ""
echo " Protocols & ports (xray inbounds, internal only):"
echo "  Trojan WS          → port 10001  path /trws"
echo "  VLESS  WS          → port 10002  path /vlws"
echo "  Trojan gRPC        → port 10003  svc  TrGRPC"
echo "  VLESS  gRPC        → port 10004  svc  VlGRPC"
echo "  Trojan HTTPUpgrade → port 10005  path /trhup"
echo "  VLESS  HTTPUpgrade → port 10006  path /vlhup"
echo "  VLESS  XHTTP       → port 10007  path /vlxhttp"
echo ""
echo " Xray config saved to: $XRAY_CONFIG"
echo " → Paste this file content into Remnawave panel:"
echo "   Nodes → [your node] → Xray Config"
echo ""
echo " Useful commands:"
echo "  remnawave status       — panel status"
echo "  remnawave caddy logs   — Caddy logs"
echo "  remnawave restart      — restart panel"
echo "═══════════════════════════════════════════════════════"
