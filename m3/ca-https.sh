#!/bin/bash
set -e

echo "=== M3 TASK 2: CA + HTTPS AUTO SCRIPT ==="

ROOT_USER="root"
ROOT_PASS="toor"

HQ_SRV_IP="10.10.100.2"
HQ_SRV_PORT="2026"

ISP_IP="172.16.1.1"
ISP_PORT="22"

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

run_ssh() {
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

copy_to() {
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

copy_from() {
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

chmod +x "$WORKDIR/hq-create-ca.sh" "$WORKDIR/isp-configure-https.sh"

echo
echo "=== STEP 1: COPY CA SCRIPT TO HQ-SRV ==="

copy_to "$WORKDIR/hq-create-ca.sh" "$HQ_SRV_IP" "$HQ_SRV_PORT" "/tmp/hq-create-ca.sh"

echo
echo "=== STEP 2: RUN CA SCRIPT ON HQ-SRV ==="

run_ssh "$HQ_SRV_IP" "$HQ_SRV_PORT" "chmod +x /tmp/hq-create-ca.sh && bash /tmp/hq-create-ca.sh"

echo
echo "=== STEP 3: DOWNLOAD CERT ARCHIVE FROM HQ-SRV ==="

copy_from "$HQ_SRV_IP" "$HQ_SRV_PORT" "/tmp/m3-certs.tar.gz" "$WORKDIR/m3-certs.tar.gz"

echo
echo "=== STEP 4: CHECK CERT ARCHIVE ON BR-SRV ==="

tar -tzf "$WORKDIR/m3-certs.tar.gz"

echo
echo "=== STEP 5: COPY CERT ARCHIVE TO ISP ==="

copy_to "$WORKDIR/m3-certs.tar.gz" "$ISP_IP" "$ISP_PORT" "/tmp/m3-certs.tar.gz"

echo
echo "=== STEP 6: COPY HTTPS SCRIPT TO ISP ==="

copy_to "$WORKDIR/isp-configure-https.sh" "$ISP_IP" "$ISP_PORT" "/tmp/isp-configure-https.sh"

echo
echo "=== STEP 7: RUN HTTPS SCRIPT ON ISP ==="

run_ssh "$ISP_IP" "$ISP_PORT" "chmod +x /tmp/isp-configure-https.sh && bash /tmp/isp-configure-https.sh"

echo
echo "=== FINAL CHECKS ==="

echo "На ISP:"
echo "nginx -t"
echo "ss -tulpn | grep 443"
echo "cat /etc/nginx/sites-available.d/reverse-proxy.conf"

echo
echo "На HQ-CLI:"
echo "Пока браузер будет ругаться, пока не доверим корневой CA."
echo "CA лежит на:"
echo "HQ-SRV: /root/ca/au-team-ca.crt"
echo "ISP:    /etc/nginx/ssl/au-team-ca.crt"

echo
echo "=== M3 TASK 2 DONE ==="
