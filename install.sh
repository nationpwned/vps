#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

clear
echo "================================="
echo " INSTALL SSHVPN + BADVPN SERVER"
echo "================================="

if [ -f /usr/bin/badvpn-udpgw ]; then
  echo "BadVPN binary already exists, skipping installation..."
else
  echo "Downloading BadVPN binaries..."

  # Setup Domain
  echo "===== SETUP DOMAIN ====="
  read -p "Masukkan Domain/Subdomain: " DOMAIN
  echo "$DOMAIN" > /etc/sshvpn_domain
  echo "Domain $DOMAIN berhasil disimpan."
  echo ""

  wget -O /usr/bin/badvpn-client https://github.com/nationpwned/vps/raw/refs/heads/sshvpn/badvpn/badvpn-client
  wget -O /usr/bin/badvpn-flooder https://github.com/nationpwned/vps/raw/refs/heads/sshvpn/badvpn/badvpn-flooder
  wget -O /usr/bin/badvpn-ncd https://github.com/nationpwned/vps/raw/refs/heads/sshvpn/badvpn/badvpn-ncd
  wget -O /usr/bin/badvpn-ncd-request https://github.com/nationpwned/vps/raw/refs/heads/sshvpn/badvpn/badvpn-ncd-request
  wget -O /usr/bin/badvpn-server https://github.com/nationpwned/vps/raw/refs/heads/sshvpn/badvpn/badvpn-server
  wget -O /usr/bin/badvpn-tun2socks https://github.com/nationpwned/vps/raw/refs/heads/sshvpn/badvpn/badvpn-tun2socks
  wget -O /usr/bin/badvpn-tunctl https://github.com/nationpwned/vps/raw/refs/heads/sshvpn/badvpn/badvpn-tunctl
  wget -O /usr/bin/badvpn-udpgw https://github.com/nationpwned/vps/raw/refs/heads/sshvpn/badvpn/badvpn-udpgw

  wget -O /usr/bin/sshsocksvpn https://raw.githubusercontent.com/nationpwned/vps/refs/heads/sshvpn/sshsocksvpn/sshsocksvpn

  chmod +x /usr/bin/badvpn-*
  chmod +x /usr/bin/sshsocksvpn

  echo "Creating BadVPN UDPGW service..."

  cat <<EOF >/etc/systemd/system/badvpn.service
[Unit]
Description=BadVPN UDPGW
After=network.target

[Service]
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 0.0.0.0:7300 --max-clients 2000 --max-connections-for-client 20
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  ufw allow 7300/udp
  ufw allow 7300/tcp

  systemctl daemon-reload
  systemctl enable badvpn
  systemctl restart badvpn

  echo "Installing SSH manager..."

  cat <<'EOF' >/usr/bin/sshvpn
#!/bin/bash

clear

function add_user(){

echo "===== ADD USER ====="
read -p "Username: " user

if id "$user" &>/dev/null; then
  echo "Error: User '$user' already exists!"
else
  read -p "Password: " pass
  read -p "Expired (days) [kosongkan untuk unlimited]: " days

  if [[ -z "$days" || "$days" == "0" ]]; then
    exp="2099-12-31"
    exp_label="Unlimited"
    # Menggunakan perintah chage jika unlimited, atau kita bisa tetap pakai useradd -e
    useradd -e $exp -s /bin/false -M $user
  else
    exp=$(date -d "$days days" +"%Y-%m-%d")
    exp_label="$exp"
    useradd -e $exp -s /bin/false -M $user
  fi

  echo "$user:$pass" | chpasswd
  
  # Ambil IP Public VPS
  MYIP=$(curl -sS ipv4.icanhazip.com)
  
  # Ambil Domain dari Instalasi
  if [ -f /etc/sshvpn_domain ]; then
    DOMAIN=$(cat /etc/sshvpn_domain)
  else
    DOMAIN=$MYIP
  fi
  
  # Setup Bug SNI
  BUG="support.zoom.us"
  SNI="${BUG}.@${DOMAIN}"

  # Tentukan folder output
  # Menggunakan SUDO_USER agar tersimpan di home folder user asli pemanggil script, bukan di /root/ jika pakai sudo.
  # Jika SUDO_USER kosong, gunakan USER biasa (root).
  HOME_DIR=$(eval echo ~${SUDO_USER:-$USER})
  OUT_DIR="${HOME_DIR}/sshvpn/user"
  mkdir -p "$OUT_DIR"
  OUT_FILE="${OUT_DIR}/${user}.txt"

  # Buat format text
  CONFIG_TXT="User created successfully
-------------------------
Username   : $user
Password   : $pass
Expired    : $exp_label
-------------------------
Host/IP    : $MYIP
Domain     : $DOMAIN
Port SSH   : 22
Port UDPGW : 7300
-------------------------
Bug / Host : $BUG
SNI / SN   : $SNI
-------------------------
Payload WS / HTTP Custom:
$SNI:22@$user:$pass
-------------------------
Config Mihomo (Clash Meta):
proxies:
  - name: SSH-$user
    type: ssh
    server: $SNI
    port: 22
    username: $user
    password: $pass
    udp: true
-------------------------"

  # Tampilkan ke terminal dan simpan ke file
  echo "$CONFIG_TXT" | tee "$OUT_FILE"
  echo ""
  echo "=> Config tersimpan di: $OUT_FILE"
fi

}

function del_user(){

echo "===== DELETE USER ====="
read -p "Username: " user

if id "$user" &>/dev/null; then
  killall -u $user 2>/dev/null || true
  userdel -f $user
  echo "User '$user' has been deleted successfully."
else
  echo "Error: User '$user' not found."
fi

}

function list_user(){

echo "===== LIST USER ====="

awk -F: '$3 >= 1000 && $1!="nobody" {print $1}' /etc/passwd | while read user
do
exp=$(chage -l $user | grep "Account expires" | cut -d: -f2)
echo "$user | Expire:$exp"
done

}

echo "==========================="
echo "         SSH MENU"
echo "==========================="
echo "1. Add User"
echo "2. Delete User"
echo "3. List User"
echo "4. Exit"
echo "==========================="
read -p "Select: " menu

case $menu in
1) add_user ;;
2) del_user ;;
3) list_user ;;
4) exit ;;
*) echo "Invalid" ;;
esac
EOF

  chmod +x /usr/bin/sshvpn

  echo ""
  echo "================================="
  echo "BadVPN UDPGW running on port 7300"
  echo "Open SSH manager with command:"
  echo "sshvpn"
  echo "================================="
fi

echo ""
echo "Entering SSH Menu..."
sleep 2
sshvpn
