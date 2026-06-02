#!/bin/bash

echo "===== MODULE 2: RTR CONFIG FROM ISP EXPECT ====="

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
    "password:" {
        send "$RTR_PASS\r"
    }
}

expect "ecorouter>"
send "enable\r"

expect "#"
send "configure\r"

expect "#"
send "ip domain-name au-team.irpo\r"
send "ip name-server 10.10.100.2\r"
send "ntp timezone utc+3\r"
send "ntp server 172.16.1.1\r"

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
    "password:" {
        send "$RTR_PASS\r"
    }
}

expect "ecorouter>"
send "enable\r"

expect "#"
send "configure\r"

expect "#"
send "ip domain-name au-team.irpo\r"
send "ip name-server 10.10.100.2\r"
send "ntp timezone utc+3\r"
send "ntp server 172.16.2.1\r"

send "end\r"
expect "#"
send "write memory\r"
expect "#"
send "exit\r"
expect eof
EOF

echo "===== BR-RTR DONE ====="
echo "===== ALL RTR CONFIG DONE ====="
