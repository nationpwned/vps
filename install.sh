#!/bin/bash

CONFIG_XRAY="/usr/local/etc/xray/config.json"
CONFIG_NGINX="/etc/nginx/sites-available/xray"
NGINX_LINK="/etc/nginx/sites-enabled/xray"
DOMAIN_FILE="/usr/local/etc/xray/domain.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

setup_firewall() {
    echo -e "${YELLOW}Mengonfigurasi Firewall (UFW)...${NC}"
    apt update && apt install -y ufw
    ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp
    echo "y" | ufw enable
}

reinstall_script() {
    clear
    echo -e "${RED}┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e "${RED}│${NC}                ${WHITE}WARNING: REINSTALL SYSTEM${NC}                 ${RED}│${NC}"
    echo -e "${RED}├──────────────────────────────────────────────────────────┤${NC}"
    echo -e "${RED}│${NC} Semua data user, SSL, dan konfigurasi akan DIHAPUS!     ${RED}│${NC}"
    echo -e "${RED}└──────────────────────────────────────────────────────────┘${NC}"
    read -p "  Apakah Anda yakin? (y/n): " confirm
    if [[ $confirm == [yY] ]]; then
        echo -e "${YELLOW}Membersihkan sistem...${NC}"
        systemctl stop xray nginx 2>/dev/null
        rm -rf /usr/local/etc/xray/
        rm -f $CONFIG_NGINX $NGINX_LINK
        echo -e "${GREEN}Pembersihan selesai. Memulai instalasi ulang...${NC}"
        sleep 2
        install_all
    else
        main_menu
    fi
}

install_all() {
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}                ${WHITE}INITIAL INSTALLATION${NC}                  ${CYAN}│${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────────────┘${NC}"
    
    read -p "  Masukkan Domain Anda : " DOMAIN
    read -p "  Masukkan Email SSL   : " EMAIL
    if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then echo -e "${RED}Error: Data tidak lengkap!${NC}"; exit 1; fi
    
    setup_firewall
    systemctl stop apache2 2>/dev/null && apt remove -y apache2 2>/dev/null

    echo -e "\n${YELLOW}Installing Xray-core & Nginx...${NC}"
    apt update && apt install -y nginx jq curl socat certbot python3-certbot-nginx
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

    mkdir -p /usr/local/etc/xray/

    cat <<EOF > $CONFIG_NGINX
server { listen 80; server_name $DOMAIN; root /var/www/html; }
EOF
    ln -sf $CONFIG_NGINX $NGINX_LINK
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null
    systemctl restart nginx

    echo -e "${YELLOW}Mengurus Sertifikat SSL...${NC}"
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

    cat <<EOF > $CONFIG_NGINX
server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location /vless-ws { proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; }
    location /trojan-ws { proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; }
    location /vless-grpc { if (\$request_method != "POST") { return 404; } client_max_body_size 0; grpc_pass grpc://127.0.0.1:10003; }
    location /trojan-grpc { if (\$request_method != "POST") { return 404; } client_max_body_size 0; grpc_pass grpc://127.0.0.1:10004; }
    location /vless-upgrade { proxy_pass http://127.0.0.1:10005; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; }
    location /trojan-upgrade { proxy_pass http://127.0.0.1:10006; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; }
    location /xhttp { proxy_pass http://127.0.0.1:10007; proxy_http_version 1.1; proxy_set_header Host \$host; }
}
EOF

NEW_UUID=$(cat /proc/sys/kernel/random/uuid)
NEW_PASS=$(openssl rand -hex 6)

sudo cat <<EOF > /usr/local/etc/xray/config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    { "port": 10001, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [{"id": "$NEW_UUID", "email": "admin"}], "decryption": "none" }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vless-ws" } } },
    { "port": 10002, "listen": "127.0.0.1", "protocol": "trojan", "settings": { "clients": [{"password": "$NEW_PASS", "email": "admin"}] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/trojan-ws" } } },
    { "port": 10003, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [{"id": "$NEW_UUID", "email": "admin"}], "decryption": "none" }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "vless-grpc" } } },
    { "port": 10004, "listen": "127.0.0.1", "protocol": "trojan", "settings": { "clients": [{"password": "$NEW_PASS", "email": "admin"}] }, "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "trojan-grpc" } } },
    { "port": 10005, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [{"id": "$NEW_UUID", "email": "admin"}], "decryption": "none" }, "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/vless-upgrade" } } },
    { "port": 10006, "listen": "127.0.0.1", "protocol": "trojan", "settings": { "clients": [{"password": "$NEW_PASS", "email": "admin"}] }, "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/trojan-upgrade" } } },
    { "port": 10007, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [{"id": "$NEW_UUID", "email": "admin"}], "decryption": "none" }, "streamSettings": { "network": "xhttp", "xhttpSettings": { "path": "/xhttp" } } }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

    echo "$DOMAIN" > "$DOMAIN_FILE"
    systemctl restart nginx && systemctl restart xray
    echo -e "${GREEN}Instalasi Selesai!${NC}"
    sleep 2
    main_menu
}

