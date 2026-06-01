#!/bin/bash

echo "===== MODULE 1: HQ-RTR CONFIG FROM ISP ====="

RTR_IP="172.16.1.2"
RTR_USER="net_admin"
RTR_PASS="P@ssw0rd"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "[+] sshpass не найден, устанавливаю..."
    apt-get update
    apt-get install -y sshpass
fi

if ! command -v sshpass >/dev/null 2>&1; then
    echo "[-] sshpass так и не установился"
    exit 1
fi

echo "[+] Подключаюсь к HQ-RTR $RTR_IP"

sshpass -p "$RTR_PASS" ssh -tt \
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
"$RTR_USER@$RTR_IP" << 'EOF'

enable
configure terminal
hostname hq-rtr
ip domain-name au-team.irpo
write memory
exit
EOF
echo "===== HQ-RTR DONE ====="
