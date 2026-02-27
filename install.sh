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
  apt update -y
  apt install python3-full -y
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
    useradd -e $exp -s /bin/false -m $user
  else
    exp=$(date -d "$days days" +"%Y-%m-%d")
    exp_label="$exp"
    useradd -e $exp -s /bin/false -m $user
  fi

  echo "$user:$pass" | chpasswd

  USER_HOME="/home/$user"
  mkdir -p "$USER_HOME/.ssh"
  ssh-keygen -t rsa -b 2048 -f "$USER_HOME/.ssh/id_rsa" -q -N ""
  
  cat "$USER_HOME/.ssh/id_rsa.pub" >> "$USER_HOME/.ssh/authorized_keys"
  chmod 700 "$USER_HOME/.ssh"
  chmod 600 "$USER_HOME/.ssh/authorized_keys"
  chown -R $user:$user "$USER_HOME/.ssh"

  PRIVATE_KEY=$(cat "$USER_HOME/.ssh/id_rsa")
  
  HOST_KEY=$(awk '{print $1" "$2}' /etc/ssh/ssh_host_rsa_key.pub 2>/dev/null)
  
  MYIP=$(curl -sS ipv4.icanhazip.com)
  
  if [ -f /etc/sshvpn_domain ]; then
    DOMAIN=$(cat /etc/sshvpn_domain)
  else
    DOMAIN=$MYIP
  fi
  
  BUG="support.zoom.us"
  SNI="${BUG}.@${DOMAIN}"
  
  OUT_DIR="/home/${USER}/client"
  mkdir -p "$OUT_DIR"
  OUT_FILE="${OUT_DIR}/${user}.txt"

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
Config Mihomo (Clash Meta) with Private/Host Key:
proxies:
  - name: SSH-$user
    type: ssh
    server: $SNI
    port: 22
    username: $user
    password: $pass
    private-key: |
$(echo "$PRIVATE_KEY" | sed 's/^/      /')
    host-key:
      - \"$HOST_KEY\"
    host-key-algorithms:
      - ssh-rsa
    udp: true
-------------------------"

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
