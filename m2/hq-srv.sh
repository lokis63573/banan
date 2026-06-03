#!/bin/bash
set -e

echo "=== M2 HQ-SRV START ==="

echo "[1] Настройка NFS"

mkdir -p /raid/nfs
chmod 777 /raid/nfs

sed -i 's#(rw,sync,no_root_squash)#(rw,sync,no_subtree_check,no_root_squash)#g' /etc/exports

exportfs -ra
exportfs -v
systemctl restart nfs-server

echo "[2] Монтирование Additional.iso"

mkdir -p /mnt/sr0 /mnt/sr1

mountpoint -q /mnt/sr0 || mount /dev/sr0 /mnt/sr0 2>/dev/null || true
mountpoint -q /mnt/sr1 || mount /dev/sr1 /mnt/sr1 2>/dev/null || true

if [ -f /mnt/sr0/web/index.php ]; then
    WEB_SRC="/mnt/sr0/web"
elif [ -f /mnt/sr1/web/index.php ]; then
    WEB_SRC="/mnt/sr1/web"
else
    echo "[ERROR] Не найден web/index.php на /mnt/sr0 или /mnt/sr1"
    exit 1
fi

echo "[OK] WEB_SRC=$WEB_SRC"

echo "[3] Установка PHP-модулей"

apt-get update
apt-get install -y apache2-mod_php8.2 php8.2-mysqlnd-mysqli

a2dismod httpd-worker || true
a2enmod httpd-prefork || true

echo "[4] Настройка web-приложения"

cp "$WEB_SRC/index.php" /var/www/html/

if [ -f "$WEB_SRC/logo.png" ]; then
    cp "$WEB_SRC/logo.png" /var/www/html/
fi

sed -i 's/$username = "user";/$username = "web";/' /var/www/html/index.php
sed -i 's/$password = "password";/$password = "P@ssw0rd";/' /var/www/html/index.php
sed -i 's/$dbname = "db";/$dbname = "webdb";/' /var/www/html/index.php

mysql -e "CREATE DATABASE IF NOT EXISTS webdb;"
mysql -e "CREATE USER IF NOT EXISTS 'web'@'localhost' IDENTIFIED BY 'P@ssw0rd';"
mysql -e "GRANT ALL PRIVILEGES ON webdb.* TO 'web'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

if [ -f "$WEB_SRC/dump.sql" ]; then
    mysql webdb < "$WEB_SRC/dump.sql"
fi

systemctl restart mariadb
systemctl restart httpd2

echo "[5] Настройка Chrony"

sed -i '/^server /d; /^pool /d' /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo
echo "=== M2 HQ-SRV CHECK ==="

cat /proc/mdstat | grep -q "md0" \
&& echo "[OK] RAID md0 exists" \
|| { echo "[ERROR] RAID md0 missing"; exit 1; }

df -h | grep -q "/raid" \
&& echo "[OK] /raid mounted" \
|| { echo "[ERROR] /raid not mounted"; exit 1; }

test -d /raid/nfs \
&& echo "[OK] /raid/nfs exists" \
|| { echo "[ERROR] /raid/nfs missing"; exit 1; }

exportfs -v | grep -q "/raid/nfs" \
&& echo "[OK] /raid/nfs exported" \
|| { echo "[ERROR] /raid/nfs not exported"; exit 1; }

systemctl is-active --quiet nfs-server \
&& echo "[OK] nfs-server active" \
|| { echo "[ERROR] nfs-server not active"; exit 1; }

systemctl is-active --quiet httpd2 \
&& echo "[OK] httpd2 active" \
|| { echo "[ERROR] httpd2 not active"; exit 1; }

systemctl is-active --quiet mariadb \
&& echo "[OK] mariadb active" \
|| { echo "[ERROR] mariadb not active"; exit 1; }

systemctl is-active --quiet chronyd \
&& echo "[OK] chronyd active" \
|| { echo "[ERROR] chronyd not active"; exit 1; }

grep -q "server 172.16.1.1 iburst" /etc/chrony.conf \
&& echo "[OK] chrony server configured" \
|| { echo "[ERROR] chrony server missing"; exit 1; }

test -f /var/www/html/index.php \
&& echo "[OK] index.php exists" \
|| { echo "[ERROR] index.php missing"; exit 1; }

grep -q '$username = "web";' /var/www/html/index.php \
&& echo "[OK] web username configured" \
|| { echo "[ERROR] web username incorrect"; exit 1; }

grep -q '$password = "P@ssw0rd";' /var/www/html/index.php \
&& echo "[OK] web password configured" \
|| { echo "[ERROR] web password incorrect"; exit 1; }

grep -q '$dbname = "webdb";' /var/www/html/index.php \
&& echo "[OK] webdb configured" \
|| { echo "[ERROR] webdb incorrect"; exit 1; }

mysql -e "SHOW DATABASES;" | grep -q "webdb" \
&& echo "[OK] webdb exists" \
|| { echo "[ERROR] webdb missing"; exit 1; }

mysql webdb -e "SHOW TABLES;" | grep -q "employees" \
&& echo "[OK] employees table exists" \
|| echo "[WARN] employees table not found"

php -m | grep -Eq "mysqli|mysqlnd" \
&& echo "[OK] PHP mysql module detected" \
|| { echo "[ERROR] PHP mysql module missing"; exit 1; }

curl -s http://localhost | grep -Eq "html|DOCTYPE|сотрудник|студент|Access forbidden" \
&& echo "[OK] Apache responds" \
|| { echo "[ERROR] Apache does not respond"; exit 1; }

echo
echo "=== MANUAL CHECK COMMANDS ==="
echo "cat /proc/mdstat"
echo "df -h | grep /raid"
echo "exportfs -v"
echo "cat /etc/exports"
echo "chronyc sources -v"
echo "ls -la /var/www/html/"
echo "mysql webdb -e 'SHOW TABLES;'"
echo "curl http://localhost"

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
echo "=== M2 HQ-SRV DONE ==="
