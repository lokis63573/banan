#!/bin/bash
set -e

echo "=== M3 TASK 1: IMPORT USERS AS FirstName.LastName ==="

CSV="/mnt/sr0/Users.csv"

mkdir -p /mnt/sr0

if [ ! -f "$CSV" ]; then
    mount /dev/sr0 /mnt/sr0 2>/dev/null || true
fi

if [ ! -f "$CSV" ]; then
    echo "[ERROR] Users.csv not found: $CSV"
    exit 1
fi

samba-tool domain info 127.0.0.1 | grep -q "Domain.*au-team.irpo" \
&& echo "[OK] Samba domain au-team.irpo found" \
|| { echo "[ERROR] Samba domain au-team.irpo not found"; exit 1; }

CSV_COUNT=$(( $(wc -l < "$CSV") - 1 ))
echo "[INFO] Users in CSV: $CSV_COUNT"

CREATED=0
SKIPPED=0
ERRORS=0

tail -n +2 "$CSV" | while IFS=';' read -r firstname lastname role phone dep street zip city country password
do
    [ -z "$firstname" ] && continue
    [ -z "$lastname" ] && continue
    [ -z "$password" ] && password="P@ssw0rd1"

    USERNAME="${firstname}.${lastname}"

    if samba-tool user show "$USERNAME" >/dev/null 2>&1; then
        echo "[SKIP] $USERNAME"
        continue
    fi

    if samba-tool user create "$USERNAME" "$password" \
        --given-name="$firstname" \
        --surname="$lastname"; then
        echo "[OK] $USERNAME"
    else
        echo "[ERROR] $USERNAME"
    fi
done

echo
echo "=== CHECK ==="
samba-tool user show Malachi.Alexander >/dev/null 2>&1 && echo "[OK] Malachi.Alexander"
samba-tool user show Stuart.York >/dev/null 2>&1 && echo "[OK] Stuart.York"

echo
echo "На HQ-CLI проверка:"
echo "id Malachi.Alexander"
echo "su - Malachi.Alexander"
echo "Пароль: P@ssw0rd1"

echo
echo "=== IMPORT DONE ==="
