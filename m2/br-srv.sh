#!/bin/bash
set -e

echo "=== M2 BR-SRV START ==="

echo "[1] Настройка Chrony"

sed -i '/^server /d; /^pool /d' /etc/chrony.conf
echo "server 172.16.2.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "[2] Настройка Samba групп и пользователей"

samba-tool group show hq >/dev/null 2>&1 || samba-tool group add hq
samba-tool group show br >/dev/null 2>&1 || samba-tool group add br

for i in 1 2 3 4 5; do
    samba-tool user show hquser$i >/dev/null 2>&1 || samba-tool user create hquser$i 'P@ssw0rd1'
    samba-tool group addmembers hq hquser$i >/dev/null 2>&1 || true
done

for i in 1 2 3 4 5; do
    samba-tool user show bruser$i >/dev/null 2>&1 || samba-tool user create bruser$i 'P@ssw0rd1'
    samba-tool group addmembers br bruser$i >/dev/null 2>&1 || true
done

echo "[3] Настройка Ansible inventory"

cat > /etc/ansible/hosts <<'EOF'
[hq]
hq-srv ansible_host=10.10.100.2 ansible_port=2026 ansible_user=sshuser ansible_ssh_pass=P@ssw0rd
hq-cli ansible_host=10.10.200.2 ansible_user=sshuser ansible_ssh_pass=P@ssw0rd

[br]
br-cli ansible_host=10.20.30.2 ansible_user=sshuser ansible_ssh_pass=P@ssw0rd

[routers]
hq-rtr ansible_host=172.16.1.2 ansible_user=net_admin ansible_ssh_pass=P@ssw0rd ansible_connection=network_cli ansible_network_os=ios
br-rtr ansible_host=172.16.2.2 ansible_user=net_admin ansible_ssh_pass=P@ssw0rd ansible_connection=network_cli ansible_network_os=ios

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF

echo
echo "=== M2 BR-SRV CHECK ==="

systemctl is-active --quiet chronyd \
&& echo "[OK] chronyd active" \
|| { echo "[ERROR] chronyd not active"; exit 1; }

grep -q "server 172.16.2.1 iburst" /etc/chrony.conf \
&& echo "[OK] chrony server configured" \
|| { echo "[ERROR] chrony server missing"; exit 1; }

chronyc sources | grep -q "172.16.2.1" \
&& echo "[OK] NTP source 172.16.2.1 detected" \
|| echo "[WARN] NTP source 172.16.2.1 not synchronized yet"

systemctl is-active --quiet samba \
&& echo "[OK] samba active" \
|| { echo "[ERROR] samba not active"; exit 1; }

samba-tool domain info 127.0.0.1 | grep -q "Domain.*au-team.irpo" \
&& echo "[OK] domain au-team.irpo exists" \
|| { echo "[ERROR] domain au-team.irpo missing"; exit 1; }

samba-tool group show hq >/dev/null 2>&1 \
&& echo "[OK] group hq exists" \
|| { echo "[ERROR] group hq missing"; exit 1; }

samba-tool group show br >/dev/null 2>&1 \
&& echo "[OK] group br exists" \
|| { echo "[ERROR] group br missing"; exit 1; }

for i in 1 2 3 4 5; do
    samba-tool user show hquser$i >/dev/null 2>&1 \
    && echo "[OK] hquser$i exists" \
    || { echo "[ERROR] hquser$i missing"; exit 1; }
done

for i in 1 2 3 4 5; do
    samba-tool user show bruser$i >/dev/null 2>&1 \
    && echo "[OK] bruser$i exists" \
    || { echo "[ERROR] bruser$i missing"; exit 1; }
done

samba-tool group listmembers hq | grep -q "hquser1" \
&& echo "[OK] hq users added to group" \
|| { echo "[ERROR] hq group members missing"; exit 1; }

samba-tool group listmembers br | grep -q "bruser1" \
&& echo "[OK] br users added to group" \
|| { echo "[ERROR] br group members missing"; exit 1; }

