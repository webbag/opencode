#!/bin/bash
# test_integration.sh — Testy integracyjne dla OpenCode Container
# Uruchomienie: ./tests/test_integration.sh [image_tag]
# Domyślnie: opencode:latest

set -euo pipefail

IMAGE="${1:-opencode:latest}"
WORKDIR="/tmp/opencode-test-$$"
EXIT_CODE=0

RUN="podman run --rm --entrypoint /bin/bash"

cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

mkdir -p "$WORKDIR"
# Użyj podman unshare, by ustawić właściciela na UID/GID 1000 (opencode).
# To pozwala uniknąć chmod 777.
if command -v podman &>/dev/null; then
    podman unshare chown 1000:1000 "$WORKDIR" 2>/dev/null || chmod 777 "$WORKDIR"
else
    chmod 777 "$WORKDIR"
fi

echo "=== Test 1: OpenCode version ==="
$RUN "$IMAGE" -c "opencode --version" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test 2: Git dziala ==="
$RUN "$IMAGE" -c "git --version" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test 3: Python dziala ==="
$RUN "$IMAGE" -c "python3 -c 'print(\"OK\")'" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test 4: Uzytkownik opencode ==="
$RUN "$IMAGE" -c "whoami | grep -q opencode" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test 5: Zapis do wolumenu ==="
podman run --rm --entrypoint /bin/bash -v "$WORKDIR:/home/opencode/workdir:Z" "$IMAGE" \
    -c "echo test > /home/opencode/workdir/test.txt"
grep -q test "$WORKDIR/test.txt" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test 6: Capabilities (--cap-drop=ALL) ==="
podman run --rm --cap-drop=ALL --entrypoint /bin/bash "$IMAGE" \
    -c "cat /proc/self/status | grep CapEff | grep -q 0000000000000000" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test 7: Siec (egress) do API opencode ==="
$RUN "$IMAGE" -c "curl -s -o /dev/null -w '%{http_code}' https://api.opencode.ai | grep -q 200" || { echo "FAIL (moze byc 4xx/5xx bez klucza)"; }

echo "=== Test 8: Siec (egress) do ogolnego internetu ==="
$RUN "$IMAGE" -c "curl -s -o /dev/null -w '%{http_code}' https://example.com | grep -q 200" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test 9: nmap w trybie TCP ==="
$RUN "$IMAGE" -c "nmap -sT -p 443 openai.com 2>&1 | grep -q open" || { echo "FAIL (oczekiwano otwartego portu)"; }

echo "=== Test 10: curl pobiera strone ==="
$RUN "$IMAGE" -c "curl -s https://example.com | grep -q 'Example Domain'" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test 11: wget dziala ==="
$RUN "$IMAGE" -c "wget --version" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test 12: No-new-privileges ==="
podman run --rm --cap-drop=ALL --security-opt=no-new-privileges --entrypoint /bin/bash "$IMAGE" \
    -c "cat /proc/self/status | grep NoNewPrivs | grep -q 1" || { echo "FAIL"; EXIT_CODE=1; }

echo "=== Test 13: Brak nasluchujacych portow ==="
$RUN "$IMAGE" -c "ss -tlnp | grep -q LISTEN" && { echo "FAIL (oczekiwano pusta liste)"; EXIT_CODE=1; } || true

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "=== WSZYSTKIE TESTY ZALICZONE ==="
else
    echo "=== NIEKTORE TESTY NIE ZALICZONE ==="
fi
exit "$EXIT_CODE"
