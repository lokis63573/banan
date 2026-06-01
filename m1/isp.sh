#!/bin/bash

echo "===== MODULE 1: ISP ====="

hostnamectl set-hostname isp

timedatectl set-timezone Europe/Moscow

sed -i 's/^HOSTNAME=.*/HOSTNAME=isp/' /etc/sysconfig/network

iptables -t nat -A POSTROUTING -s 172.16.1.0/28 -o ens3 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 172.16.2.0/28 -o ens3 -j MASQUERADE

iptables-save > /etc/sysconfig/iptables
systemctl enable --now iptables || true

echo "===== ISP DONE ====="
echo
echo "===== HOSTNAME ====="
hostname

echo
echo "===== TIME ====="
timedatectl | grep "Time zone"

echo
echo "===== INTERFACES ====="
ip -br a

echo
echo "===== NAT ====="
iptables -t nat -L -n -v

