#!/bin/bash
set -e

echo "=== M3 TASK 1: IMPORT USERS TO SAMBA DOMAIN ==="

CSV_SRC="/mnt/sr0/Users.csv"
CSV_WORK="/root/Users.csv"

echo
echo "=== CHECK ADDITIONAL ISO ==="

mkdir -p /mnt/sr0

if [ ! -f "$CSV_SRC" ]; then
    mount /dev/sr0 /mnt/sr0 2>/dev/null || true
fi

if [ ! -f "$CSV_SRC" ]; then
    echo "[ERROR] Не найден файл $CSV_SRC"
    exit 1
fi

echo "[OK] CSV найден: $CSV_SRC"

echo
echo "=== COPY CSV ==="

cp "$CSV_SRC" "$CSV_WORK"

echo "[OK] CSV скопирован в $CSV_WORK"

echo
echo "=== CHECK SAMBA DOMAIN ==="

samba-tool domain info 127.0.0.1 | grep -q "Domain.*au-team.irpo" \
&& echo "[OK] Домен au-team.irpo найден" \
|| { echo "[ERROR] Домен au-team.irpo не найден"; exit 1; }

echo
echo "=== CSV INFO ==="

echo "[INFO] Количество строк:"
wc -l "$CSV_WORK"

echo
echo "[INFO] Первые 3 строки:"
head -3 "$CSV_WORK"

echo
echo "[INFO] Последние 3 строки:"
tail -3 "$CSV_WORK"

echo
echo "=== IMPORT USERS ==="

IMPORT_COUNT=0
SKIP_COUNT=0
ERROR_COUNT=0

while IFS=';' read -r firstname lastname role phone dep street zip city country password
do
    [ -z "$firstname" ] && continue
    [ "$firstname" = "First Name" ] && continue

    USERNAME="$firstname"

    if samba-tool user show "$USERNAME" >/dev/null 2>&1; then
        echo "[SKIP] $USERNAME already exists"
        SKIP_COUNT=$((SKIP_COUNT+1))
        continue
    fi

    if samba-tool user create "$USERNAME" "$password" \
        --given-name="$firstname" \
        --surname="$lastname"; then

        echo "[OK] Created user: $USERNAME"
        IMPORT_COUNT=$((IMPORT_COUNT+1))
    else
        echo "[ERROR] Failed to create user: $USERNAME"
        ERROR_COUNT=$((ERROR_COUNT+1))
    fi

done < "$CSV_WORK"

echo
echo "=== IMPORT SUMMARY ==="
echo "Created: $IMPORT_COUNT"
echo "Skipped: $SKIP_COUNT"
echo "Errors:  $ERROR_COUNT"

echo
echo "=== CHECK CONTROL USERS ==="

samba-tool user list | grep -q "^Malachi$" \
&& echo "[OK] Malachi exists" \
|| echo "[WARN] Malachi not found"

samba-tool user list | grep -q "^Stuart$" \
&& echo "[OK] Stuart exists" \
|| echo "[WARN] Stuart not found"

samba-tool user list | grep -q "^Alden$" \
&& echo "[OK] Alden exists" \
|| echo "[WARN] Alden not found"

echo
echo "=== USER COUNT ==="

TOTAL_USERS=$(samba-tool user list | wc -l)
CSV_USERS=$(( $(wc -l < "$CSV_WORK") - 1 ))

echo "[INFO] Users in CSV: $CSV_USERS"
echo "[INFO] Users in Samba total: $TOTAL_USERS"

echo
echo "=== MANUAL CHECK COMMANDS ==="
echo "На BR-SRV:"
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
