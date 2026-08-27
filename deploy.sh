#!/usr/bin/env bash
set -e

# ==============================================================================
# Auto Deploy Script for Cloudflare Worker: edgetunnel
# ==============================================================================

WORKER_NAME="edgetunnel"
KV_TITLE="kv"
MAIN_FILE="_worker.js"
WRANGLER_CONFIG="wrangler.toml"
EDGETUNNEL_SOURCE_URL="https://raw.githubusercontent.com/cmliu/edgetunnel/main/_worker.js"

echo "=========================================="
echo "🚀 Starting edgetunnel Auto Setup & Deploy"
echo "=========================================="

# 1. Periksa ketersediaan Node.js & npm
echo "[1/6] Checking Node.js & npm..."
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "❌ Node.js atau npm belum terinstall. Silakan install Node.js terlebih dahulu."
    exit 1
fi
echo "✅ Node.js $(node -v) & npm $(npm -v) detected."

# 2. Periksa / Pasang Wrangler
echo "[2/6] Checking Wrangler CLI..."
if ! npx wrangler --version >/dev/null 2>&1; then
    echo "Installing wrangler locally..."
    npm install -D wrangler
fi
echo "✅ Wrangler version: $(npx wrangler --version)"

# 3. Validasi Login Cloudflare
echo "[3/6] Checking Cloudflare Authentication..."
if ! npx wrangler whoami >/dev/null 2>&1; then
    echo "⚠️ Anda belum login ke Cloudflare."
    echo "Membuka proses login..."
    npx wrangler login
fi
echo "✅ Cloudflare Authenticated."

# 4. Download source code _worker.js terbaru
echo "[4/6] Downloading latest _worker.js from repository..."
curl -sSL "$EDGETUNNEL_SOURCE_URL" -o "$MAIN_FILE"
if [ ! -s "$MAIN_FILE" ]; then
    echo "❌ Gagal mengunduh _worker.js."
    exit 1
fi
echo "✅ _worker.js downloaded successfully."

# 5. Konfigurasi KV Namespace & Password Admin
echo "[5/6] Setting up KV Namespace & wrangler.toml..."

# Baca password admin dari user atau gunakan default/input
read -r -p "Masukkan Password ADMIN untuk Dashboard [default: admin123]: " INPUT_ADMIN
ADMIN_PASSWORD=${INPUT_ADMIN:-admin123}

# Periksa apakah KV Namespace sudah ada
KV_LIST_JSON=$(npx wrangler kv namespace list 2>/dev/null || echo "[]")
KV_ID=$(echo "$KV_LIST_JSON" | grep -o '{"id":"[^"]*","supports_url_encoding":[^,]*,"title":"'"$KV_TITLE"'"}' | sed -E 's/.*"id":"([^"]+)".*/\1/' || true)

# Jika belum ada ID, buat KV namespace baru
if [ -z "$KV_ID" ]; then
    # Alternatif parsing sederhana jika format list berbeda
    KV_ID=$(echo "$KV_LIST_JSON" | grep -B 1 "\"title\": \"$KV_TITLE\"" | grep "\"id\":" | head -n 1 | awk -F '"' '{print $4}' || true)
fi

if [ -z "$KV_ID" ]; then
    echo "Membuat KV namespace baru: '$KV_TITLE'..."
    CREATE_OUTPUT=$(npx wrangler kv namespace create "$KV_TITLE" 2>&1)
    KV_ID=$(echo "$CREATE_OUTPUT" | grep -o 'id = "[^"]*"' | head -n 1 | cut -d '"' -f 2 || true)
fi

if [ -z "$KV_ID" ]; then
    echo "⚠️ Gagal mendapatkan KV ID otomatis, silakan buat manual atau cek dashboard Cloudflare."
    read -r -p "Masukkan KV Namespace ID Anda secara manual: " KV_ID
fi

echo "✅ Using KV Namespace ID: $KV_ID"

# Generate wrangler.toml
cat <<EOF > "$WRANGLER_CONFIG"
name = "$WORKER_NAME"
main = "$MAIN_FILE"
compatibility_date = "2024-08-01"
compatibility_flags = ["nodejs_compat"]

[vars]
ADMIN = "$ADMIN_PASSWORD"

[[kv_namespaces]]
binding = "KV"
id = "$KV_ID"
EOF

echo "✅ $WRANGLER_CONFIG generated successfully."

# 6. Deploy ke Cloudflare Workers
echo "[6/6] Deploying Worker to Cloudflare..."
npx wrangler deploy

echo "=========================================="
echo "🎉 DEPLOYMENT SUKSES!"
echo "=========================================="
echo "Password Admin Anda : $ADMIN_PASSWORD"
echo ""
echo "📌 Akses Dashboard Admin:"
echo "   https://$WORKER_NAME.<subdomain-workers>.workers.dev/admin"
echo ""
echo "⚠️ PENTING AGAR PROXY/TUNNEL BERJALAN:"
echo "   Tambahkan Custom Domain di Cloudflare Dashboard:"
echo "   Worker Settings -> Domains & Routes -> Add Custom Domain (contoh: vpn.domainanda.com)"
echo "   Akses via: https://vpn.domainanda.com/admin"
echo "=========================================="