add_user() {
    echo -ne "  ${YELLOW}Nama User Baru:${NC} "
    read USERNAME
    if [[ -z "$USERNAME" ]]; then return; fi
    UUID=$(cat /proc/sys/kernel/random/uuid)
    PASS="${USERNAME}$(shuf -i 100-999 -n 1)"
    for i in 0 2 4 6; do jq ".inbounds[$i].settings.clients += [{\"id\": \"$UUID\", \"email\": \"$USERNAME\"}]" $CONFIG_XRAY > tmp.json && mv tmp.json $CONFIG_XRAY; done
    for i in 1 3 5; do jq ".inbounds[$i].settings.clients += [{\"password\": \"$PASS\", \"email\": \"$USERNAME\"}]" $CONFIG_XRAY > tmp.json && mv tmp.json $CONFIG_XRAY; done
    systemctl restart xray
    show_links "$USERNAME" "$UUID" "$PASS"
}

show_links() {
    local USER=$1; local UUID=$2; local PASS=$3; local DOMAIN=$(cat $DOMAIN_FILE)
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${GREEN}CONFIG LINKS FOR USER:${NC} ${YELLOW}$USER${NC}"
    echo -e "${CYAN}├──────────────────────────────────────────────────────────┤${NC}"
    echo -e "${BLUE}[ VLESS ]${NC}"
    echo -e " WS      : vless://$UUID@$DOMAIN:443?path=%2Fvless-ws&security=tls&encryption=none&type=ws#$USER-VLESS-ws"
    echo -e " gRPC    : vless://$UUID@$DOMAIN:443?mode=multi&serviceName=vless-grpc&security=tls&encryption=none&type=grpc#$USER-VLESS-grpc"
    echo -e " Upgrade : vless://$UUID@$DOMAIN:443?path=%2Fvless-upgrade&security=tls&encryption=none&type=httpupgrade#$USER-VLESS-upgrade"
    echo -e " XHTTP   : vless://$UUID@$DOMAIN:443?path=%2Fxhttp&security=tls&encryption=none&type=xhttp&mode=packet-streamed#$USER-VLESS-xhttp"
    echo -e ""
    echo -e "${BLUE}[ TROJAN ]${NC}"
    echo -e " WS      : trojan://$PASS@$DOMAIN:443?path=%2Ftrojan-ws&security=tls&type=ws#$USER-TROJAN-ws"
    echo -e " gRPC    : trojan://$PASS@$DOMAIN:443?mode=multi&serviceName=trojan-grpc&security=tls&type=grpc#$USER-TROJAN-grpc"
    echo -e " Upgrade : trojan://$PASS@$DOMAIN:443?path=%2Ftrojan-upgrade&security=tls&type=httpupgrade#$USER-TROJAN-upgrade"
    echo -e "${CYAN}└──────────────────────────────────────────────────────────┘${NC}"
    read -p "Tekan Enter..."
    main_menu
}

