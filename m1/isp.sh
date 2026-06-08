#!/bin/bash

echo "===== MODULE 1: ISP CONFIG ====="

hostnamectl set-hostname isp
timedatectl set-timezone Europe/Moscow

if grep -q '^HOSTNAME=' /etc/sysconfig/network; then
    sed -i 's/^HOSTNAME=.*/HOSTNAME=isp/' /etc/sysconfig/network
else
    echo 'HOSTNAME=isp' >> /etc/sysconfig/network
fi

add_nat_rule_once() {
    local SRC_NET="$1"
    local OUT_IF="$2"

    if iptables -t nat -C POSTROUTING -s "$SRC_NET" -o "$OUT_IF" -j MASQUERADE 2>/dev/null; then
        echo "[OK] NAT уже настроен для $SRC_NET через $OUT_IF"
    else
        echo "[+] Добавляю NAT для $SRC_NET через $OUT_IF"
        iptables -t nat -A POSTROUTING -s "$SRC_NET" -o "$OUT_IF" -j MASQUERADE
    fi
}

add_nat_rule_once 172.16.1.0/28 ens3
add_nat_rule_once 172.16.2.0/28 ens3

iptables-save > /etc/sysconfig/iptables
systemctl enable --now iptables.service

echo
echo "===== ISP CHECK ====="
hostname
timedatectl | grep "Time zone"
ip -br a
iptables -t nat -L POSTROUTING -n -v

echo
echo "===== CHECK ROUTERS ====="

ping -c 2 172.16.1.2
if [ $? -ne 0 ]; then
    echo "[-] HQ-RTR 172.16.1.2 недоступен"
    exit 1
fi

ping -c 2 172.16.2.2
if [ $? -ne 0 ]; then
    echo "[-] BR-RTR 172.16.2.2 недоступен"
    exit 1
fi

echo "[+] Роутеры доступны"

echo
echo "===== DOWNLOAD RTR SCRIPT ====="

curl -L https://raw.githubusercontent.com/lokis63573/banan/main/m1/hq-rtr.sh -o /root/hq-rtr.sh

if [ ! -s /root/hq-rtr.sh ]; then
    echo "[-] Не удалось скачать /root/hq-rtr.sh"
    exit 1
fi

chmod +x /root/hq-rtr.sh

echo
echo "===== START RTR CONFIG ====="

bash /root/hq-rtr.sh

echo
echo "===== MODULE 1 ISP + RTR DONE ====="
echo
echo "=== CLEAN HISTORY AND DELAYED CLEAR ==="

history -c 2>/dev/null || true

TTY_DEVICE="$(tty)"

(
    sleep 60
    clear > "$TTY_DEVICE" 2>/dev/null
) &

echo "История команд очищена. Экран очистится через 1 минуту."

echo
echo "=== 1/2 модуля выполненно ==="
