#!/bin/bash
set -e

echo "=== M2 ISP START ==="

chronyc makestep || true
systemctl restart chronyd

printf "WEB:$(openssl passwd -apr1 'P@ssw0rd')\n" > /etc/nginx/.htpasswd
chmod 644 /etc/nginx/.htpasswd

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

nginx -t
systemctl restart nginx

echo "=== M2 ISP DONE ==="
