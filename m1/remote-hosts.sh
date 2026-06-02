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

    sshpass -p "$ROOT_PASS" ssh -tt \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$ROOT_USER@$IP" << EOF
hostnamectl set-hostname $HOSTNAME

if grep -q '^HOSTNAME=' /etc/sysconfig/network; then
    sed -i 's/^HOSTNAME=.*/HOSTNAME=$HOSTNAME/' /etc/sysconfig/network
else
    echo 'HOSTNAME=$HOSTNAME' >> /etc/sysconfig/network
fi

hostname
grep '^HOSTNAME=' /etc/sysconfig/network
exit
EOF
}

run_br_srv() {
    IP="$1"
    HOSTNAME="$2"

    echo "===== CONFIG BR-SRV $HOSTNAME ($IP) ====="

    sshpass -p "$BR_SRV_PASS" ssh -tt \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$BR_SRV_USER@$IP" << EOF
su -
$BR_SRV_PASS

hostnamectl set-hostname $HOSTNAME

if grep -q '^HOSTNAME=' /etc/sysconfig/network; then
    sed -i 's/^HOSTNAME=.*/HOSTNAME=$HOSTNAME/' /etc/sysconfig/network
else
    echo 'HOSTNAME=$HOSTNAME' >> /etc/sysconfig/network
fi

grep -q '^Banner /etc/openssh/banner' /etc/openssh/sshd_config || echo 'Banner /etc/openssh/banner' >> /etc/openssh/sshd_config

echo "Authorized access only" > /etc/openssh/banner
systemctl restart sshd

hostname
grep '^HOSTNAME=' /etc/sysconfig/network
grep '^Banner' /etc/openssh/sshd_config
cat /etc/openssh/banner

exit
exit
EOF
}

run_root_host "10.10.200.2" "hq-cli.au-team.irpo"
run_br_srv "10.20.20.2" "br-srv.au-team.irpo"
run_root_host "10.20.30.2" "br-cli.au-team.irpo"

echo "===== REMOTE HOST CONFIG DONE ====="
