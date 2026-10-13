#!/bin/bash
# =============================================================================
#  Health check for every service in the stack.
#  Safe to run any time. Exits 0 only if everything answers.
# =============================================================================
set -uo pipefail

PASS=0
FAIL=0

check() {
    local name="$1" url="$2"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "401" ]; then
        printf "  OK   %-12s %s (%s)\n" "$name" "$url" "$code"
        PASS=$((PASS+1))
    else
        printf "  FAIL %-12s %s (%s)\n" "$name" "$url" "$code"
        FAIL=$((FAIL+1))
    fi
}

echo "=== Service health ==="
check "nginx"     "http://127.0.0.1:7860/health"
check "pocketbase" "http://127.0.0.1:8090/api/health"
check "openlist"   "http://127.0.0.1:5244/ping"
check "miniflux"   "http://127.0.0.1:8080/"
check "chhoto"     "http://127.0.0.1:4567/"
check "vaultwarden" "http://127.0.0.1:8222/alive"

echo
echo "=== Auth gate (401 = password IS working) ==="
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1:7860/pb/api/health 2>/dev/null || echo "000")
if [ "$code" = "401" ]; then
    echo "  OK   basic auth active on /pb/ (401 as expected)"
    PASS=$((PASS+1))
else
    echo "  WARN /pb/ returned $code - expected 401 if auth is enabled"
fi

echo
echo "=== Backup ==="
if pgrep -f "litestream replicate" >/dev/null 2>&1; then
    echo "  OK   litestream is replicating"
else
    echo "  WARN litestream is NOT running (missing B2 credentials?)"
fi

echo
echo "=== Disk (HF gives 50 GB, ephemeral) ==="
df -h /app 2>/dev/null | tail -1 || echo "  (df unavailable)"

echo
echo "passed: $PASS   failed: $FAIL"
exit $(( FAIL > 0 ? 1 : 0 ))