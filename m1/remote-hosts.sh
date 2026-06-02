#!/bin/bash

echo "===== MODULE 1: REMOTE HOST CONFIG FROM HQ-SRV ====="

SSH_USER="root"
SSH_PASS="toor"

if ! command -v sshpass >/dev/null 2>&1; then
    apt-get update
    apt-get install -y sshpass
fi

run_cli() {
    IP="$1"
    HOSTNAME="$2"

    echo "===== CONFIG CLI $HOSTNAME ($IP) ====="

    sshpass -p "$SSH_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$SSH_USER@$IP" bash -s << EOF
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

run_srv() {
    IP="$1"
    HOSTNAME="$2"

    echo "===== CONFIG SRV $HOSTNAME ($IP) ====="

    sshpass -p "$SSH_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$SSH_USER@$IP" bash -s << EOF
hostnamectl set-hostname $HOSTNAME

if grep -q '^HOSTNAME=' /etc/sysconfig/network; then
    sed -i 's/^HOSTNAME=.*/HOSTNAME=$HOSTNAME/' /etc/sysconfig/network
else
    echo 'HOSTNAME=$HOSTNAME' >> /etc/sysconfig/network
fi

grep -q '^Banner /etc/openssh/banner' /etc/openssh/sshd_config || \
echo 'Banner /etc/openssh/banner' >> /etc/openssh/sshd_config

echo "Authorized access only" > /etc/openssh/banner
systemctl restart sshd

hostname
grep '^HOSTNAME=' /etc/sysconfig/network
grep '^Banner' /etc/openssh/sshd_config
cat /etc/openssh/banner
EOF
}

run_cli "10.10.200.2" "hq-cli.au-team.irpo"
run_srv "10.20.20.2" "br-srv.au-team.irpo"
run_cli "10.20.30.2" "br-cli.au-team.irpo"

echo "===== REMOTE HOST CONFIG DONE ====="
