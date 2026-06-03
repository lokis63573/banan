#!/bin/bash
set -e

echo "=== M3 TASK 2: AUTO CA + HTTPS WITHOUT HQ-CLI ==="

ROOT_USER="root"
ROOT_PASS="toor"

HQ_SRV_IP="10.10.100.2"
ISP_IP="172.16.1.1"

WORKDIR="/root/m3-ca-work"
mkdir -p "$WORKDIR"

echo "=== INSTALL EXPECT IF NEEDED ==="

if ! command -v expect >/dev/null 2>&1; then
    apt-get install -y expect || {
        apt-get update || true
        apt-get install -y expect
    }
fi

if ! command -v expect >/dev/null 2>&1; then
    echo "[ERROR] expect не установлен"
    exit 1
fi

echo "=== CREATE HQ-SRV REMOTE SCRIPT ==="

cat > "$WORKDIR/hq-ca-create.sh" <<'EOF'
#!/bin/bash
set -e

echo "=== HQ-SRV: CREATE CA AND WEB CERTS ==="

CA_DIR="/root/ca"
OUT_DIR="/tmp/m3-certs"

rm -rf "$OUT_DIR"
mkdir -p "$CA_DIR" "$OUT_DIR"

openssl genrsa -out "$CA_DIR/au-team-ca.key" 4096

openssl req -x509 -new -nodes \
    -key "$CA_DIR/au-team-ca.key" \
    -sha256 \
    -days 3650 \
    -out "$CA_DIR/au-team-ca.crt" \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=AU-TEAM/OU=IRPO/CN=AU-TEAM-CA"

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

openssl genrsa -out "$CA_DIR/web.key" 4096

openssl req -new \
    -key "$CA_DIR/web.key" \
    -out "$CA_DIR/web.csr" \
    -config "$CA_DIR/web.cnf"

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

cp "$CA_DIR/au-team-ca.crt" "$OUT_DIR/"
cp "$CA_DIR/web.crt" "$OUT_DIR/"
cp "$CA_DIR/web.key" "$OUT_DIR/"

chmod 644 "$OUT_DIR/au-team-ca.crt" "$OUT_DIR/web.crt"
chmod 600 "$OUT_DIR/web.key"

tar -czf /tmp/m3-certs.tar.gz -C "$OUT_DIR" .

echo
echo "=== HQ-SRV CERT CHECK ==="
openssl x509 -in "$OUT_DIR/web.crt" -noout -subject -issuer -dates
openssl x509 -in "$OUT_DIR/web.crt" -noout -text | grep -A2 "Subject Alternative Name"

echo
echo "=== HQ-SRV FILES ==="
ls -la "$OUT_DIR"
ls -la /tmp/m3-certs.tar.gz

echo "[OK] HQ-SRV certificates created"
EOF

echo "=== CREATE ISP REMOTE SCRIPT ==="

cat > "$WORKDIR/isp-https.sh" <<'EOF'
#!/bin/bash
set -e

echo "=== ISP: CONFIGURE NGINX HTTPS ==="

mkdir -p /etc/nginx/ssl
tar -xzf /tmp/m3-certs.tar.gz -C /etc/nginx/ssl

chmod 644 /etc/nginx/ssl/au-team-ca.crt
chmod 644 /etc/nginx/ssl/web.crt
chmod 600 /etc/nginx/ssl/web.key

cp /etc/nginx/sites-available.d/reverse-proxy.conf \
   /etc/nginx/sites-available.d/reverse-proxy.conf.bak.$(date +%F_%H-%M-%S) 2>/dev/null || true

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
ss -tulpn | grep -E ":443|nginx" || true

echo
echo "=== ISP NGINX CONFIG ==="
cat /etc/nginx/sites-available.d/reverse-proxy.conf

echo "[OK] ISP nginx HTTPS configured"
EOF

chmod +x "$WORKDIR/"*.sh

expect_scp_to() {
    local SRC="$1"
    local DST="$2"
    local IP="$3"

expect <<EOF
set timeout 60
spawn scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SRC" ${ROOT_USER}@${IP}:"$DST"
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

expect_scp_from() {
    local IP="$1"
    local SRC="$2"
    local DST="$3"

expect <<EOF
set timeout 60
spawn scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${ROOT_USER}@${IP}:"$SRC" "$DST"
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

expect_ssh_run() {
    local IP="$1"
    local CMD="$2"

expect <<EOF
set timeout 180
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${ROOT_USER}@${IP} "$CMD"
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
echo "=== STEP 1: COPY AND RUN SCRIPT ON HQ-SRV ==="

expect_scp_to "$WORKDIR/hq-ca-create.sh" "/tmp/hq-ca-create.sh" "$HQ_SRV_IP"
expect_ssh_run "$HQ_SRV_IP" "chmod +x /tmp/hq-ca-create.sh && bash /tmp/hq-ca-create.sh"

echo
echo "=== STEP 2: DOWNLOAD CERTS FROM HQ-SRV TO BR-SRV ==="

expect_scp_from "$HQ_SRV_IP" "/tmp/m3-certs.tar.gz" "$WORKDIR/m3-certs.tar.gz"

echo
echo "=== CERT ARCHIVE CHECK ON BR-SRV ==="
tar -tzf "$WORKDIR/m3-certs.tar.gz"

echo
echo "=== STEP 3: COPY CERTS AND CONFIGURE ISP ==="

expect_scp_to "$WORKDIR/m3-certs.tar.gz" "/tmp/m3-certs.tar.gz" "$ISP_IP"
expect_scp_to "$WORKDIR/isp-https.sh" "/tmp/isp-https.sh" "$ISP_IP"
expect_ssh_run "$ISP_IP" "chmod +x /tmp/isp-https.sh && bash /tmp/isp-https.sh"

echo
echo "=== FINAL CHECK COMMANDS ==="
echo "На ISP:"
echo "nginx -t"
echo "ss -tulpn | grep 443"
echo
echo "На HQ-CLI позже вручную нужно добавить доверие CA:"
echo "CA лежит на ISP: /etc/nginx/ssl/au-team-ca.crt"
echo "CA лежит на HQ-SRV: /root/ca/au-team-ca.crt"
echo
echo "Проверка из HQ-CLI после доверия CA:"
echo "https://web.au-team.irpo"
echo "https://docker.au-team.irpo"
echo
echo "Для web.au-team.irpo логин:"
echo "WEB"
echo "P@ssw0rd"

echo
echo "=== M3 TASK 2 DONE ==="
