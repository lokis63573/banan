#!/bin/bash
set -e

echo "=== M2 ISP START ==="

echo "[1] Настройка Chrony"

sed -i '/^local stratum/d' /etc/chrony.conf

grep -q "^local stratum 5" /etc/chrony.conf || \
echo "local stratum 5" >> /etc/chrony.conf

chronyc makestep >/dev/null 2>&1 || true
systemctl restart chronyd

echo "[2] Создание пароля WEB для nginx"

printf "WEB:$(openssl passwd -apr1 'P@ssw0rd')\n" > /etc/nginx/.htpasswd
chmod 644 /etc/nginx/.htpasswd

echo "[3] Настройка reverse proxy nginx"

cat > /etc/nginx/sites-available.d/reverse-proxy.conf <<'EOF'
server {
    listen 80;
    server_name web.au-team.irpo;

    location / {
        auth_basic "Restricted Access";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://172.16.1.2:8080;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}

server {
    listen 80;
    server_name docker.au-team.irpo;

    location / {
        proxy_pass http://172.16.2.2:8080;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

echo "[4] Проверка конфига и перезапуск nginx"

nginx -t
systemctl restart nginx

echo
echo "=== M2 ISP CHECK ==="

systemctl is-active --quiet chronyd \
&& echo "[OK] chronyd active" \
|| { echo "[ERROR] chronyd not active"; exit 1; }

systemctl is-active --quiet nginx \
&& echo "[OK] nginx active" \
|| { echo "[ERROR] nginx not active"; exit 1; }

grep -q "^local stratum 5" /etc/chrony.conf \
&& echo "[OK] stratum 5 configured" \
|| { echo "[ERROR] stratum 5 missing"; exit 1; }

test -f /etc/nginx/.htpasswd \
&& echo "[OK] .htpasswd exists" \
|| { echo "[ERROR] .htpasswd missing"; exit 1; }

grep -q "^WEB:" /etc/nginx/.htpasswd \
&& echo "[OK] WEB account exists" \
|| { echo "[ERROR] WEB account missing"; exit 1; }

grep -q "server_name web.au-team.irpo" /etc/nginx/sites-available.d/reverse-proxy.conf \
&& echo "[OK] web.au-team.irpo configured" \
|| { echo "[ERROR] web.au-team.irpo missing"; exit 1; }

grep -q "proxy_pass http://172.16.1.2:8080" /etc/nginx/sites-available.d/reverse-proxy.conf \
&& echo "[OK] HQ-SRV proxy configured" \
|| { echo "[ERROR] HQ-SRV proxy missing"; exit 1; }

grep -q "server_name docker.au-team.irpo" /etc/nginx/sites-available.d/reverse-proxy.conf \
&& echo "[OK] docker.au-team.irpo configured" \
|| { echo "[ERROR] docker.au-team.irpo missing"; exit 1; }

grep -q "proxy_pass http://172.16.2.2:8080" /etc/nginx/sites-available.d/reverse-proxy.conf \
&& echo "[OK] BR-SRV proxy configured" \
|| { echo "[ERROR] BR-SRV proxy missing"; exit 1; }

grep -q "auth_basic_user_file /etc/nginx/.htpasswd" /etc/nginx/sites-available.d/reverse-proxy.conf \
&& echo "[OK] web authentication configured" \
|| { echo "[ERROR] web authentication missing"; exit 1; }

nginx -t >/dev/null 2>&1 \
&& echo "[OK] nginx config valid" \
|| { echo "[ERROR] nginx config invalid"; exit 1; }

echo
echo "=== M2 ISP DONE ==="
