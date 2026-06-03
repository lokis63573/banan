#!/bin/bash
set -e

echo "=== M2 CLI CONFIG START ==="

ROOT_USER="root"
ROOT_PASS="toor"

HQ_CLI_IP="10.10.200.2"
BR_CLI_IP="10.20.30.2"

if ! command -v expect >/dev/null 2>&1; then
    echo "expect не найден, устанавливаю..."
    apt-get install -y expect || {
        apt-get update || true
        apt-get install -y expect
    }
fi

configure_client() {
    local NAME="$1"
    local IP="$2"
    local NTP="$3"
    local DENY_GROUP="$4"
    local NEED_HQ_SUDO="$5"

    echo
    echo "===== CONFIG $NAME ====="

expect << EOF
set timeout 60

spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${ROOT_USER}@${IP}

expect {
    "yes/no" {
        send "yes\r"
        exp_continue
    }
    "assword:" {
        send "${ROOT_PASS}\r"
    }
}

expect "#"

send "sed -i '/^server /d; /^pool /d' /etc/chrony.conf\r"
expect "#"
send "echo 'server ${NTP} iburst' >> /etc/chrony.conf\r"
expect "#"
send "systemctl restart chronyd\r"
expect "#"

send "id sshuser >/dev/null 2>&1 || useradd -m sshuser\r"
expect "#"
send "echo 'sshuser:P@ssw0rd' | chpasswd\r"
expect "#"
send "usermod -aG wheel sshuser 2>/dev/null || true\r"
expect "#"

send "cat > /etc/sudoers.d/sshuser <<'SUDOEOF'\r"
send "sshuser ALL=(ALL) NOPASSWD:ALL\r"
send "SUDOEOF\r"
expect "#"
send "chmod 440 /etc/sudoers.d/sshuser\r"
expect "#"
send "visudo -cf /etc/sudoers.d/sshuser\r"
expect "#"

send "sed -i '/- : ${DENY_GROUP} : ALL/d' /etc/security/access.conf\r"
expect "#"
send "sed -i '/- : @${DENY_GROUP} : ALL/d' /etc/security/access.conf\r"
expect "#"
send "grep -q '^- : @${DENY_GROUP} : ALL' /etc/security/access.conf || echo '- : @${DENY_GROUP} : ALL' >> /etc/security/access.conf\r"
expect "#"

send "grep -q 'pam_access.so' /etc/pam.d/login || echo 'account required pam_access.so' >> /etc/pam.d/login\r"
expect "#"
send "grep -q 'pam_access.so' /etc/pam.d/sshd || echo 'account required pam_access.so' >> /etc/pam.d/sshd\r"
expect "#"
send "systemctl restart sshd 2>/dev/null || true\r"
expect "#"

send "mkdir -p /mnt/nfs\r"
expect "#"
send "grep -q '^/mnt/nfs ' /etc/auto.master || echo '/mnt/nfs /etc/auto.nfs --timeout=60' >> /etc/auto.master\r"
expect "#"
send "cat > /etc/auto.nfs <<'NFSEOF'\r"
send "shared -fstype=nfs4,rw 10.10.100.2:/raid/nfs\r"
send "NFSEOF\r"
expect "#"
send "systemctl restart autofs\r"
expect "#"

if { "${NEED_HQ_SUDO}" == "yes" } {
    send "cat > /etc/sudoers.d/hq-limited <<'HQEOF'\r"
    send "%hq ALL=(root) NOPASSWD: /bin/cat, /bin/grep, /usr/bin/id\r"
    send "HQEOF\r"
    expect "#"
    send "chmod 440 /etc/sudoers.d/hq-limited\r"
    expect "#"
    send "visudo -cf /etc/sudoers.d/hq-limited\r"
    expect "#"
}

send "exit\r"
expect eof
EOF

    echo "===== $NAME DONE ====="
}

configure_client "HQ-CLI" "$HQ_CLI_IP" "172.16.1.1" "br" "yes"
configure_client "BR-CLI" "$BR_CLI_IP" "172.16.2.1" "hq" "no"

echo
echo "=== M2 CLI CHECK FROM BR-SRV ==="

check_sshuser() {
    local NAME="$1"
    local IP="$2"

    echo
    echo "===== CHECK SSHUSER $NAME ====="

expect << EOF
set timeout 30

spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null sshuser@${IP}

expect {
    "yes/no" {
        send "yes\r"
        exp_continue
    }
    "assword:" {
        send "P@ssw0rd\r"
    }
}

expect {
    "\\$" { send "whoami\r" }
    "#" { send "whoami\r" }
}

expect {
    "sshuser" {
        send "exit\r"
    }
    timeout {
        exit 1
    }
}

expect eof
EOF

    echo "[OK] sshuser login works on $NAME"
}

check_sshuser "HQ-CLI" "$HQ_CLI_IP"
check_sshuser "BR-CLI" "$BR_CLI_IP"

echo
echo "=== MANUAL CHECK COMMANDS ==="
echo "На HQ-CLI:"
echo "grep pam_access /etc/pam.d/login"
echo "grep pam_access /etc/pam.d/sshd"
echo "tail -20 /etc/security/access.conf"
echo "su - hquser1"
echo "su - bruser1"

echo
echo "На BR-CLI:"
echo "grep pam_access /etc/pam.d/login"
echo "grep pam_access /etc/pam.d/sshd"
echo "tail -20 /etc/security/access.conf"
echo "su - bruser1"
echo "su - hquser1"

echo
echo "=== M2 CLI CONFIG DONE ==="
