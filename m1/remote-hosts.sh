#!/bin/bash

echo "===== MODULE 1: REMOTE HOST CONFIG FROM HQ-SRV ====="

ROOT_USER="root"
ROOT_PASS="toor"

BR_SRV_USER="sshuser"
BR_SRV_PASS="P@ssw0rd"

if ! command -v sshpass >/dev/null 2>&1; then
    apt-get update
    apt-get install -y sshpass
fi

run_root_host() {
    IP="$1"
    HOSTNAME="$2"

    echo "===== CONFIG ROOT HOST $HOSTNAME ($IP) ====="

    sshpass -p "$ROOT_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$ROOT_USER@$IP" bash -s << EOF
hostnamectl set-hostname $HOSTNAME

if grep -q '^HOSTNAME=' /etc/sysconfig/network; then
    sed -i 's/^HOSTNAME=.*/HOSTNAME=$HOSTNAME/' /etc/sysconfig/network
else
    echo 'HOSTNAME=$HOSTNAME' >> /etc/sysconfig/network
fi

hostname
grep '^HOSTNAME=' /etc/sysconfig/network
EOF
}

run_br_srv() {
    IP="$1"
    HOSTNAME="$2"

    echo "===== CONFIG BR-SRV $HOSTNAME ($IP) ====="

    sshpass -p "$BR_SRV_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$BR_SRV_USER@$IP" bash -s << EOF
echo "$BR_SRV_PASS" | sudo -S hostnamectl set-hostname $HOSTNAME

echo "$BR_SRV_PASS" | sudo -S sh -c "if grep -q '^HOSTNAME=' /etc/sysconfig/network; then sed -i 's/^HOSTNAME=.*/HOSTNAME=$HOSTNAME/' /etc/sysconfig/network; else echo 'HOSTNAME=$HOSTNAME' >> /etc/sysconfig/network; fi"

echo "$BR_SRV_PASS" | sudo -S sh -c "grep -q '^Banner /etc/openssh/banner' /etc/openssh/sshd_config || echo 'Banner /etc/openssh/banner' >> /etc/openssh/sshd_config"

echo "$BR_SRV_PASS" | sudo -S sh -c "echo 'Authorized access only' > /etc/openssh/banner"

echo "$BR_SRV_PASS" | sudo -S systemctl restart sshd

hostname
grep '^HOSTNAME=' /etc/sysconfig/network
grep '^Banner' /etc/openssh/sshd_config
cat /etc/openssh/banner
EOF
}

run_root_host "10.10.200.2" "hq-cli.au-team.irpo"
run_br_srv "10.20.20.2" "br-srv.au-team.irpo"
run_root_host "10.20.30.2" "br-cli.au-team.irpo"

echo "===== REMOTE HOST CONFIG DONE ====="
