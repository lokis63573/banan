#!/bin/bash
set -e

echo "=== MODULE 3 MASTER: TASK 1 USERS + TASK 2 CA/HTTPS ==="

# =========================
# COMMON SETTINGS
# =========================
ROOT_USER="root"
ROOT_PASS="toor"

CLI_USER="sshuser"
CLI_PASS="P@ssw0rd"

HQ_SRV_IP="10.10.100.2"
HQ_SRV_PORT="2026"

ISP_IP="172.16.1.1"
ISP_PORT="22"

HQ_CLI_IP="10.10.200.2"
HQ_CLI_PORT="22"

BR_CLI_IP="10.20.30.2"
BR_CLI_PORT="22"

WORKDIR="/root/m3-work"
mkdir -p "$WORKDIR"

# =========================
# INSTALL EXPECT
# =========================
echo
echo "=== INSTALL EXPECT IF NEEDED ==="

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

# =========================
# SSH/SCP HELPERS
# =========================
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
spawn scp -P ${PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SRC" ${ROOT_USER}@${IP}:${DST}
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
spawn scp -P ${PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${ROOT_USER}@${IP}:${SRC} "$DST"
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
spawn scp -P ${PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SRC" ${CLI_USER}@${IP}:${DST}
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

# =========================
# TASK 1: IMPORT USERS ON BR-SRV
# =========================
echo
echo "=== M3 TASK 1: IMPORT USERS TO SAMBA DOMAIN ==="

CSV="/mnt/sr0/Users.csv"
mkdir -p /mnt/sr0

if [ ! -f "$CSV" ]; then
    mount /dev/sr0 /mnt/sr0 2>/dev/null || true
fi

if [ ! -f "$CSV" ]; then
    echo "[ERROR] Users.csv not found: $CSV"
    exit 1
fi

echo "[OK] Users.csv found"

samba-tool domain info 127.0.0.1 >/dev/null

echo "[OK] Samba domain available"

CSV_USERS=$(( $(wc -l < "$CSV") - 1 ))
echo "[INFO] Users in CSV: $CSV_USERS"

SAMBA_USERS_COUNT=$(samba-tool user list | wc -l)
IMPORTED_DOT_USERS_COUNT=$(samba-tool user list | grep -E '^[A-Za-z]+\.[A-Za-z]+$' | wc -l || true)

echo "[INFO] Samba users total: $SAMBA_USERS_COUNT"
echo "[INFO] Imported FirstName.LastName users: $IMPORTED_DOT_USERS_COUNT"

CREATED=0
SKIPPED=0
ERRORS=0

reset_samba_password() {
    local USERNAME="$1"
    samba-tool user setpassword "$USERNAME" \
        --newpassword='P@ssw0rd1' \
        --must-change-at-next-login=no >/dev/null 2>&1 || \
    samba-tool user setpassword "$USERNAME" \
        --newpassword='P@ssw0rd1' >/dev/null 2>&1 || true
}

if [ "$SAMBA_USERS_COUNT" -gt 299 ] || [ "$IMPORTED_DOT_USERS_COUNT" -ge 299 ]; then
    echo "[OK] Users already imported, skipping user import"

    for USER in Malachi.Alexander Nelle.Alford Meredith.Arnold Stuart.York; do
        if samba-tool user list | grep -Fxq "$USER"; then
            reset_samba_password "$USER"
            echo "[OK] $USER exists, password updated"
        else
            echo "[WARN] $USER not found"
        fi
    done
else
    echo "[INFO] Users count less than 300, starting import"

    while IFS=';' read -r firstname lastname role phone dep street zip city country password
    do
        [ -z "$firstname" ] && continue
        [ -z "$lastname" ] && continue

        USERNAME="${firstname}.${lastname}"

        if samba-tool user list | grep -Fxq "$USERNAME"; then
            reset_samba_password "$USERNAME"
            echo "[SKIP] $USERNAME already exists, password updated"
            SKIPPED=$((SKIPPED+1))
            continue
        fi

        if samba-tool user create "$USERNAME" 'P@ssw0rd1' \
            --given-name="$firstname" \
            --surname="$lastname"; then
            reset_samba_password "$USERNAME"
            echo "[OK] Created: $USERNAME"
            CREATED=$((CREATED+1))
        else
            echo "[ERROR] Failed: $USERNAME"
            ERRORS=$((ERRORS+1))
        fi

    done < <(tail -n +2 "$CSV")

    echo
    echo "=== TASK 1 SUMMARY ==="
    echo "Created: $CREATED"
    echo "Skipped: $SKIPPED"
    echo "Errors:  $ERRORS"

    for USER in Malachi.Alexander Nelle.Alford Meredith.Arnold Stuart.York; do
        if samba-tool user list | grep -Fxq "$USER"; then
            echo "[OK] $USER exists"
        else
            echo "[WARN] $USER not found"
        fi
    done
fi

# =========================
# TASK 2 REMOTE SCRIPTS
# =========================
echo
echo "=== CREATE REMOTE SCRIPT FOR HQ-SRV ==="

cat > "$WORKDIR/hq-create-ca.sh" <<'EOF'
#!/bin/bash
set -e

CA_DIR="/root/ca"
CERT_DIR="/tmp/m3-certs"
CA_KEY="$CA_DIR/au-team-ca.key"
CA_CRT="$CA_DIR/au-team-ca.crt"
WEB_KEY="$CA_DIR/web.key"
WEB_CRT="$CA_DIR/web.crt"
WEB_CSR="$CA_DIR/web.csr"
WEB_CNF="$CA_DIR/web.cnf"

mkdir -p "$CA_DIR" "$CERT_DIR"
rm -rf "$CERT_DIR"/*

need_new_ca=0
need_new_web=0

if [ ! -f "$CA_KEY" ] || [ ! -f "$CA_CRT" ]; then
    need_new_ca=1
    need_new_web=1
fi

if [ ! -f "$WEB_KEY" ] || [ ! -f "$WEB_CRT" ]; then
    need_new_web=1
else
    if ! openssl x509 -in "$WEB_CRT" -noout -checkend 86400 >/dev/null 2>&1; then
        need_new_web=1
    fi
    if ! openssl x509 -in "$WEB_CRT" -noout -text | grep -q "DNS:web.au-team.irpo"; then
        need_new_web=1
    fi
    if ! openssl x509 -in "$WEB_CRT" -noout -text | grep -q "DNS:docker.au-team.irpo"; then
        need_new_web=1
    fi
fi

if [ "$need_new_ca" -eq 1 ]; then
    echo "[INFO] Creating new CA"
    openssl genrsa -out "$CA_KEY" 4096
    openssl req -x509 -new -nodes \
        -key "$CA_KEY" \
        -sha256 \
        -days 3650 \
        -out "$CA_CRT" \
        -subj "/C=RU/ST=Moscow/L=Moscow/O=AU-TEAM/OU=IRPO/CN=AU-TEAM-CA"
else
    echo "[SKIP] CA already exists"
fi

cat > "$WEB_CNF" <<EOC
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

if [ "$need_new_web" -eq 1 ]; then
    echo "[INFO] Creating web certificate for 30 days"
    openssl genrsa -out "$WEB_KEY" 4096
    openssl req -new \
        -key "$WEB_KEY" \
        -out "$WEB_CSR" \
        -config "$WEB_CNF"
    openssl x509 -req \
        -in "$WEB_CSR" \
        -CA "$CA_CRT" \
        -CAkey "$CA_KEY" \
        -CAcreateserial \
        -out "$WEB_CRT" \
        -days 30 \
        -sha256 \
        -extensions req_ext \
        -extfile "$WEB_CNF"
else
    echo "[SKIP] Web certificate already exists and is valid"
fi

cp "$CA_CRT" "$CERT_DIR/"
cp "$WEB_CRT" "$CERT_DIR/"
cp "$WEB_KEY" "$CERT_DIR/"

chmod 644 "$CERT_DIR/au-team-ca.crt" "$CERT_DIR/web.crt"
chmod 600 "$CERT_DIR/web.key"

tar -czf /tmp/m3-certs.tar.gz -C "$CERT_DIR" .

echo
echo "=== HQ-SRV CERT CHECK ==="
openssl x509 -in "$WEB_CRT" -noout -subject -issuer -dates
openssl x509 -in "$WEB_CRT" -noout -text | grep -A2 "Subject Alternative Name"
ls -la /tmp/m3-certs.tar.gz
EOF

cat > "$WORKDIR/isp-configure-https.sh" <<'EOF'
#!/bin/bash
set -e

echo "=== ISP: CONFIGURE HTTPS NGINX ==="

CERT_ARCHIVE="/tmp/m3-certs.tar.gz"
SSL_DIR="/etc/nginx/ssl"
CONF="/etc/nginx/sites-available.d/reverse-proxy.conf"
TMP_CONF="/tmp/reverse-proxy.conf.new"

if [ ! -f "$CERT_ARCHIVE" ]; then
    echo "[ERROR] Certificate archive not found: $CERT_ARCHIVE"
    exit 1
fi

mkdir -p "$SSL_DIR"
tar -xzf "$CERT_ARCHIVE" -C "$SSL_DIR"
chmod 644 "$SSL_DIR/au-team-ca.crt" "$SSL_DIR/web.crt"
chmod 600 "$SSL_DIR/web.key"

cat > "$TMP_CONF" <<'NGINX'
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

if [ -f "$CONF" ] && cmp -s "$TMP_CONF" "$CONF"; then
    echo "[SKIP] nginx reverse-proxy.conf already configured"
else
    if [ -f "$CONF" ]; then
        cp "$CONF" "$CONF.bak.$(date +%F_%H-%M-%S)"
    fi
    cp "$TMP_CONF" "$CONF"
    echo "[OK] nginx reverse-proxy.conf updated"
fi

nginx -t
systemctl restart nginx

ss -tulpn | grep 443 || true
curl -k -I https://web.au-team.irpo 2>/dev/null | head || true
curl -k -I https://docker.au-team.irpo 2>/dev/null | head || true
EOF

cat > "$WORKDIR/client-trust-ca.sh" <<'EOF'
#!/bin/bash
set -e

echo "=== CLIENT: TRUST AU-TEAM CA ==="

SRC="/tmp/au-team-ca.crt"
DST_DIR="/etc/pki/ca-trust/source/anchors"
DST="$DST_DIR/au-team-ca.crt"

if [ ! -f "$SRC" ]; then
    echo "[ERROR] $SRC not found"
    exit 1
fi

mkdir -p "$DST_DIR"

if [ -f "$DST" ] && cmp -s "$SRC" "$DST"; then
    echo "[SKIP] CA already trusted, reboot not needed"
    exit 0
fi

cp "$SRC" "$DST"
chmod 644 "$DST"

update-ca-trust enable 2>/dev/null || true
update-ca-trust extract 2>/dev/null || update-ca-trust 2>/dev/null || true

ls -la "$DST"
echo "[OK] CA installed, rebooting client"
sleep 3
reboot
EOF

chmod +x "$WORKDIR/hq-create-ca.sh" "$WORKDIR/isp-configure-https.sh" "$WORKDIR/client-trust-ca.sh"

# =========================
# TASK 2 EXECUTION
# =========================
echo
echo "=== M3 TASK 2: CA + HTTPS ==="

echo "=== STEP 1: COPY CA SCRIPT TO HQ-SRV ==="
copy_to_root "$WORKDIR/hq-create-ca.sh" "$HQ_SRV_IP" "$HQ_SRV_PORT" "/tmp/hq-create-ca.sh"

echo "=== STEP 2: RUN CA SCRIPT ON HQ-SRV ==="
run_ssh_root "$HQ_SRV_IP" "$HQ_SRV_PORT" "chmod +x /tmp/hq-create-ca.sh && bash /tmp/hq-create-ca.sh"

echo "=== STEP 3: DOWNLOAD CERT ARCHIVE FROM HQ-SRV ==="
copy_from_root "$HQ_SRV_IP" "$HQ_SRV_PORT" "/tmp/m3-certs.tar.gz" "$WORKDIR/m3-certs.tar.gz"

echo "=== STEP 4: CHECK CERT ARCHIVE ON BR-SRV ==="
tar -tzf "$WORKDIR/m3-certs.tar.gz"

echo "=== STEP 5: COPY CERT ARCHIVE TO ISP ==="
copy_to_root "$WORKDIR/m3-certs.tar.gz" "$ISP_IP" "$ISP_PORT" "/tmp/m3-certs.tar.gz"

echo "=== STEP 6: COPY HTTPS SCRIPT TO ISP ==="
copy_to_root "$WORKDIR/isp-configure-https.sh" "$ISP_IP" "$ISP_PORT" "/tmp/isp-configure-https.sh"

echo "=== STEP 7: RUN HTTPS SCRIPT ON ISP ==="
run_ssh_root "$ISP_IP" "$ISP_PORT" "chmod +x /tmp/isp-configure-https.sh && bash /tmp/isp-configure-https.sh"

echo "=== STEP 8: EXTRACT CA ON BR-SRV ==="
rm -f "$WORKDIR/au-team-ca.crt"
rm -rf "$WORKDIR/certs-extract"
mkdir -p "$WORKDIR/certs-extract"
tar -xzf "$WORKDIR/m3-certs.tar.gz" -C "$WORKDIR/certs-extract"

FOUND_CA="$(find "$WORKDIR/certs-extract" -name 'au-team-ca.crt' -type f | head -1)"

if [ -z "$FOUND_CA" ]; then
    echo "[ERROR] au-team-ca.crt not found in archive"
    tar -tzf "$WORKDIR/m3-certs.tar.gz"
    exit 1
fi

cp "$FOUND_CA" "$WORKDIR/au-team-ca.crt"
chmod 644 "$WORKDIR/au-team-ca.crt"
ls -la "$WORKDIR/au-team-ca.crt"

echo "=== STEP 9: COPY CA TO HQ-CLI, TRUST IT AND REBOOT IF NEEDED ==="
copy_to_cli "$WORKDIR/au-team-ca.crt" "$HQ_CLI_IP" "$HQ_CLI_PORT" "/tmp/au-team-ca.crt"
copy_to_cli "$WORKDIR/client-trust-ca.sh" "$HQ_CLI_IP" "$HQ_CLI_PORT" "/tmp/client-trust-ca.sh"
run_ssh_cli "$HQ_CLI_IP" "$HQ_CLI_PORT" "sudo chmod +x /tmp/client-trust-ca.sh && sudo bash /tmp/client-trust-ca.sh" || true

echo "=== STEP 10: COPY CA TO BR-CLI, TRUST IT AND REBOOT IF NEEDED ==="
copy_to_cli "$WORKDIR/au-team-ca.crt" "$BR_CLI_IP" "$BR_CLI_PORT" "/tmp/au-team-ca.crt"
copy_to_cli "$WORKDIR/client-trust-ca.sh" "$BR_CLI_IP" "$BR_CLI_PORT" "/tmp/client-trust-ca.sh"
run_ssh_cli "$BR_CLI_IP" "$BR_CLI_PORT" "sudo chmod +x /tmp/client-trust-ca.sh && sudo bash /tmp/client-trust-ca.sh" || true


# =========================
# TASK 5/6/8/9 REMOTE SCRIPTS
# =========================

cat > "$WORKDIR/hq-srv-tasks-5-6-9.sh" <<'EOF'
#!/bin/bash
set -e

echo "=== HQ-SRV: TASK 5 CUPS + TASK 6 SYSLOG SERVER + TASK 9 FAIL2BAN ==="

echo "=== TASK 5: CUPS PDF SERVER ==="
rpm -q cups >/dev/null 2>&1 || apt-get install -y cups
rpm -q cups-pdf >/dev/null 2>&1 || apt-get install -y cups-pdf || true

systemctl enable cups >/dev/null 2>&1 || true
systemctl restart cups >/dev/null 2>&1 || systemctl start cups >/dev/null 2>&1 || true
cupsctl --remote-any --share-printers >/dev/null 2>&1 || true

if lpstat -p Cups-PDF >/dev/null 2>&1; then
    echo "[SKIP] Cups-PDF already exists"
else
    lpadmin -p Cups-PDF -E -v cups-pdf:/ -m CUPS-PDF.ppd >/dev/null 2>&1 || \
    lpadmin -p Cups-PDF -E -v cups-pdf:/ -m everywhere >/dev/null 2>&1 || true
fi

lpadmin -d Cups-PDF >/dev/null 2>&1 || true
lpstat -p 2>/dev/null || true
lpstat -d 2>/dev/null || true

echo "=== TASK 6: SYSLOG SERVER ==="
rpm -q rsyslog >/dev/null 2>&1 || apt-get install -y rsyslog

mkdir -p /opt/hq-rtr /opt/br-rtr /opt/br-srv

cat > /etc/rsyslog.d/50-module3-server.conf <<'RSYSLOG'
module(load="imudp")
input(type="imudp" port="514")
module(load="imtcp")
input(type="imtcp" port="514")
$template Module3RemoteLogs,"/opt/%HOSTNAME%/syslog.log"
*.warning ?Module3RemoteLogs
& stop
RSYSLOG

cat > /etc/logrotate.d/module3-remote-logs <<'LOGROTATE'
/opt/*/*.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    minsize 10M
    create 0644 root root
    postrotate
        systemctl reload rsyslog 2>/dev/null || true
    endscript
}
LOGROTATE

systemctl enable rsyslog >/dev/null 2>&1 || true
systemctl restart rsyslog
ss -ulpn | grep ':514' || true
ss -tlpn | grep ':514' || true
ls -la /opt

echo "=== TASK 9: FAIL2BAN SSH ==="
rpm -q fail2ban >/dev/null 2>&1 || apt-get install -y fail2ban || true

mkdir -p /etc/fail2ban/jail.d

# ALT: fail2ban часто падает, если logpath не существует.
touch /var/log/secure
chmod 600 /var/log/secure || true

# Убираем старые конфликтующие настройки sshd.
rm -f /etc/fail2ban/jail.local
rm -f /etc/fail2ban/jail.d/sshd.local
rm -f /etc/fail2ban/jail.d/00-module3-sshd.conf

cat > /etc/fail2ban/jail.local <<'EOF2'
[DEFAULT]
bantime = 60
findtime = 60
maxretry = 3
backend = polling
ignoreip = 127.0.0.1/8 10.10.0.0/16 10.20.0.0/16 169.254.0.0/16

[sshd]
enabled = true
port = 2026
filter = sshd
logpath = /var/log/secure
backend = polling
maxretry = 3
findtime = 60
bantime = 60
EOF2

fail2ban-client -x stop >/dev/null 2>&1 || true
systemctl reset-failed fail2ban >/dev/null 2>&1 || true
systemctl enable fail2ban >/dev/null 2>&1 || true

if fail2ban-client -t >/dev/null 2>&1; then
    echo "[OK] fail2ban config test passed"
else
    echo "[WARN] fail2ban config test failed"
    fail2ban-client -t || true
fi

systemctl restart fail2ban || {
    echo "[WARN] fail2ban restart failed, trying direct start"
    fail2ban-client -x start || true
}

systemctl status fail2ban --no-pager 2>/dev/null | head -15 || true
fail2ban-client status 2>/dev/null || true
fail2ban-client status sshd 2>/dev/null || true

echo "=== HQ-SRV TASKS 5/6/9 DONE ==="
EOF

cat > "$WORKDIR/br-srv-tasks-6-8.sh" <<'EOF'
#!/bin/bash
set -e

echo "=== BR-SRV: TASK 6 SYSLOG CLIENT + TASK 8 ANSIBLE INVENTORY ==="

echo "=== TASK 6: SYSLOG CLIENT ==="
rpm -q rsyslog >/dev/null 2>&1 || apt-get install -y rsyslog

cat > /etc/rsyslog.d/50-module3-client.conf <<'RSYSLOG'
*.warning @10.10.100.2:514
RSYSLOG

systemctl enable rsyslog >/dev/null 2>&1 || true
systemctl restart rsyslog
logger -p user.warning "module3 warning syslog test from br-srv"

echo "=== TASK 8: ANSIBLE INVENTORY ==="
rpm -q ansible >/dev/null 2>&1 || apt-get install -y ansible
rpm -q sshpass >/dev/null 2>&1 || apt-get install -y sshpass || true

mkdir -p /etc/ansible/PC-INFO

[ -f /etc/ansible/hosts ] && cp /etc/ansible/hosts /etc/ansible/hosts.bak.module3.$(date +%F_%H-%M-%S) || true

cat > /etc/ansible/hosts <<'HOSTS'
[hq]
hq-srv ansible_host=10.10.100.2 ansible_port=2026 ansible_user=sshuser ansible_ssh_pass=P@ssw0rd
hq-cli ansible_host=10.10.200.2 ansible_user=sshuser ansible_ssh_pass=P@ssw0rd

[br]
br-cli ansible_host=10.20.30.2 ansible_user=sshuser ansible_ssh_pass=P@ssw0rd

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
HOSTS

cat > /etc/ansible/ansible.cfg <<'CFG'
[defaults]
inventory = /etc/ansible/hosts
host_key_checking = False
retry_files_enabled = False
timeout = 15
CFG

PLAYBOOK_SRC=""
for f in /mnt/sr0/playbook/get_hostname_address.yml /media/cdrom/playbook/get_hostname_address.yml; do
    [ -f "$f" ] && PLAYBOOK_SRC="$f" && break
done

[ -n "$PLAYBOOK_SRC" ] && cp "$PLAYBOOK_SRC" /etc/ansible/get_hostname_address.yml || true

cat > /etc/ansible/module3_inventory.yml <<'PLAY'
---
- name: Module 3 PC inventory
  hosts: hq-srv,hq-cli,br-cli
  gather_facts: yes
  tasks:
    - name: Save hostname and IP report
      copy:
        dest: "/etc/ansible/PC-INFO/{{ inventory_hostname }}.yml"
        content: |
          hostname: {{ ansible_hostname }}
          fqdn: {{ ansible_fqdn | default(ansible_hostname) }}
          ip: {{ ansible_default_ipv4.address | default('unknown') }}
      delegate_to: localhost
PLAY

ansible all -m ping || true
[ -f /etc/ansible/get_hostname_address.yml ] && ansible-playbook /etc/ansible/get_hostname_address.yml || true
ansible-playbook /etc/ansible/module3_inventory.yml || true

ls -la /etc/ansible/PC-INFO
for f in /etc/ansible/PC-INFO/*.yml; do
    [ -f "$f" ] && echo "--- $f ---" && cat "$f"
done

echo "=== BR-SRV TASKS 6/8 DONE ==="
EOF

cat > "$WORKDIR/hq-cli-task-5.sh" <<'EOF'
#!/bin/bash
set -e

echo "=== HQ-CLI: TASK 5 CUPS CLIENT ==="

cat > /tmp/hq-cli-cups-root.sh <<'ROOTEOF'
#!/bin/bash
set -e

rpm -q cups >/dev/null 2>&1 || apt-get install -y cups
rpm -q cups-client >/dev/null 2>&1 || apt-get install -y cups-client || true

systemctl enable cups >/dev/null 2>&1 || true
systemctl restart cups >/dev/null 2>&1 || systemctl start cups >/dev/null 2>&1 || true

if lpstat -p HQ-PDF >/dev/null 2>&1; then
    echo "[SKIP] HQ-PDF already exists"
else
    lpadmin -p HQ-PDF -E -v ipp://10.10.100.2:631/printers/Cups-PDF -m everywhere >/dev/null 2>&1 ||     lpadmin -p HQ-PDF -E -v ipp://10.10.100.2:631/printers/Cups-PDF -m raw >/dev/null 2>&1 || true
fi

if lpstat -p HQ-PDF >/dev/null 2>&1; then
    lpadmin -d HQ-PDF >/dev/null 2>&1 || true
elif lpstat -p Cups-PDF >/dev/null 2>&1; then
    lpadmin -d Cups-PDF >/dev/null 2>&1 || true
else
    echo "[WARN] No HQ-PDF or Cups-PDF printer found"
fi

lpstat -p 2>/dev/null || true
lpstat -d 2>/dev/null || true
ROOTEOF

chmod +x /tmp/hq-cli-cups-root.sh

if [ "$(id -u)" -eq 0 ]; then
    bash /tmp/hq-cli-cups-root.sh
else
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        sudo bash /tmp/hq-cli-cups-root.sh
    else
        echo 'toor' | su - root -c 'bash /tmp/hq-cli-cups-root.sh'
    fi
fi

echo "=== HQ-CLI TASK 5 DONE ==="
EOF

chmod +x "$WORKDIR/hq-srv-tasks-5-6-9.sh"
chmod +x "$WORKDIR/br-srv-tasks-6-8.sh"
chmod +x "$WORKDIR/hq-cli-task-5.sh"

echo
echo "=== M3 TASK 5/6/8/9 EXECUTION ==="

echo "=== STEP 11: COPY AND RUN TASKS 5/6/9 ON HQ-SRV ==="
copy_to_root "$WORKDIR/hq-srv-tasks-5-6-9.sh" "$HQ_SRV_IP" "$HQ_SRV_PORT" "/tmp/hq-srv-tasks-5-6-9.sh"
run_ssh_root "$HQ_SRV_IP" "$HQ_SRV_PORT" "chmod +x /tmp/hq-srv-tasks-5-6-9.sh && bash /tmp/hq-srv-tasks-5-6-9.sh"

echo "=== STEP 12: RUN TASKS 6/8 ON BR-SRV ==="
bash "$WORKDIR/br-srv-tasks-6-8.sh"

echo "=== STEP 13: COPY AND RUN TASK 5 ON HQ-CLI ==="
copy_to_cli "$WORKDIR/hq-cli-task-5.sh" "$HQ_CLI_IP" "$HQ_CLI_PORT" "/tmp/hq-cli-task-5.sh"
run_ssh_cli "$HQ_CLI_IP" "$HQ_CLI_PORT" "chmod +x /tmp/hq-cli-task-5.sh && bash /tmp/hq-cli-task-5.sh" || true

echo "=== TASKS 5/6/8/9 DONE ==="

echo
echo "=== FINAL CHECK COMMANDS ==="
echo "На ISP: nginx -t && ss -tulpn | grep 443"
echo "На HQ-CLI после перезагрузки:"
echo "curl -I https://web.au-team.irpo"
echo "curl -I https://docker.au-team.irpo"
echo "WEB / P@ssw0rd для web.au-team.irpo"

echo
echo "=== MODULE 3 MASTER TASK 1 + TASK 2 DONE ==="
echo "=== Не забываем попу мыть! ==="
echo "=== Попу мыть, попу мыть ==="
echo "=== Нужно каждый день. ==="
echo "=== Гигиеной дорожить ==="
echo "=== Нужно если лень. ==="

echo "=== Припев: ==="
echo "=== Чистая и нежная ==="
echo "=== Попа белоснежная. ==="
echo "=== Будет пахнуть и сиять, ==="
echo "=== Каждый должен это знать.==="
echo
