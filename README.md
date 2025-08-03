
# Cloudflare worker VLESS TROJAN GRPC
- curl -fsSL https://github.com/nationpwned/vps/raw/refs/heads/worker/install.sh -o install.sh
  
- chmod +x install.sh
- sudo su -c "./install.sh"

- Create worker in cloudflare with provided worker.js, dont forget to change the domain...
- Set subdomain to A DNS record with your VPS IP and Proxies off..
- client conf looks like this..

  - name: VLESS-gRPC
    server: YOUR_DOMAIN
    port: 443
    type: vless
    uuid: 1f9b8529-d065-4ac2-a1f2-d56a2c2edbc1
    cipher: auto
    tls: true
    skip-cert-verify: true
    servername: YOUR_DOMAIN
    network: grpc
    grpc-opts:
      grpc-service-name: vless-service
    udp: true
    
  - name: Trojan-gRPC
    server: YOUR_DOMAIN
    port: 443
    type: trojan
    password: ec0a721c3be5d839
    skip-cert-verify: true
    sni: YOUR_DOMAIN
    network: grpc
    grpc-opts:
      grpc-service-name: trojan-service
    udp: true
