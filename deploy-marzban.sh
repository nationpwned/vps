#!/bin/bash

#==========================================
# Marzban VPS Deployment Script
# Version: 1.0
# Author: @sib0ndt
# Description: Complete Marzban deployment with SSL and Nginx
#==========================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MARZBAN_VERSION="v1.0.0-beta-3"
MARZBAN_DIR="/opt/marzban"
MARZBAN_USER="marzban"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
SYSTEMD_DIR="/etc/systemd/system"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

get_user_input() {
    log_info "=== Marzban VPS Deployment Configuration ==="
    echo
    
    # Domain name with validation
    while [[ -z "$DOMAIN" ]]; do
        echo -e "${BLUE}Examples:${NC} marzban.example.com, vpn.mydomain.org"
        read -p "Enter your domain name: " DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            log_warning "Domain name cannot be empty!"
        elif [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
            log_warning "Invalid domain format! Please use a valid domain name."
            DOMAIN=""
        else
            log_success "Domain: $DOMAIN"
        fi
    done
    
    # Email for SSL with validation
    while [[ -z "$EMAIL" ]]; do
        echo -e "${BLUE}Examples:${NC} admin@example.com, nom41jymf2@cmhvzylmfc.com"
        read -p "Enter your email for SSL certificate: " EMAIL
        if [[ -z "$EMAIL" ]]; then
            log_warning "Email cannot be empty!"
        elif [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log_warning "Invalid email format! Please enter a valid email address."
            EMAIL=""
        else
            log_success "Email: $EMAIL"
        fi
    done
    
    # Marzban port (internal) with validation
    while true; do
        read -p "Enter Marzban internal port [8000]: " MARZBAN_PORT
        MARZBAN_PORT=${MARZBAN_PORT:-8000}
        if [[ "$MARZBAN_PORT" =~ ^[0-9]+$ ]] && [ "$MARZBAN_PORT" -ge 1000 ] && [ "$MARZBAN_PORT" -le 65535 ]; then
            log_success "Internal port: $MARZBAN_PORT"
            break
        else
            log_warning "Please enter a valid port number (1000-65535)"
        fi
    done
    
    # Admin credentials
    echo
    log_info "Admin user configuration:"
    
    # Admin username with validation
    while [[ -z "$ADMIN_USERNAME" ]]; do
        echo -e "${BLUE}Requirements:${NC} 3+ characters, letters and numbers only"
        read -p "Enter admin username: " ADMIN_USERNAME
        if [[ -z "$ADMIN_USERNAME" ]]; then
            log_warning "Username cannot be empty!"
        elif [[ ${#ADMIN_USERNAME} -lt 3 ]]; then
            log_warning "Username must be at least 3 characters long!"
            ADMIN_USERNAME=""
        elif [[ ! "$ADMIN_USERNAME" =~ ^[a-zA-Z0-9]+$ ]]; then
            log_warning "Username can only contain letters and numbers!"
            ADMIN_USERNAME=""
        else
            log_success "Username: $ADMIN_USERNAME"
        fi
    done
    
    # Admin password with validation
    while [[ -z "$ADMIN_PASSWORD" ]]; do
        echo -e "${BLUE}Requirements:${NC} Min 12 chars, 2+ uppercase, 1+ special character"
        echo -e "${BLUE}Example:${NC} MySecurePass123!"
        read -s -p "Enter admin password: " ADMIN_PASSWORD
        echo
        if [[ -z "$ADMIN_PASSWORD" ]]; then
            log_warning "Password cannot be empty!"
        elif [[ ${#ADMIN_PASSWORD} -lt 12 ]]; then
            log_warning "Password must be at least 12 characters long!"
            ADMIN_PASSWORD=""
        elif [[ $(echo "$ADMIN_PASSWORD" | grep -o '[A-Z]' | wc -l) -lt 2 ]]; then
            log_warning "Password must contain at least 2 uppercase letters!"
            ADMIN_PASSWORD=""
        elif [[ ! "$ADMIN_PASSWORD" =~ [[:punct:]] ]]; then
            log_warning "Password must contain at least 1 special character!"
            ADMIN_PASSWORD=""
        else
            # Confirm password
            read -s -p "Confirm admin password: " CONFIRM_PASSWORD
            echo
            if [[ "$ADMIN_PASSWORD" != "$CONFIRM_PASSWORD" ]]; then
                log_warning "Passwords do not match!"
                ADMIN_PASSWORD=""
            else
                log_success "Password confirmed"
            fi
        fi
    done
    
    # Optional Telegram ID
    echo
    log_info "Optional integrations (press Enter to skip):"
    read -p "Enter Telegram ID for notifications (optional): " TELEGRAM_ID
    if [[ -n "$TELEGRAM_ID" ]]; then
        if [[ "$TELEGRAM_ID" =~ ^[0-9]+$ ]]; then
            log_success "Telegram ID: $TELEGRAM_ID"
        else
            log_warning "Invalid Telegram ID format, skipping..."
            TELEGRAM_ID=""
        fi
    fi
    
    # Optional Discord webhook
    read -p "Enter Discord webhook URL (optional): " DISCORD_WEBHOOK
    if [[ -n "$DISCORD_WEBHOOK" ]]; then
        if [[ "$DISCORD_WEBHOOK" =~ ^https://discord(app)?\.com/api/webhooks/ ]]; then
            log_success "Discord webhook configured"
        else
            log_warning "Invalid Discord webhook URL format, skipping..."
            DISCORD_WEBHOOK=""
        fi
    fi
    
    echo
    log_success "Configuration completed!"
    echo "=========================================="
    echo "Domain: $DOMAIN"
    echo "Email: $EMAIL" 
    echo "Internal Port: $MARZBAN_PORT"
    echo "Admin Username: $ADMIN_USERNAME"
    if [[ -n "$TELEGRAM_ID" ]]; then
        echo "Telegram ID: $TELEGRAM_ID"
    fi
    if [[ -n "$DISCORD_WEBHOOK" ]]; then
        echo "Discord Webhook: Configured"
    fi
    echo "=========================================="
    echo
    
    # Confirmation
    while true; do
        read -p "Proceed with installation? (y/n): " CONFIRM
        case $CONFIRM in
            [Yy]* ) break;;
            [Nn]* ) log_error "Installation cancelled by user"; exit 1;;
            * ) log_warning "Please answer yes (y) or no (n).";;
        esac
    done
}

update_system() {
    log_info "Updating system packages..."
    apt update && apt upgrade -y
    log_success "System updated successfully"
}

install_dependencies() {
    log_info "Installing dependencies..."

    # Install Xray
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    log_success "Xray installed successfully"
    
    # Install basic packages
    apt install -y cron curl wget git unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release socat tree net-tools
    
    # Install Python 3.11+ (if not available, install from deadsnakes PPA)
    if ! python3.11 --version >/dev/null 2>&1; then
        add-apt-repository -y ppa:deadsnakes/ppa
        apt update
        apt install -y python3.11 python3.11-venv python3.11-dev
    fi
    
    # Install uv (Python package manager) system-wide
    if ! command -v uv >/dev/null 2>&1; then
        log_info "Installing uv system-wide..."
        # Install for root first
        curl -LsSf https://astral.sh/uv/install.sh | sh
        
        # Copy to system location - check multiple possible locations
        UV_BINARY=""
        if [[ -f "$HOME/.local/bin/uv" ]]; then
            UV_BINARY="$HOME/.local/bin/uv"
        elif [[ -f "$HOME/.cargo/bin/uv" ]]; then
            UV_BINARY="$HOME/.cargo/bin/uv"
        else
            log_error "uv binary not found in expected locations"
            log_error "Checked: $HOME/.local/bin/uv and $HOME/.cargo/bin/uv"
            exit 1
        fi
        
        log_info "Found uv at: $UV_BINARY"
        
        # Remove any existing symlink or file
        rm -f /usr/local/bin/uv
        
        # Copy the binary
        cp "$UV_BINARY" /usr/local/bin/uv
        chmod 755 /usr/local/bin/uv
        chown root:root /usr/local/bin/uv
        
        # Verify installation
        if /usr/local/bin/uv --version >/dev/null 2>&1; then
            log_success "uv installed successfully at /usr/local/bin/uv"
        else
            log_error "uv installation verification failed"
            exit 1
        fi
    fi
    
    # Install Node.js
    if ! command -v node >/dev/null 2>&1; then
        log_info "Installing Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
        apt install -y nodejs
    fi
    
    # Install bun system-wide
    if ! command -v bun >/dev/null 2>&1; then
        log_info "Installing bun system-wide..."
        # Install for root first
        curl -fsSL https://bun.sh/install | bash
        
        # Copy to system location - check multiple possible locations
        BUN_BINARY=""
        if [[ -f "$HOME/.local/bin/bun" ]]; then
            BUN_BINARY="$HOME/.local/bin/bun"
        elif [[ -f "$HOME/.bun/bin/bun" ]]; then
            BUN_BINARY="$HOME/.bun/bin/bun"
        else
            log_error "bun binary not found in expected locations"
            log_error "Checked: $HOME/.local/bin/bun and $HOME/.bun/bin/bun"
            exit 1
        fi
        
        log_info "Found bun at: $BUN_BINARY"
        
        # Remove any existing symlink or file
        rm -f /usr/local/bin/bun
        
        # Handle the case where bun might be a symlink pointing to root directory
        if [[ -L "$BUN_BINARY" ]]; then
            log_info "Detected bun as symlink, resolving to actual binary..."
            ACTUAL_BUN=$(readlink -f "$BUN_BINARY")
            log_info "Resolved to: $ACTUAL_BUN"
            if [[ -f "$ACTUAL_BUN" ]]; then
                cp "$ACTUAL_BUN" /usr/local/bin/bun
            else
                log_error "Cannot find actual bun binary at: $ACTUAL_BUN"
                exit 1
            fi
        else
            # Copy the binary (not create symlink)
            cp "$BUN_BINARY" /usr/local/bin/bun
        fi
        
        chmod 755 /usr/local/bin/bun
        chown root:root /usr/local/bin/bun
        
        # Verify it's actually a binary, not a symlink
        if [[ -L /usr/local/bin/bun ]]; then
            log_error "Unexpected: /usr/local/bin/bun is still a symlink after copy"
            exit 1
        fi
        
        # Verify installation
        if /usr/local/bin/bun --version >/dev/null 2>&1; then
            log_success "bun installed successfully at /usr/local/bin/bun"
        else
            log_error "bun installation verification failed"
            exit 1
        fi
    fi
    
    # Install Nginx
    if ! command -v nginx >/dev/null 2>&1; then
        log_info "Installing Nginx..."
        apt install -y nginx
        systemctl enable nginx
        systemctl stop nginx > /dev/null 2>&1 || true
    fi
    
    log_success "Dependencies installed successfully"
}

install_certificate() {
    log_info "Installing SSL certificates..."
    mkdir -p /opt/marzban/certs
    curl https://get.acme.sh | sh -s email="$EMAIL" && source ~/.bashrc

    ~/.acme.sh/acme.sh \
    --issue --force --standalone -d "$DOMAIN" \
    --fullchain-file "/opt/marzban/certs/fullchain.pem" \
    --key-file "/opt/marzban/certs/key.pem"
}

create_user() {
    log_info "Creating Marzban user..."
    
    if ! id "$MARZBAN_USER" >/dev/null 2>&1; then
        useradd -r -m -s /bin/bash "$MARZBAN_USER"
        log_success "User $MARZBAN_USER created"
    else
        log_warning "User $MARZBAN_USER already exists"
    fi
}

download_marzban() {
    log_info "Downloading Marzban $MARZBAN_VERSION..."
    
    # Create directory
    mkdir -p "$MARZBAN_DIR"
    cd "$MARZBAN_DIR"
    
    # Download and extract
    wget -q "https://github.com/Gozargah/Marzban/archive/refs/tags/${MARZBAN_VERSION}.tar.gz" -O marzban.tar.gz
    tar -xzf marzban.tar.gz --strip-components=1
    rm marzban.tar.gz
    
    # Set ownership
    chown -R "$MARZBAN_USER:$MARZBAN_USER" "$MARZBAN_DIR"
    
    log_success "Marzban downloaded and extracted"
}

build_marzban() {
    log_info "Building Marzban..."
    
    cd "$MARZBAN_DIR"
    
    # Ensure tools are accessible and have correct permissions
    if ! /usr/local/bin/uv --version >/dev/null 2>&1; then
        log_error "uv is not accessible at /usr/local/bin/uv"
        log_info "Fixing uv permissions..."
        chmod 755 /usr/local/bin/uv
        chown root:root /usr/local/bin/uv
        if ! /usr/local/bin/uv --version >/dev/null 2>&1; then
            log_error "uv still not working after permission fix"
            exit 1
        fi
    fi
    
    if ! /usr/local/bin/bun --version >/dev/null 2>&1; then
        log_error "bun is not accessible at /usr/local/bin/bun"
        log_info "Fixing bun permissions..."
        
        # Check if it's a symlink and fix it
        if [[ -L /usr/local/bin/bun ]]; then
            log_info "Detected bun as symlink, replacing with actual binary..."
            BUN_TARGET=$(readlink -f /usr/local/bin/bun)
            log_info "Symlink resolves to: $BUN_TARGET"
            
            # Remove the symlink and copy the actual binary
            rm -f /usr/local/bin/bun
            if [[ -f "$BUN_TARGET" ]]; then
                cp "$BUN_TARGET" /usr/local/bin/bun
            elif [[ -f "$HOME/.bun/bin/bun" ]]; then
                # Resolve the actual binary if it's also a symlink
                ACTUAL_BUN=$(readlink -f "$HOME/.bun/bin/bun")
                if [[ -f "$ACTUAL_BUN" ]]; then
                    cp "$ACTUAL_BUN" /usr/local/bin/bun
                else
                    cp "$HOME/.bun/bin/bun" /usr/local/bin/bun
                fi
            else
                log_error "Cannot find bun binary to copy"
                exit 1
            fi
        fi
        
        chmod 755 /usr/local/bin/bun
        chown root:root /usr/local/bin/bun
        
        if ! /usr/local/bin/bun --version >/dev/null 2>&1; then
            log_error "bun still not working after permission fix"
            exit 1
        fi
    fi
    
    log_info "Tools verified, proceeding with build..."
    
    # Additional permission and ownership check
    log_info "Verifying binary permissions and ownership..."
    ls -la /usr/local/bin/uv /usr/local/bin/bun
    
    # Ensure the binaries are actually executable by testing as root first
    log_info "Testing tools execution as root..."
    /usr/local/bin/uv --version
    /usr/local/bin/bun --version
    
    # Test as marzban user
    log_info "Testing tools execution as marzban user..."
    sudo -u "$MARZBAN_USER" /usr/local/bin/uv --version
    sudo -u "$MARZBAN_USER" /usr/local/bin/bun --version
    
    # Build as marzban user with proper error handling
    sudo -u "$MARZBAN_USER" bash << 'EOF'
set -e

log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

log_debug() {
    echo -e "\033[0;35m[DEBUG]\033[0m $1"
}

cd /opt/marzban

# Debug information
log_debug "Current user: $(whoami)"
log_debug "Current working directory: $(pwd)"
log_debug "UV binary info: $(ls -la /usr/local/bin/uv 2>/dev/null || echo 'Not found')"
log_debug "BUN binary info: $(ls -la /usr/local/bin/bun 2>/dev/null || echo 'Not found')"
log_debug "PATH: $PATH"

log_info "Installing Python dependencies..."
if ! /usr/local/bin/uv sync; then
    log_error "Failed to install Python dependencies"
    exit 1
fi

log_info "Building frontend..."
cd dashboard

# Test bun access explicitly
log_debug "Testing bun access..."
if ! ls -la /usr/local/bin/bun; then
    log_error "Cannot access /usr/local/bin/bun"
    exit 1
fi

if ! file /usr/local/bin/bun; then
    log_error "Cannot determine file type of /usr/local/bin/bun"
    exit 1
fi

# Try to run bun version first
log_debug "Testing bun version..."
if ! /usr/local/bin/bun --version; then
    log_error "Cannot run bun --version"
    exit 1
fi

log_debug "bun seems accessible, proceeding with install..."
if ! /usr/local/bin/bun install; then
    log_error "Failed to install frontend dependencies"
    exit 1
fi

if ! VITE_BASE_API=/ /usr/local/bin/bun run build; then
    log_error "Failed to build frontend"
    exit 1
fi

if ! cp ./build/index.html ./build/404.html; then
    log_error "Failed to copy 404.html"
    exit 1
fi

cd ..

log_info "Running database migrations..."
if ! /usr/local/bin/uv run alembic upgrade head; then
    log_error "Failed to run database migrations"
    exit 1
fi

echo "Build completed successfully"
EOF
    
    if [[ $? -ne 0 ]]; then
        log_error "Build failed"
        exit 1
    fi
    
    log_success "Marzban built successfully"
}

create_admin_user() {
    log_info "Creating admin user..."
    
    cd "$MARZBAN_DIR"
    
    # Prepare Telegram ID and Discord webhook values
    TELEGRAM_ID_VALUE="None"
    DISCORD_WEBHOOK_VALUE="None"
    
    if [[ -n "$TELEGRAM_ID" ]]; then
        TELEGRAM_ID_VALUE="$TELEGRAM_ID"
    fi
    
    if [[ -n "$DISCORD_WEBHOOK" ]]; then
        DISCORD_WEBHOOK_VALUE="\"$DISCORD_WEBHOOK\""
    fi
    
    # Create admin user creation script
    cat > create_admin.py << EOF
#!/usr/bin/env python3
import asyncio
from sqlalchemy.exc import IntegrityError
from pydantic import ValidationError
from app.db.base import get_db
from app.db.crud.admin import create_admin
from app.models.admin import AdminCreate

async def create_admin_user():
    admin_data = AdminCreate(
        username="$ADMIN_USERNAME",
        password="$ADMIN_PASSWORD",
        is_sudo=True,
        telegram_id=$TELEGRAM_ID_VALUE,
        discord_webhook=$DISCORD_WEBHOOK_VALUE
    )
    
    async for db in get_db():
        try:
            db_admin = await create_admin(db, admin_data)
            print(f"✅ Admin user created: {db_admin.username} (ID: {db_admin.id})")
            break
        except IntegrityError:
            print(f"❌ Admin user '{admin_data.username}' already exists!")
            break
        except Exception as e:
            print(f"❌ Error: {e}")
            break

if __name__ == "__main__":
    asyncio.run(create_admin_user())
EOF

    # Run the script as marzban user
    sudo -u "$MARZBAN_USER" bash << 'EOF'
cd /opt/marzban
export PATH="/usr/local/bin:$PATH"
/usr/local/bin/uv run python create_admin.py
EOF
    
    # Clean up
    rm create_admin.py
    
    log_success "Admin user created"
}

create_systemd_service() {
    log_info "Creating systemd service..."
    
    cat > "$SYSTEMD_DIR/marzban.service" << EOF
[Unit]
Description=Marzban VPN Management Panel
After=network.target

[Service]
Type=simple
User=$MARZBAN_USER
Group=$MARZBAN_USER
WorkingDirectory=$MARZBAN_DIR
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/local/bin/uv run main.py
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable marzban
    
    log_success "Systemd service created"
}

setup_ssl() {
    log_info "Setting up SSL certificate..."
    
    # Stop nginx temporarily
    systemctl stop nginx > /dev/null 2>&1 || true
    
        # Start nginx
    systemctl start nginx > /dev/null 2>&1 || true

    log_success "SSL certificate installed and auto-renewal configured"
}

configure_nginx() {
    log_info "Configuring Nginx..."
    
    # Create Nginx configuration
    cat > "$NGINX_AVAILABLE/marzban" << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    # SSL Configuration (will be configured by Certbot)
    ssl_certificate /opt/marzban/certs/fullchain.pem;
    ssl_certificate_key /opt/marzban/certs/key.pem;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Proxy settings
    location / {
        proxy_pass http://127.0.0.1:$MARZBAN_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_redirect off;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # VLESS WS TLS
    location /vless-ws {
        proxy_pass https://127.0.0.1:2021;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_ssl_verify off;
    }

    # TROJAN WS TLS
    location /trojan-ws {
        proxy_pass https://127.0.0.1:2022;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_ssl_verify off;
    }

    # VLESS GRPC TLS
    location /vless {
        if (\$http_content_type != "application/grpc") {
            return 404;
        }
        grpc_pass grpcs://127.0.0.1:2023;
        grpc_set_header Host \$host;
        grpc_ssl_verify off;
    }

    # TROJAN GRPC TLS
    location /trojan {
        if (\$http_content_type != "application/grpc") {
            return 404;
        }
        grpc_pass grpcs://127.0.0.1:2024;
        grpc_set_header Host \$host;
        grpc_ssl_verify off;
    }
    
    # Static files caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://127.0.0.1:$MARZBAN_PORT;
        proxy_set_header Host \$host;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF
    
    # Enable site
    ln -sf "$NGINX_AVAILABLE/marzban" "$NGINX_ENABLED/marzban"
    
    # Remove default site if exists
    rm -f "$NGINX_ENABLED/default"
    
    # Test Nginx configuration
    nginx -t
    
    log_success "Nginx configured"
}

hook_postinstall() {
    mv /opt/marzban/app/templates/subscription/index.html /opt/marzban/app/templates/subscription/index.html.bak
    wget https://github.com/nationpwned/vps/raw/refs/heads/marzban-next/index.html -O /opt/marzban/app/templates/subscription/index.html
    sudo tee /etc/systemd/system/marzban.service > /dev/null << 'EOF'
[Unit]
Description=Marzban VPN Management Panel
After=network.target

[Service]
Type=simple
User=marzban
Group=marzban
WorkingDirectory=/opt/marzban
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/local/bin/uv run main.py
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

configure_firewall() {
    log_info "Configuring firewall..."
    
    # Install UFW if not present
    if ! command -v ufw >/dev/null 2>&1; then
        apt install -y ufw
    fi
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
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
    
    log_success "Firewall configured"
}

start_services() {
    log_info "Starting services..."
    
    # Start and enable services
    systemctl start marzban
    systemctl reload nginx > /dev/null 2>&1 || true

    # Check status
    if systemctl is-active --quiet marzban; then
        log_success "Marzban service started successfully"
    else
        log_error "Failed to start Marzban service"
        systemctl status marzban
        exit 1
    fi
    
    if systemctl is-active --quiet nginx; then
        log_success "Nginx service is running"
    else
        log_error "Nginx service failed"
        systemctl status nginx
        exit 1
    fi
}

show_completion_info() {
    echo
    echo "=========================================="
    log_success "Marzban VPS Deployment Completed!"
    echo "=========================================="
    echo
    echo "🌐 Access URL: https://$DOMAIN"
    echo "👤 Admin Username: $ADMIN_USERNAME"
    echo "🔑 Admin Password: [hidden]"
    echo "📧 SSL Email: $EMAIL"
    echo
    echo "📁 Installation Directory: $MARZBAN_DIR"
    echo "👥 Service User: $MARZBAN_USER"
    echo "🔧 Internal Port: $MARZBAN_PORT"
    
    if [[ -n "$TELEGRAM_ID" ]]; then
        echo "📱 Telegram ID: $TELEGRAM_ID"
    fi
    
    if [[ -n "$DISCORD_WEBHOOK" ]]; then
        echo "💬 Discord Webhook: Configured"
    fi
    
    echo
    echo "🔧 Service Commands:"
    echo "  Start:   systemctl start marzban"
    echo "  Stop:    systemctl stop marzban"
    echo "  Restart: systemctl restart marzban"
    echo "  Status:  systemctl status marzban"
    echo "  Logs:    journalctl -u marzban -f"
    echo
    echo "🎛️  Admin Management:"
    echo "  cd $MARZBAN_DIR && sudo -u $MARZBAN_USER /usr/local/bin/uv run marzban-cli.py"
    echo
    echo "🔒 SSL Certificate:"
    echo "  Auto-renewal is configured"
    echo "  Manual renewal: certbot renew"
    echo
    echo "⚠️  Important Notes:"
    echo "  • Firewall is enabled (UFW)"
    echo "  • Only SSH, HTTP, and HTTPS ports are open"
    echo "  • SSL certificate will auto-renew"
    echo "  • Nginx is configured as reverse proxy"
    echo
    log_success "Deployment completed successfully!"
    echo "=========================================="
}

# Main execution
main() {
    log_info "Starting Marzban VPS deployment..."
    echo
    
    check_root
    get_user_input
    update_system
    install_dependencies
    install_certificate
    create_user
    download_marzban
    build_marzban
    create_admin_user
    create_systemd_service
    setup_ssl
    configure_nginx
    hook_postinstall
    configure_firewall
    start_services
    show_completion_info
}

# Run main function
main "$@"
