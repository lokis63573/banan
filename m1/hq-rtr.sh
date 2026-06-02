echo "===== MODULE 1: HQ-RTR + BR-RTR CONFIG FROM ISP EXPECT ====="

RTR_USER="net_admin"
RTR_PASS="P@ssw0rd"

if ! command -v expect >/dev/null 2>&1; then
    echo "[+] expect не найден, устанавливаю..."
    apt-get update
    apt-get install -y expect
fi

if ! command -v expect >/dev/null 2>&1; then
    echo "[-] expect не установился"
    exit 1
fi

echo "===== CONFIG HQ-RTR ====="

expect << EOF
set timeout 30

spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $RTR_USER@172.16.1.2

expect {
    "yes/no" {
        send "yes\r"
        exp_continue
    }
    "Password:" {
        send "$RTR_PASS\r"
    }
}

expect "ecorouter>"
send "enable\r"

expect "#"
send "configure\r"

expect "#"
send "hostname hq-rtr\r"
send "ip domain-name au-team.irpo\r"
send "ip name-server 10.10.100.2\r"
send "ntp timezone utc+3\r"
send "ip route 0.0.0.0/0 172.16.1.1\r"

send "interface tunnel.0\r"
send "ip address 10.10.10.1/30\r"
send "ip tunnel 172.16.1.2 172.16.2.2 mode gre\r"
send "exit\r"

send "router ospf 1\r"
send "ospf router-id 10.10.10.1\r"
send "passive-interface default\r"
send "no passive-interface tunnel.0\r"
send "network 10.10.10.0/30 area 0\r"
send "network 10.10.100.0/27 area 0\r"
send "network 10.10.200.0/28 area 0\r"
send "network 10.10.30.0/29 area 0\r"
send "exit\r"

send "interface tunnel.0\r"
send "ip ospf authentication message-digest\r"
send "ip ospf message-digest-key 1 md5 P@ssw0rd\r"
send "exit\r"

send "interface isp\r"
send "ip nat outside\r"
send "exit\r"

send "interface vl100\r"
send "ip nat inside\r"
send "exit\r"

send "interface vl200\r"
send "ip nat inside\r"
send "exit\r"

send "interface vl999\r"
send "ip nat inside\r"
send "exit\r"

send "ip nat pool VLAN100 10.10.100.1-10.10.100.30\r"
send "ip nat pool VLAN200 10.10.200.1-10.10.200.14\r"
send "ip nat pool VLAN999 10.10.30.1-10.10.30.6\r"

send "ip nat source dynamic inside-to-outside pool VLAN100 overload interface isp\r"
send "ip nat source dynamic inside-to-outside pool VLAN200 overload interface isp\r"
send "ip nat source dynamic inside-to-outside pool VLAN999 overload interface isp\r"

send "end\r"
expect "#"
send "write memory\r"
expect "#"
send "exit\r"
expect eof
EOF

echo "===== HQ-RTR DONE ====="
echo "===== CONFIG BR-RTR ====="

expect << EOF
set timeout 30

spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $RTR_USER@172.16.2.2

expect {
    "yes/no" {
        send "yes\r"
        exp_continue
    }
    "Password:" {
        send "$RTR_PASS\r"
    }
}

expect "ecorouter>"
send "enable\r"

expect "#"
send "configure\r"

expect "#"
send "hostname br-rtr\r"
send "ip name-server 10.10.100.2\r"
send "ip domain-name au-team.irpo\r"
send "ntp timezone utc+3\r"
send "ip route 0.0.0.0/0 172.16.2.1\r"

send "interface tunnel.0\r"
send "ip address 10.10.10.2/30\r"
send "ip tunnel 172.16.2.2 172.16.1.2 mode gre\r"
send "exit\r"

send "router ospf 1\r"
send "ospf router-id 10.10.10.2\r"
send "passive-interface default\r"
send "no passive-interface tunnel.0\r"
send "no passive-interface fw\r"
send "network 10.10.10.0/30 area 0\r"
send "network 10.20.10.0/30 area 0\r"
send "exit\r"

send "interface tunnel.0\r"
send "ip ospf authentication message-digest\r"
send "ip ospf message-digest-key 1 md5 P@ssw0rd\r"
send "exit\r"

send "interface fw\r"
send "ip ospf authentication message-digest\r"
send "ip ospf message-digest-key 1 md5 P@ssw0rd\r"
send "exit\r"

send "interface isp\r"
send "ip nat outside\r"
send "exit\r"

send "interface fw\r"
send "ip nat inside\r"
send "exit\r"

send "ip nat pool VLAN10 10.20.20.1-10.20.20.14\r"
send "ip nat pool VLAN20 10.20.30.1-10.20.30.6\r"
send "ip nat pool RTR-FW 10.20.10.1-10.20.10.2\r"

send "ip nat source dynamic inside-to-outside pool VLAN10 overload interface isp\r"
send "ip nat source dynamic inside-to-outside pool VLAN20 overload interface isp\r"
send "ip nat source dynamic inside-to-outside pool RTR-FW overload interface isp\r"

send "end\r"
expect "#"
send "write memory\r"
expect "#"
send "exit\r"
expect eof
EOF

echo "===== BR-RTR DONE ====="
echo "===== ALL RTR CONFIG DONE ====="
