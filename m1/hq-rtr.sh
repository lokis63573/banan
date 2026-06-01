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

hostname hq-rtr
ip domain-name au-team.irpo
ip name-server 10.10.100.2
ntp timezone utc+3
ip route 0.0.0.0/0 172.16.1.1

interface tunnel.0
ip address 10.10.10.1/30
ip tunnel 172.16.1.2 172.16.2.2 mode gre
exit

router ospf 1
ospf router-id 10.10.10.1
passive-interface default
no passive-interface tunnel.0
network 10.10.10.0/30 area 0
network 10.10.100.0/27 area 0
network 10.10.200.0/28 area 0
network 10.10.30.0/29 area 0
exit

interface tunnel.0
ip ospf authentication message-digest
ip ospf message-digest-key 1 md5 P@ssw0rd
exit

interface isp
ip nat outside
exit

interface vl100
ip nat inside
exit

interface vl200
ip nat inside
exit

interface vl999
ip nat inside
exit

ip nat pool VLAN100 10.10.100.1-10.10.100.30
ip nat pool VLAN200 10.10.200.1-10.10.200.14
ip nat pool VLAN999 10.10.30.1-10.10.30.6

ip nat source dynamic inside-to-outside pool VLAN100 overload interface isp
ip nat source dynamic inside-to-outside pool VLAN200 overload interface isp
ip nat source dynamic inside-to-outside pool VLAN999 overload interface isp

write memory
exit
EOF

echo "===== HQ-RTR DONE ====="
