#!/bin/bash

echo "===== MODULE 1: ISP ====="

hostnamectl set-hostname isp

timedatectl set-timezone Europe/Moscow

cat > /etc/sysconfig/network <<EOF
HOSTNAME=isp
EOF

exec bash

iptables -t nat -A POSTROUTING -s 172.16.1.0/28 -o ens3 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 172.16.2.0/28 -o ens3 -j MASQUERADE

iptables-save > /etc/sysconfig/iptables

systemctl enable --now iptables.service

echo "===== ISP DONE ====="
hostname
iptables -t nat -L -n -v
