#!/bin/bash
set -e

echo "=== M3 TASK 1: IMPORT USERS AS FirstName.LastName ==="

CSV="/mnt/sr0/Users.csv"

mkdir -p /mnt/sr0
[ -f "$CSV" ] || mount /dev/sr0 /mnt/sr0 2>/dev/null || true

if [ ! -f "$CSV" ]; then
    echo "[ERROR] Users.csv not found: $CSV"
    exit 1
fi

samba-tool domain info 127.0.0.1 | grep -q "Domain.*au-team.irpo" \
&& echo "[OK] Samba domain au-team.irpo found" \
|| { echo "[ERROR] Samba domain au-team.irpo not found"; exit 1; }

echo "[INFO] Users in CSV: $(( $(wc -l < "$CSV") - 1 ))"

tail -n +2 "$CSV" | while IFS=';' read -r firstname lastname role phone dep street zip city country password
do
    [ -z "$firstname" ] && continue
    [ -z "$lastname" ] && continue
    [ -z "$password" ] && password="P@ssw0rd1"

    USERNAME="${firstname}.${lastname}"

    if samba-tool user list | grep -Fxq "$USERNAME"; then
        echo "[SKIP] $USERNAME already exists"
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
for USER in "Malachi.Alexander" "Stuart.York" "Alden.Wright"; do
    if samba-tool user list | grep -Fxq "$USER"; then
        echo "[OK] $USER exists"
    else
        echo "[WARN] $USER not found"
    fi
done

echo
echo "=== IMPORT DONE ==="
