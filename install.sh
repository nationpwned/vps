#!/bin/bash

# Marzban VPS Deployment - Smart Installer
# This script automatically uses local deploy-marzban.sh if available,
# otherwise downloads it from the internet

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

show_banner() {
    clear
    echo -e "${GREEN}"
    cat << "EOF"
 ███╗   ███╗ █████╗ ██████╗ ███████╗██████╗  █████╗ ███╗   ██╗
 ████╗ ████║██╔══██╗██╔══██╗╚══███╔╝██╔══██╗██╔══██╗████╗  ██║
 ██╔████╔██║███████║██████╔╝  ███╔╝ ██████╔╝███████║██╔██╗ ██║
 ██║╚██╔╝██║██╔══██║██╔══██╗ ███╔╝  ██╔══██╗██╔══██║██║╚██╗██║
 ██║ ╚═╝ ██║██║  ██║██║  ██║███████╗██████╔╝██║  ██║██║ ╚████║
 ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝
                                                                
EOF
    echo -e "${NC}"
    echo -e "${BLUE}🚀 VPS Deployment Installer${NC}"
    echo "==============================================="
    echo
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

# Function to detect and validate OS
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS version"
        exit 1
    fi
    
    . /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]] && [[ "$ID" != "debian" ]]; then
        log_error "This script only supports Ubuntu and Debian"
        exit 1
    fi
    
    log_success "OS check passed: $PRETTY_NAME"
}

# Function to install basic requirements
install_requirements() {
    log_info "Installing basic requirements..."
    
    apt-get update >/dev/null 2>&1
    apt-get install -y curl wget unzip bc >/dev/null 2>&1
    
    log_success "Basic requirements installed"
}

# Function to download deployment script from internet
download_deployment_script() {
    log_info "Downloading Marzban deployment script from internet..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Try different download methods
    SCRIPT_URL="https://github.com/nationpwned/mz/raw/refs/heads/next/deploy-marzban.sh"
    
    if command -v wget >/dev/null 2>&1; then
        if ! wget -q -O deploy-marzban.sh "$SCRIPT_URL"; then
            log_error "Failed to download deployment script with wget"
            return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL -o deploy-marzban.sh "$SCRIPT_URL"; then
            log_error "Failed to download deployment script with curl"
            return 1
        fi
    else
        log_error "Neither wget nor curl is available"
        return 1
    fi
    
    chmod +x deploy-marzban.sh
    log_success "Deployment script downloaded"
    return 0
}

# Main function
main() {
    show_banner
    check_root
    check_os
    install_requirements
    
    log_info "Starting Marzban VPS deployment..."
    echo
    
    # Check if local deployment script exists
    if [[ -f "./deploy-marzban.sh" ]]; then
        log_info "Found local deployment script, using it..."
        chmod +x ./deploy-marzban.sh
        ./deploy-marzban.sh
    else
        log_info "Local deployment script not found, downloading from internet..."
        
        if download_deployment_script; then
            cd "$TEMP_DIR"
            ./deploy-marzban.sh
            
            # Cleanup
            cd /
            rm -rf "$TEMP_DIR"
        else
            log_error "Failed to download deployment script"
            log_info "Please ensure you have internet connection and try again"
            log_info "Or place deploy-marzban.sh in the same directory as this script"
            exit 1
        fi
    fi
    
    log_success "Installation completed!"
}

# Run main function
main "$@"