HQ_COUNT=$(samba-tool user list | grep -c "^hquser")
BR_COUNT=$(samba-tool user list | grep -c "^bruser")

echo "[INFO] HQ users count: $HQ_COUNT"
echo "[INFO] BR users count: $BR_COUNT"

[ "$HQ_COUNT" -eq 5 ] \
&& echo "[OK] HQ users count correct" \
|| { echo "[ERROR] HQ users count incorrect"; exit 1; }

[ "$BR_COUNT" -eq 5 ] \
&& echo "[OK] BR users count correct" \
|| { echo "[ERROR] BR users count incorrect"; exit 1; }

grep -q "hq-srv ansible_host=10.10.100.2" /etc/ansible/hosts \
&& echo "[OK] hq-srv in inventory" \
|| { echo "[ERROR] hq-srv missing in inventory"; exit 1; }

grep -q "hq-cli ansible_host=10.10.200.2" /etc/ansible/hosts \
&& echo "[OK] hq-cli in inventory" \
|| { echo "[ERROR] hq-cli missing in inventory"; exit 1; }

grep -q "hq-rtr ansible_host=172.16.1.2" /etc/ansible/hosts \
&& echo "[OK] hq-rtr in inventory" \
|| { echo "[ERROR] hq-rtr missing in inventory"; exit 1; }

grep -q "br-rtr ansible_host=172.16.2.2" /etc/ansible/hosts \
&& echo "[OK] br-rtr in inventory" \
|| { echo "[ERROR] br-rtr missing in inventory"; exit 1; }

grep -q "br-cli ansible_host=10.20.30.2" /etc/ansible/hosts \
&& echo "[OK] br-cli in inventory" \
|| { echo "[ERROR] br-cli missing in inventory"; exit 1; }

docker ps | grep -q "testapp" \
&& echo "[OK] docker testapp running" \
|| echo "[WARN] docker testapp not found"

docker ps | grep -q "db" \
&& echo "[OK] docker db running" \
|| echo "[WARN] docker db not found"

echo
echo "=== MANUAL CHECK COMMANDS ==="
echo "chronyc sources -v"
echo "samba-tool domain info 127.0.0.1"
echo "samba-tool group listmembers hq"
echo "samba-tool group listmembers br"
echo "samba-tool user list"
echo "cat /etc/ansible/hosts"
echo "docker ps"

echo
echo "=== START M2 CLI SCRIPT ==="

if curl -fsSL https://raw.githubusercontent.com/lokis63573/banan/main/m2/cli.sh -o /root/cli.sh; then
    chmod +x /root/cli.sh
    bash /root/cli.sh
else
    echo "[ERROR] Не удалось скачать cli.sh"
    exit 1
fi

echo
echo "=== M2 BR-SRV + CLI DONE ==="
echo
echo "=== START M2 HQ-SRV SCRIPT ==="

if curl -fsSL https://raw.githubusercontent.com/lokis63573/banan/main/m2/hq-srv.sh -o /root/hq-srv.sh; then
    chmod +x /root/hq-srv.sh

    if ! command -v sshpass >/dev/null 2>&1; then
        apt-get install -y sshpass || true
    fi

    sshpass -p 'P@ssw0rd' scp -P 2026 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /root/hq-srv.sh sshuser@10.10.100.2:/tmp/hq-srv.sh

    sshpass -p 'P@ssw0rd' ssh -p 2026 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null sshuser@10.10.100.2 \
        "chmod +x /tmp/hq-srv.sh && sudo bash /tmp/hq-srv.sh"
else
    echo "[ERROR] Не удалось скачать hq-srv.sh"
    exit 1
fi

echo
echo "=== M2 HQ-SRV SCRIPT DONE ==="
echo
echo "=== CLEAN HISTORY AND DELAYED CLEAR ==="

history -c 2>/dev/null || true

TTY_DEVICE="$(tty)"

(
    sleep 60
    clear > "$TTY_DEVICE" 2>/dev/null
) &

echo "История команд очищена. Экран очистится через 1 минуту."

echo
echo "=== 4/4 МОДУЛЯ ВЫПОЛНЕНО ==="
