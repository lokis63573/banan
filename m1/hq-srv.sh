#!/bin/bash

echo "===== MODULE 1: HQ-SRV BIND PATCH ====="

hostnamectl set-hostname hq-srv.au-team.irpo

if grep -q '^HOSTNAME=' /etc/sysconfig/network; then
    sed -i 's/^HOSTNAME=.*/HOSTNAME=hq-srv.au-team.irpo/' /etc/sysconfig/network
else
    echo 'HOSTNAME=hq-srv.au-team.irpo' >> /etc/sysconfig/network
fi

echo "10.10.100.2/27" > /etc/net/ifaces/ens3/ipv4address
echo "default via 10.10.100.1" > /etc/net/ifaces/ens3/ipv4route

cat > /etc/net/ifaces/ens3/resolv.conf <<EOF
nameserver 10.10.100.2
nameserver 77.88.8.8
EOF

systemctl restart network

echo "===== PATCH /etc/bind/options.conf ====="

sed -i 's/listen-on { 127.0.0.1; };/listen-on { 127.0.0.1; 10.10.100.2; };/' /etc/bind/options.conf
sed -i 's/listen-on-v6 { ::1; };/listen-on-v6 { none; };/' /etc/bind/options.conf
sed -i 's|//forward only;|forward only;|' /etc/bind/options.conf
sed -i 's|//forwarders { };|forwarders { 77.88.8.8; };|' /etc/bind/options.conf
sed -i 's|//allow-query { localnets; };|allow-query { any; };|' /etc/bind/options.conf
sed -i 's|//allow-query-cache { localnets; };|allow-query-cache { any; };|' /etc/bind/options.conf
sed -i 's|//allow-recursion { localnets; };|allow-recursion { any; };|' /etc/bind/options.conf

grep -q '^[[:space:]]*allow-query-cache' /etc/bind/options.conf || \
sed -i '/^};/i\allow-query-cache { any; };' /etc/bind/options.conf

grep -q '^[[:space:]]*allow-recursion' /etc/bind/options.conf || \
sed -i '/^};/i\allow-recursion { any; };' /etc/bind/options.conf

echo "===== PATCH /etc/bind/zone/10.10.in-addr.arpa ====="

sed -i 's/itpo/irpo/g' /etc/bind/zone/10.10.in-addr.arpa
sed -i 's|^@.*IN.*SOA.*|@       IN      SOA     hq-rtr.au-team.irpo. root.au-team.irpo. (|' /etc/bind/zone/10.10.in-addr.arpa

echo "===== PATCH /etc/bind/zone/16.172.in-addr.arpa ====="

sed -i 's/itpo/irpo/g' /etc/bind/zone/16.172.in-addr.arpa
sed -i 's|^@.*IN.*SOA.*|@       IN      SOA     hq-rtr.au-team.irpo. root.au-team.irpo. (|' /etc/bind/zone/16.172.in-addr.arpa

echo "===== PATCH /etc/bind/zone/au-team.irpo.zone ====="

sed -i 's/^web[[:space:]]\+IN[[:space:]]\+A[[:space:]]\+172\.16\.1\.1/web       IN  A   172.16.2.1/' /etc/bind/zone/au-team.irpo.zone
sed -i 's/^docker[[:space:]]\+IN[[:space:]]\+A[[:space:]]\+172\.16\.2\.1/docker    IN  A   172.16.1.1/' /etc/bind/zone/au-team.irpo.zone

echo "===== SSH BANNER ====="

grep -q '^Banner /etc/openssh/banner' /etc/openssh/sshd_config || \
echo 'Banner /etc/openssh/banner' >> /etc/openssh/sshd_config

echo "Authorized access only" > /etc/openssh/banner

systemctl restart sshd

echo "===== CHECK BIND FILES ====="

grep -E 'listen-on|listen-on-v6|forward only|forwarders|allow-query|allow-query-cache|allow-recursion' /etc/bind/options.conf

echo
echo "----- 10.10.in-addr.arpa -----"
grep -E 'SOA|NS|PTR' /etc/bind/zone/10.10.in-addr.arpa

echo
echo "----- 16.172.in-addr.arpa -----"
grep -E 'SOA|NS|PTR' /etc/bind/zone/16.172.in-addr.arpa

echo
echo "----- au-team.irpo.zone web/docker -----"
grep -E '^web|^docker' /etc/bind/zone/au-team.irpo.zone

echo
echo "===== CHECK BIND SYNTAX ====="

named-checkconf
named-checkzone au-team.irpo /etc/bind/zone/au-team.irpo.zone
named-checkzone 10.10.in-addr.arpa /etc/bind/zone/10.10.in-addr.arpa
named-checkzone 16.172.in-addr.arpa /etc/bind/zone/16.172.in-addr.arpa

systemctl enable --now bind.service
systemctl restart bind.service

echo
echo "===== DNS CHECK ====="

dig @10.10.100.2 hq-srv.au-team.irpo +short
dig @10.10.100.2 hq-cli.au-team.irpo +short
dig @10.10.100.2 br-srv.au-team.irpo +short
dig @10.10.100.2 br-cli.au-team.irpo +short
dig @10.10.100.2 web.au-team.irpo +short
dig @10.10.100.2 docker.au-team.irpo +short

echo
echo "===== SSH BANNER CHECK ====="
grep '^Banner' /etc/openssh/sshd_config
cat /etc/openssh/banner

echo
echo "===== DOWNLOAD AND RUN REMOTE HOSTS SCRIPT ====="

curl -L https://raw.githubusercontent.com/lokis63573/banan/main/m1/remote-hosts.sh -o /root/remote-hosts.sh

if [ ! -s /root/remote-hosts.sh ]; then
    echo "[-] Не удалось скачать remote-hosts.sh"
    exit 1
fi

chmod +x /root/remote-hosts.sh
bash /root/remote-hosts.sh

echo
echo "===== HQ-SRV BIND PATCH DONE ====="
echo
echo "=== CLEAN HISTORY AND DELAYED CLEAR ==="

history -c 2>/dev/null || true

TTY_DEVICE="$(tty)"

(
    sleep 60
    clear > "$TTY_DEVICE" 2>/dev/null
) &

echo "История команд очищена. Экран очистится через 1 минуту."
echo "=== 2/2 модуля выполненно ==="
