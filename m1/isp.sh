#!/bin/bash

echo "===== MODULE 1: ISP CONFIG ====="

hostnamectl set-hostname isp
timedatectl set-timezone Europe/Moscow

if grep -q '^HOSTNAME=' /etc/sysconfig/network; then
    sed -i 's/^HOSTNAME=.*/HOSTNAME=isp/' /etc/sysconfig/network
else
    echo 'HOSTNAME=isp' >> /etc/sysconfig/network
fi

iptables -t nat -A POSTROUTING -s 172.16.1.0/28 -o ens3 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 172.16.2.0/28 -o ens3 -j MASQUERADE

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

curl -L https://raw.githubusercontent.com/lokis63573/banan/main/m1/rtrs.sh -o /root/rtrs.sh

if [ ! -s /root/rtrs.sh ]; then
    echo "[-] Не удалось скачать /root/rtrs.sh"
    exit 1
fi

chmod +x /root/rtrs.sh

echo
echo "===== START RTR CONFIG ====="

bash /root/rtrs.sh

echo
echo "===== MODULE 1 ISP + RTR DONE ====="
