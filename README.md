
# Marzban
- curl -fsSL https://github.com/nationpwned/vps/raw/refs/heads/marzban-nowarp/install.sh -o install.sh
  
- chmod +x install.sh
- sudo su -c "./install.sh"
- Source
  https://gozargah.github.io/marzban/en/docs/installation

```
  - name: Trojan-httpupgrade
    server: google.com
    port: 443
    type: trojan
    password: J4YJHuLRj6AtpcM1L8J8rg
    skip-cert-verify: true
    sni: google.com
    network: ws
    ws-opts:
      path: /trojan-httpupgrade
      headers:
        Host: google.com
      v2ray-http-upgrade: true
    udp: true

  - name: VLESS-httpupgrade
    server: google.com
    port: 443
    type: vless
    uuid: 2cbf46b4-8efa-405d-be5f-d3505898885b
    cipher: auto
    tls: true
    skip-cert-verify: true
    servername: google.com
    network: ws
    ws-opts:
      path: /vless-httpupgrade
      headers:
        Host: google.com
      v2ray-http-upgrade: true
    udp: true

  - name: Trojan-xhttp
    server: google.com
    port: 443
    type: trojan
    password: J4YJHuLRj6AtpcM1L8J8rg
    skip-cert-verify: true
    sni: google.com
    network: xhttp
    xhttp-opts:
      path: /trojan-xhttp
      headers:
        Host: google.com
      mode: packet-up
      extra:
        noGRPCHeader: false
    udp: true

  - name: VLESS-xhttp
    server: google.com
    port: 443
    type: vless
    uuid: 2cbf46b4-8efa-405d-be5f-d3505898885b
    cipher: auto
    tls: true
    skip-cert-verify: true
    servername: google.com
    network: xhttp
    xhttp-opts:
      path: /vless-xhttp
      headers:
        Host: google.com
      mode: packet-up
      extra:
        noGRPCHeader: false
    udp: true
```