list_user() {
    clear
    USERS=$(jq -r '.inbounds[0].settings.clients[].email' $CONFIG_XRAY)
    if [[ -z "$USERS" ]]; then echo -e "${RED}Kosong.${NC}"; sleep 2; main_menu; return; fi
    echo -e "${YELLOW}Pilih user:${NC}"
    select USERNAME in $USERS "Kembali"; do
        if [ "$USERNAME" == "Kembali" ]; then main_menu; break; fi
        UUID=$(jq -r ".inbounds[0].settings.clients[] | select(.email==\"$USERNAME\") | .id" $CONFIG_XRAY)
        PASS=$(jq -r ".inbounds[1].settings.clients[] | select(.email==\"$USERNAME\") | .password" $CONFIG_XRAY)
        show_links "$USERNAME" "$UUID" "$PASS"; break
    done
}

del_user() {
    clear
    USERS=$(jq -r '.inbounds[0].settings.clients[].email' $CONFIG_XRAY)
    echo -e "${RED}Pilih user untuk dihapus:${NC}"
    select USERNAME in $USERS "Batal"; do
        if [ "$USERNAME" == "Batal" ]; then main_menu; break; fi
        for i in {0..6}; do jq ".inbounds[$i].settings.clients |= del(.[] | select(.email == \"$USERNAME\"))" $CONFIG_XRAY > tmp.json && mv tmp.json $CONFIG_XRAY; done
        systemctl restart xray
        echo -e "${GREEN}User $USERNAME dihapus.${NC}"
        sleep 2; main_menu; break
    done
}

check_services() {
    clear
    echo -e "${BLUE}┌───────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}      SERVICE STATUS       ${BLUE}│${NC}"
    echo -e "${BLUE}├───────────────────────────┤${NC}"
    echo -ne "${BLUE}│${NC} Xray  : "
    if systemctl is-active --quiet xray; then echo -e "${GREEN}RUNNING${NC}     ${BLUE}│${NC}"; else echo -e "${RED}STOPPED${NC}     ${BLUE}│${NC}"; fi
    echo -ne "${BLUE}│${NC} Nginx : "
    if systemctl is-active --quiet nginx; then echo -e "${GREEN}RUNNING${NC}     ${BLUE}│${NC}"; else echo -e "${RED}STOPPED${NC}     ${BLUE}│${NC}"; fi
    echo -e "${BLUE}└───────────────────────────┘${NC}"
    read -p "Tekan Enter..."
    main_menu
}

main_menu() {
    clear
    DOMAIN=$(cat $DOMAIN_FILE 2>/dev/null || echo "Belum Setup")
    OS=$(cat /etc/os-release | grep -w PRETTY_NAME | cut -d= -f2 | tr -d '"')
    RAM=$(free -m | awk '/Mem:/ { print $3 "MB / " $2 "MB" }')
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')%

    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}                ${GREEN}XRAY ULTIMATE DASHBOARD${NC}                 ${BLUE}│${NC}"
    echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${NC}"
    echo -e "${BLUE}│${NC}  ${YELLOW}OS${NC}      : $OS"
    echo -e "${BLUE}│${NC}  ${YELLOW}DOMAIN${NC}  : $DOMAIN"
    echo -e "${BLUE}│${NC}  ${YELLOW}RAM${NC}     : $RAM"
    echo -e "${BLUE}│${NC}  ${YELLOW}CPU${NC}     : $CPU Usage"
    echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}[1]${NC} Tambah User Baru (All Protocols)             ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}[2]${NC} Hapus User Aktif                             ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}[3]${NC} Lihat Daftar User & Share Link               ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}[4]${NC} Cek Status Service Sistem                    ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${PURPLE}[R]${NC} Reinstall Script (Reset Total)               ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}[5]${NC} Keluar (Exit)                                ${BLUE}│${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${NC}"
    echo -ne "  ${YELLOW}Pilih menu:${NC} "
    read opt
    case $opt in
        1) add_user ;;
        2) del_user ;;
        3) list_user ;;
        4) check_services ;;
        [rR]) reinstall_script ;;
        5) exit ;;
        *) main_menu ;;
    esac
}

check_install() {
    if [[ -f "$CONFIG_XRAY" ]]; then
        main_menu
    else
        echo -e "${YELLOW}Sistem belum terinstal. Memulai setup awal...${NC}"
        install_all
    fi
}

check_install
