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
  read -p "Expired (days): " days

  exp=$(date -d "$days days" +"%Y-%m-%d")

  useradd -e $exp -s /bin/false -M $user
  echo "$user:$pass" | chpasswd

  echo "User created successfully"
  echo "Username : $user"
  echo "Expired  : $exp"
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
