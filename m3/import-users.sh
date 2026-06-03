#!/bin/bash
set -e

echo "=== M3 TASK 1: IMPORT USERS TO SAMBA DOMAIN ==="

CSV_SRC="/mnt/sr0/Users.csv"
CSV_WORK="/root/Users.csv"

echo "[1] Проверка Additional.iso"

mkdir -p /mnt/sr0

if [ ! -f "$CSV_SRC" ]; then
    mount /dev/sr0 /mnt/sr0 2>/dev/null || true
fi

if [ ! -f "$CSV_SRC" ]; then
    echo "[ERROR] Не найден файл $CSV_SRC"
    exit 1
fi

echo "[OK] CSV найден: $CSV_SRC"

echo "[2] Копирование CSV"

cp "$CSV_SRC" "$CSV_WORK"

echo "[3] Проверка Samba DC"

samba-tool domain info 127.0.0.1 | grep -q "Domain.*au-team.irpo" \
&& echo "[OK] Домен au-team.irpo найден" \
|| { echo "[ERROR] Домен au-team.irpo не найден"; exit 1; }

echo "[4] Информация о CSV"

echo "[INFO] Количество строк:"
wc -l "$CSV_WORK"

echo "[INFO] Первые строки:"
head -3 "$CSV_WORK"

echo "[5] Импорт пользователей"

IMPORT_COUNT=0
SKIP_COUNT=0
ERROR_COUNT=0

while IFS=';' read -r firstname lastname role phone dep street zip city country password
do
    [ -z "$firstname" ] && continue
    [ "$firstname" = "First Name" ] && continue

    USERNAME="$firstname"

    if samba-tool user show "$USERNAME" >/dev/null 2>&1; then
        echo "[SKIP] $USERNAME уже существует"
        SKIP_COUNT=$((SKIP_COUNT+1))
        continue
    fi

    if samba-tool user create "$USERNAME" "$password" \
        --given-name="$firstname" \
        --surname="$lastname" \
        --department="$dep" \
        --job-title="$role" \
        --telephone-number="$phone" \
        --city="$city" \
        --country="$country" >/dev/null 2>&1; then

        echo "[OK] Создан пользователь: $USERNAME"
        IMPORT_COUNT=$((IMPORT_COUNT+1))
    else
        echo "[ERROR] Не удалось создать пользователя: $USERNAME"
        ERROR_COUNT=$((ERROR_COUNT+1))
    fi

done < "$CSV_WORK"

echo
echo "=== IMPORT SUMMARY ==="
echo "Создано: $IMPORT_COUNT"
echo "Пропущено: $SKIP_COUNT"
echo "Ошибок: $ERROR_COUNT"

echo
echo "[6] Проверка контрольных пользователей"

samba-tool user list | grep -q "^Malachi$" \
&& echo "[OK] Malachi найден" \
|| echo "[WARN] Malachi не найден"

samba-tool user list | grep -q "^Stuart$" \
&& echo "[OK] Stuart найден" \
|| echo "[WARN] Stuart не найден"

echo
echo "=== MANUAL CHECK COMMANDS ==="
echo "samba-tool user list | grep Malachi"
echo "samba-tool user list | grep Stuart"
echo "samba-tool user show Malachi"
echo
echo "На HQ-CLI:"
echo "id Malachi"
echo "su - Malachi"
echo "Пароль: P@ssw0rd1"

echo
echo "=== M3 TASK 1 DONE ==="
