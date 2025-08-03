
# Cloudflare worker VLESS TROJAN GRPC
- curl -fsSL https://github.com/nationpwned/vps/raw/refs/heads/worker/install.sh -o install.sh
  
- chmod +x install.sh
- sudo su -c "./install.sh"

- Create worker in cloudflare with provided worker.js, dont forget to change the domain...
- Set subdomain to A DNS record with your VPS IP and Proxies off..
- client conf looks like this..

    echo "vless://1f9b8529-d065-4ac2-a1f2-d56a2c2edbc1@$DOMAIN:443?encryption=none&security=tls&type=grpc&serviceName=vless-service&sni=$DOMAIN#vless-grpc"
    echo "trojan://1f9b8529-d065-4ac2-a1f2-d56a2c2edbc1@$DOMAIN:443?encryption=none&security=tls&type=grpc&serviceName=trojan-service&sni=$DOMAIN#trojan-grpc"

