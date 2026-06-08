#!/bin/bash
set -e

echo "===== MODULE 1: ISP CONFIG ====="

hostnamectl set-hostname isp
timedatectl set-timezone Europe/Moscow

if grep -q '^HOSTNAME=' /etc/sysconfig/network 2>/dev/null; then
    sed -i 's/^HOSTNAME=.*/HOSTNAME=isp/' /etc/sysconfig/network
else
    echo 'HOSTNAME=isp' >> /etc/sysconfig/network
fi

# ===== IPTABLES / NAT IDEMPOTENT SETUP =====
echo
 echo "===== IPTABLES CHECK ====="

# Установка iptables, если команды нет
if ! command -v iptables >/dev/null 2>&1; then
    echo "[!] iptables не найден, устанавливаю..."
    apt-get update
    apt-get install -y iptables
else
    echo "[OK] iptables установлен"
fi

# Включаем маршрутизацию IPv4
echo 1 > /proc/sys/net/ipv4/ip_forward
if grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf 2>/dev/null; then
    sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf
else
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
fi
sysctl -p >/dev/null 2>&1 || true

# Определяем WAN интерфейс автоматически, если есть default route.
# Если default route не найден, используем ens3 как в старом скрипте.
WAN_IF="$(ip route | awk '/default/ {print $5; exit}')"
if [ -z "$WAN_IF" ]; then
    WAN_IF="ens3"
fi

echo "[OK] WAN interface: $WAN_IF"

add_nat_rule() {
    local SRC_NET="$1"

    if iptables -t nat -C POSTROUTING -s "$SRC_NET" -o "$WAN_IF" -j MASQUERADE 2>/dev/null; then
        echo "[OK] NAT уже есть для $SRC_NET"
    else
        iptables -t nat -A POSTROUTING -s "$SRC_NET" -o "$WAN_IF" -j MASQUERADE
        echo "[+] Добавлен NAT для $SRC_NET"
    fi
}

add_forward_rule() {
    local SRC_NET="$1"

    if iptables -C FORWARD -s "$SRC_NET" -j ACCEPT 2>/dev/null; then
        echo "[OK] FORWARD уже разрешен для $SRC_NET"
    else
        iptables -A FORWARD -s "$SRC_NET" -j ACCEPT
        echo "[+] Добавлен FORWARD для $SRC_NET"
    fi

    if iptables -C FORWARD -d "$SRC_NET" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
        echo "[OK] ESTABLISHED/RELATED уже разрешен для $SRC_NET"
    else
        iptables -A FORWARD -d "$SRC_NET" -m state --state ESTABLISHED,RELATED -j ACCEPT
        echo "[+] Добавлен ESTABLISHED/RELATED для $SRC_NET"
    fi
}

add_nat_rule "172.16.1.0/28"
add_nat_rule "172.16.2.0/28"

add_forward_rule "172.16.1.0/28"
add_forward_rule "172.16.2.0/28"

mkdir -p /etc/sysconfig
iptables-save > /etc/sysconfig/iptables
systemctl enable iptables.service 2>/dev/null || true
systemctl restart iptables.service 2>/dev/null || systemctl enable --now iptables.service 2>/dev/null || true

# ===== CHECK =====
echo
echo "===== ISP CHECK ====="
hostname
timedatectl | grep "Time zone" || true
ip -br a

echo
echo "===== IPTABLES NAT RULES ====="
iptables -t nat -L POSTROUTING -n -v

echo
echo "===== IPTABLES FORWARD RULES ====="
iptables -L FORWARD -n -v

echo
echo "===== CHECK ROUTERS ====="

ping -c 2 172.16.1.2
if [ $? -ne 0 ]; then
    echo "[-] HQ-RTR 172.16.1.2 недоступен"
    exit 1
fi

ping -c 2 172.16.2.2
if [ $? -ne 0 ]; then
    echo "[-] BR-RTR 172.16.2.2 недоступен"
    exit 1
fi

echo "[+] Роутеры доступны"

echo
echo "===== DOWNLOAD RTR SCRIPT ====="

curl -L https://raw.githubusercontent.com/lokis63573/banan/main/m1/hq-rtr.sh -o /root/hq-rtr.sh

if [ ! -s /root/hq-rtr.sh ]; then
    echo "[-] Не удалось скачать /root/hq-rtr.sh"
    exit 1
fi

chmod +x /root/hq-rtr.sh

echo
echo "===== START RTR CONFIG ====="

bash /root/hq-rtr.sh

echo
echo "===== MODULE 1 ISP + RTR DONE ====="
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
echo "=== 1/2 модуля выполнено ==="
