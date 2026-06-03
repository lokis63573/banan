#!/bin/bash
set -e

echo "=== M3 TASK 2: CA + HTTPS AUTO SCRIPT ==="

ROOT_USER="root"
ROOT_PASS="toor"

HQ_SRV_IP="10.10.100.2"
HQ_SRV_PORT="2026"

ISP_IP="172.16.1.1"
ISP_PORT="22"

CLI_USER="sshuser"
CLI_PASS="P@ssw0rd"

HQ_CLI_IP="10.10.200.2"
HQ_CLI_PORT="22"

BR_CLI_IP="10.20.30.2"
BR_CLI_PORT="22"

WORKDIR="/root/m3-ca-work"
mkdir -p "$WORKDIR"

echo
echo "=== INSTALL EXPECT ==="

if ! command -v expect >/dev/null 2>&1; then
    apt-get install -y expect || {
        apt-get update || true
        apt-get install -y expect
    }
fi

if ! command -v expect >/dev/null 2>&1; then
    echo "[ERROR] expect not installed"
    exit 1
fi

run_ssh_root() {
    local IP="$1"
    local PORT="$2"
    local CMD="$3"

expect <<EOF
set timeout 240
spawn ssh -p ${PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${ROOT_USER}@${IP} "$CMD"
expect {
    "yes/no" {
        send "yes\r"
        exp_continue
    }
    "assword:" {
        send "${ROOT_PASS}\r"
    }
}
expect eof
EOF
}

copy_to_root() {
    local SRC="$1"
    local IP="$2"
    local PORT="$3"
    local DST="$4"

expect <<EOF
set timeout 120
spawn scp -P ${PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SRC" ${ROOT_USER}@${IP}:"$DST"
expect {
    "yes/no" {
        send "yes\r"
        exp_continue
    }
    "assword:" {
        send "${ROOT_PASS}\r"
    }
}
expect eof
EOF
}

copy_from_root() {
    local IP="$1"
    local PORT="$2"
    local SRC="$3"
    local DST="$4"

expect <<EOF
set timeout 120
spawn scp -P ${PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${ROOT_USER}@${IP}:"$SRC" "$DST"
expect {
    "yes/no" {
        send "yes\r"
        exp_continue
    }
    "assword:" {
        send "${ROOT_PASS}\r"
    }
}
expect eof
EOF
}

run_ssh_cli() {
    local IP="$1"
    local PORT="$2"
    local CMD="$3"

expect <<EOF
set timeout 240
spawn ssh -p ${PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLI_USER}@${IP} "$CMD"
expect {
    "yes/no" {
        send "yes\r"
        exp_continue
    }
    "assword:" {
        send "${CLI_PASS}\r"
    }
}
expect eof
EOF
}

copy_to_cli() {
    local SRC="$1"
    local IP="$2"
    local PORT="$3"
    local DST="$4"

expect <<EOF
set timeout 120
spawn scp -P ${PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SRC" ${CLI_USER}@${IP}:"$DST"
expect {
    "yes/no" {
        send "yes\r"
        exp_continue
    }
    "assword:" {
        send "${CLI_PASS}\r"
    }
}
expect eof
EOF
}

echo
echo "=== CREATE REMOTE SCRIPT FOR HQ-SRV ==="

cat > "$WORKDIR/hq-create-ca.sh" <<'EOF'
#!/bin/bash
set -e

echo "=== HQ-SRV: CREATE CA AND CERTIFICATES ==="

CA_DIR="/root/ca"
CERT_DIR="/tmp/m3-certs"

rm -rf "$CERT_DIR"
mkdir -p "$CA_DIR" "$CERT_DIR"

echo "[1] Generate CA private key"
openssl genrsa -out "$CA_DIR/au-team-ca.key" 4096

echo "[2] Generate CA certificate"
openssl req -x509 -new -nodes \
    -key "$CA_DIR/au-team-ca.key" \
    -sha256 \
    -days 3650 \
    -out "$CA_DIR/au-team-ca.crt" \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=AU-TEAM/OU=IRPO/CN=AU-TEAM-CA"

echo "[3] Create web certificate config"
cat > "$CA_DIR/web.cnf" <<EOC
[ req ]
default_bits       = 4096
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = req_ext

[ dn ]
C  = RU
ST = Moscow
L  = Moscow
O  = AU-TEAM
OU = Web
CN = web.au-team.irpo

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = web.au-team.irpo
DNS.2 = docker.au-team.irpo
EOC

echo "[4] Generate web private key"
openssl genrsa -out "$CA_DIR/web.key" 4096

echo "[5] Generate CSR"
openssl req -new \
    -key "$CA_DIR/web.key" \
    -out "$CA_DIR/web.csr" \
    -config "$CA_DIR/web.cnf"

echo "[6] Sign web certificate for 30 days"
openssl x509 -req \
    -in "$CA_DIR/web.csr" \
    -CA "$CA_DIR/au-team-ca.crt" \
    -CAkey "$CA_DIR/au-team-ca.key" \
    -CAcreateserial \
    -out "$CA_DIR/web.crt" \
    -days 30 \
    -sha256 \
    -extensions req_ext \
    -extfile "$CA_DIR/web.cnf"

cp "$CA_DIR/au-team-ca.crt" "$CERT_DIR/"
cp "$CA_DIR/web.crt" "$CERT_DIR/"
cp "$CA_DIR/web.key" "$CERT_DIR/"

chmod 644 "$CERT_DIR/au-team-ca.crt" "$CERT_DIR/web.crt"
chmod 600 "$CERT_DIR/web.key"

tar -czf /tmp/m3-certs.tar.gz -C "$CERT_DIR" .

echo
echo "=== CERTIFICATE CHECK ==="
openssl x509 -in "$CERT_DIR/web.crt" -noout -subject -issuer -dates
openssl x509 -in "$CERT_DIR/web.crt" -noout -text | grep -A2 "Subject Alternative Name"

echo
echo "=== CREATED FILES ==="
ls -la "$CERT_DIR"
ls -la /tmp/m3-certs.tar.gz

echo "[OK] HQ-SRV CA and certificates created"
EOF

echo
echo "=== CREATE REMOTE SCRIPT FOR ISP ==="

cat > "$WORKDIR/isp-configure-https.sh" <<'EOF'
#!/bin/bash
set -e

echo "=== ISP: CONFIGURE HTTPS NGINX ==="

CERT_ARCHIVE="/tmp/m3-certs.tar.gz"
SSL_DIR="/etc/nginx/ssl"

if [ ! -f "$CERT_ARCHIVE" ]; then
    echo "[ERROR] Certificate archive not found: $CERT_ARCHIVE"
    exit 1
fi

mkdir -p "$SSL_DIR"
tar -xzf "$CERT_ARCHIVE" -C "$SSL_DIR"

chmod 644 "$SSL_DIR/au-team-ca.crt"
chmod 644 "$SSL_DIR/web.crt"
chmod 600 "$SSL_DIR/web.key"

if [ -f /etc/nginx/sites-available.d/reverse-proxy.conf ]; then
    cp /etc/nginx/sites-available.d/reverse-proxy.conf \
       /etc/nginx/sites-available.d/reverse-proxy.conf.bak.$(date +%F_%H-%M-%S)
fi

cat > /etc/nginx/sites-available.d/reverse-proxy.conf <<'NGINX'
server {
    listen 80;
    server_name web.au-team.irpo docker.au-team.irpo;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name web.au-team.irpo;

    ssl_certificate     /etc/nginx/ssl/web.crt;
    ssl_certificate_key /etc/nginx/ssl/web.key;

    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        proxy_pass http://172.16.1.2:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}

server {
    listen 443 ssl;
    server_name docker.au-team.irpo;

    ssl_certificate     /etc/nginx/ssl/web.crt;
    ssl_certificate_key /etc/nginx/ssl/web.key;

    location / {
        proxy_pass http://172.16.2.2:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX

nginx -t
systemctl restart nginx

echo
echo "=== ISP HTTPS CHECK ==="
ss -tulpn | grep 443 || true
curl -k -I https://web.au-team.irpo 2>/dev/null | head || true
curl -k -I https://docker.au-team.irpo 2>/dev/null | head || true

echo "[OK] ISP nginx HTTPS configured"
EOF

echo
echo "=== CREATE REMOTE SCRIPT FOR CLIENTS ==="

cat > "$WORKDIR/client-trust-ca.sh" <<'EOF'
#!/bin/bash
set -e

echo "=== CLIENT: TRUST AU-TEAM CA ==="

if [ ! -f /tmp/au-team-ca.crt ]; then
    echo "[ERROR] /tmp/au-team-ca.crt not found"
    exit 1
fi

mkdir -p /etc/pki/ca-trust/source/anchors

cp /tmp/au-team-ca.crt \
   /etc/pki/ca-trust/source/anchors/au-team-ca.crt

chmod 644 /etc/pki/ca-trust/source/anchors/au-team-ca.crt

update-ca-trust enable 2>/dev/null || true
update-ca-trust extract 2>/dev/null || update-ca-trust 2>/dev/null || true

echo
echo "=== CLIENT CA CHECK ==="
ls -la /etc/pki/ca-trust/source/anchors/au-team-ca.crt
echo "[OK] CA installed to trust store"
echo "[INFO] Rebooting client in 3 seconds..."

sleep 3
reboot
EOF

chmod +x "$WORKDIR/hq-create-ca.sh"
chmod +x "$WORKDIR/isp-configure-https.sh"
chmod +x "$WORKDIR/client-trust-ca.sh"

echo
echo "=== STEP 1: COPY CA SCRIPT TO HQ-SRV ==="
copy_to_root "$WORKDIR/hq-create-ca.sh" "$HQ_SRV_IP" "$HQ_SRV_PORT" "/tmp/hq-create-ca.sh"

echo
echo "=== STEP 2: RUN CA SCRIPT ON HQ-SRV ==="
run_ssh_root "$HQ_SRV_IP" "$HQ_SRV_PORT" "chmod +x /tmp/hq-create-ca.sh && bash /tmp/hq-create-ca.sh"

echo
echo "=== STEP 3: DOWNLOAD CERT ARCHIVE FROM HQ-SRV ==="
copy_from_root "$HQ_SRV_IP" "$HQ_SRV_PORT" "/tmp/m3-certs.tar.gz" "$WORKDIR/m3-certs.tar.gz"

echo
echo "=== STEP 4: CHECK CERT ARCHIVE ON BR-SRV ==="
tar -tzf "$WORKDIR/m3-certs.tar.gz"

echo
echo "=== STEP 5: COPY CERT ARCHIVE TO ISP ==="
copy_to_root "$WORKDIR/m3-certs.tar.gz" "$ISP_IP" "$ISP_PORT" "/tmp/m3-certs.tar.gz"

echo
echo "=== STEP 6: COPY HTTPS SCRIPT TO ISP ==="
copy_to_root "$WORKDIR/isp-configure-https.sh" "$ISP_IP" "$ISP_PORT" "/tmp/isp-configure-https.sh"

echo
echo "=== STEP 7: RUN HTTPS SCRIPT ON ISP ==="
run_ssh_root "$ISP_IP" "$ISP_PORT" "chmod +x /tmp/isp-configure-https.sh && bash /tmp/isp-configure-https.sh"

echo
echo "=== STEP 8: EXTRACT CA ON BR-SRV ==="
rm -f "$WORKDIR/au-team-ca.crt"
tar -xzf "$WORKDIR/m3-certs.tar.gz" -C "$WORKDIR" au-team-ca.crt

echo
echo "=== STEP 9: COPY CA TO HQ-CLI, TRUST IT AND REBOOT ==="
copy_to_cli "$WORKDIR/au-team-ca.crt" "$HQ_CLI_IP" "$HQ_CLI_PORT" "/tmp/au-team-ca.crt"
copy_to_cli "$WORKDIR/client-trust-ca.sh" "$HQ_CLI_IP" "$HQ_CLI_PORT" "/tmp/client-trust-ca.sh"
run_ssh_cli "$HQ_CLI_IP" "$HQ_CLI_PORT" "sudo chmod +x /tmp/client-trust-ca.sh && sudo bash /tmp/client-trust-ca.sh" || true

echo
echo "=== STEP 10: COPY CA TO BR-CLI, TRUST IT AND REBOOT ==="
copy_to_cli "$WORKDIR/au-team-ca.crt" "$BR_CLI_IP" "$BR_CLI_PORT" "/tmp/au-team-ca.crt"
copy_to_cli "$WORKDIR/client-trust-ca.sh" "$BR_CLI_IP" "$BR_CLI_PORT" "/tmp/client-trust-ca.sh"
run_ssh_cli "$BR_CLI_IP" "$BR_CLI_PORT" "sudo chmod +x /tmp/client-trust-ca.sh && sudo bash /tmp/client-trust-ca.sh" || true

echo
echo "=== FINAL CHECKS ==="
echo "На ISP:"
echo "nginx -t"
echo "ss -tulpn | grep 443"
echo "cat /etc/nginx/sites-available.d/reverse-proxy.conf"

echo
echo "После перезагрузки HQ-CLI проверь:"
echo "curl -I https://web.au-team.irpo"
echo "curl -I https://docker.au-team.irpo"

echo
echo "В браузере HQ-CLI:"
echo "https://web.au-team.irpo"
echo "https://docker.au-team.irpo"

echo
echo "Для web.au-team.irpo логин:"
echo "WEB"
echo "P@ssw0rd"

echo
echo "=== WHY BROWSER WILL NOT WARN ==="
echo "1. web.crt signed by AU-TEAM-CA"
echo "2. au-team-ca.crt installed into client trusted anchors"
echo "3. certificate has SAN: web.au-team.irpo and docker.au-team.irpo"
echo "4. certificate validity is 30 days"

echo
echo "=== M3 TASK 2 DONE ==="
