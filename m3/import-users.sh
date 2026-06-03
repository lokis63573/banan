#!/bin/bash
set -e

echo "=== M3 TASK 1: IMPORT USERS TO SAMBA DOMAIN ==="

CSV="/mnt/sr0/Users.csv"

mkdir -p /mnt/sr0

if [ ! -f "$CSV" ]; then
mount /dev/sr0 /mnt/sr0 2>/dev/null || true
fi

if [ ! -f "$CSV" ]; then
echo "[ERROR] Users.csv not found"
exit 1
fi

echo "[OK] Users.csv found"

samba-tool domain info 127.0.0.1 >/dev/null

echo "[OK] Samba domain available"

CSV_USERS=$(( $(wc -l < "$CSV") - 1 ))

echo "[INFO] Users in CSV: $CSV_USERS"

CREATED=0
SKIPPED=0
ERRORS=0

tail -n +2 "$CSV" | while IFS=';' read -r firstname lastname role phone dep street zip city country password
do
[ -z "$firstname" ] && continue
[ -z "$lastname" ] && continue

```
USERNAME="${firstname}.${lastname}"

if samba-tool user list | grep -Fxq "$USERNAME"; then

    samba-tool user setpassword "$USERNAME" \
        --newpassword='P@ssw0rd1' \
        --must-change-at-next-login=no >/dev/null 2>&1

    echo "[SKIP] $USERNAME already exists (password updated)"
    continue
fi

if samba-tool user create "$USERNAME" "P@ssw0rd1" \
    --given-name="$firstname" \
    --surname="$lastname"; then

    samba-tool user setpassword "$USERNAME" \
        --newpassword='P@ssw0rd1' \
        --must-change-at-next-login=no >/dev/null 2>&1

    echo "[OK] Created: $USERNAME"
else
    echo "[ERROR] Failed: $USERNAME"
fi
```

done

echo
echo "=== CONTROL CHECK ==="

for USER in 
Malachi.Alexander 
Nelle.Alford 
Meredith.Arnold 
Stuart.York
do
if samba-tool user list | grep -Fxq "$USER"; then
echo "[OK] $USER exists"
else
echo "[WARN] $USER not found"
fi
done

echo
echo "=== LOGIN TEST ==="
echo "Username: Malachi.Alexander"
echo "Password: P@ssw0rd1"

echo
echo "=== M3 TASK 1 DONE ==="
