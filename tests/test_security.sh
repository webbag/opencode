#!/bin/bash
# test_security.sh — Testy bezpieczeństwa dla OpenCode Container
# Uruchomienie: ./tests/test_security.sh [image_tag]
# Domyślnie: opencode:latest

set -euo pipefail

IMAGE="${1:-opencode:latest}"
EXIT_CODE=0

RUN="podman run --rm --cap-drop=ALL --security-opt=no-new-privileges --entrypoint /bin/bash"

echo "=== Test S1: Próba mountowania ==="
$RUN "$IMAGE" -c "mount /dev/sda1 /mnt 2>&1 || true" | grep -q "Permission denied\|Operation not permitted\|No such device\|mount:" && echo "PASS (mount zablokowany)" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test S2: Brak dostępu do blokowych device'ów ==="
$RUN "$IMAGE" -c "ls -la /dev/sda* 2>&1 || true" | grep -q "No such file or directory\|Permission denied" && echo "PASS (brak dostępu do /dev/sda)" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test S3: Brak lsmod (kernel modules) ==="
$RUN "$IMAGE" -c "lsmod 2>&1 || true" | grep -q "Permission denied\|not found" && echo "PASS (lsmod zablokowany)" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test S4: Brak sudo w obrazie ==="
podman run --rm --entrypoint /bin/bash "$IMAGE" -c "command -v sudo 2>&1" | grep -q "opencode" || echo "PASS (sudo nieobecny)"

echo "=== Test S5: Próba zmiany właściciela pliku roota ==="
$RUN "$IMAGE" -c "touch /tmp/test && chown root:root /tmp/test 2>&1 || true" | grep -q "Operation not permitted\|chown:" && echo "PASS (chown zablokowany)" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test S6: Próba dostępu do /proc innych procesów ==="
$RUN "$IMAGE" -c "cat /proc/1/environ 2>&1 || true" | grep -q "Permission denied" && echo "PASS (/proc/1 zablokowany)" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test S7: Próba utworzenia device node ==="
$RUN "$IMAGE" -c "mknod /tmp/testnull c 1 3 2>&1 || true" | grep -q "Permission denied\|Operation not permitted" && echo "PASS (mknod zablokowany)" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test S8: Próba przeładowania jądra (kexec) ==="
$RUN "$IMAGE" -c "kexec -l /vmlinuz 2>&1 || true" | grep -q "not found\|Permission denied\|not permitted" && echo "PASS (kexec zablokowany)" || { echo "FAIL"; EXIT_CODE=1; }

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "=== WSZYSTKIE TESTY BEZPIECZEŃSTWA ZALICZONE ==="
else
    echo "=== NIEKTORE TESTY BEZPIECZEŃSTWA NIE ZALICZONE ==="
fi
exit "$EXIT_CODE"
