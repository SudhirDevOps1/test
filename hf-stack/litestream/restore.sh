#!/bin/bash
# =============================================================================
#  Restore SQLite databases from B2 at container start.
#
#  Hugging Face gives every container a FRESH disk. On a cold start or a
#  rebuild nothing under /app/data exists, so without this step every
#  database, every password and every note would be gone.
#
#  v0.5 syntax:
#      litestream restore -if-replica-exists -config <cfg> <local-path>
#  (there is no -o flag and no s3:// argument any more)
# =============================================================================
set -uo pipefail

CFG=/etc/litestream/litestream.yml

DBS=(
  "/app/data/pocketbase/data.db"
  "/app/data/miniflux/miniflux.db"
  "/app/data/chhoto/urls.sqlite"
  "/app/data/openlist/data/data.db"
)

for DB in "${DBS[@]}"; do
    DIR="$(dirname "$DB")"

    if [ -f "$DB" ]; then
        echo "[restore] $DB already present - skipping"
        continue
    fi

    mkdir -p "$DIR"
    chown -R user:user "$DIR" 2>/dev/null || true

    echo "[restore] $DB not found, pulling from B2 ..."
    if litestream restore -if-replica-exists -config "$CFG" "$DB" 2>/tmp/restore.err; then
        echo "[restore] OK  $DB"
        chown user:user "$DB" 2>/dev/null || true
    else
        # A missing replica is normal on a first deploy - not a crash.
        if grep -qi 'replica does not exist\|no such file\|not found' /tmp/restore.err; then
            echo "[restore] no backup yet for $DB - starting fresh"
        else
            echo "[restore] FAILED for $DB:"
            sed 's/^/[restore]   /' /tmp/restore.err
        fi
    fi
done

exit 0