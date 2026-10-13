#!/bin/bash
# =============================================================================
#  restic - file level backup to Backblaze B2
#
#  Litestream only covers SQLite databases. Everything else (uploaded files,
#  config) is handled here.
#
#  Everything is ENCRYPTED ON THIS MACHINE before upload (client-side AES-256),
#  so Backblaze only ever stores unreadable blobs. That means the provider
#  can be used for backups without handing them readable data.
# =============================================================================
set -uo pipefail

say() { echo "[restic] $*"; }

LOCK=/tmp/restic-backup.lock
exec 9>"$LOCK" || { say "cannot create lock"; exit 0; }
if ! flock -n 9; then
    say "another backup is already running - skipping this cycle"
    exit 0
fi

export RESTIC_REPOSITORY="s3:${B2_ENDPOINT}/${B2_BUCKET}/files"
export AWS_ACCESS_KEY_ID="${B2_KEY_ID:-}"
export AWS_SECRET_ACCESS_KEY="${B2_APP_KEY:-}"
export RESTIC_CACHE_DIR="/tmp/restic-cache"
export RESTIC_PASSWORD="${RESTIC_PASSWORD:-}"

if [ -z "$RESTIC_PASSWORD" ] || [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$B2_ENDPOINT" ]; then
    say "SKIPPED - RESTIC_PASSWORD or B2 credentials missing"
    exit 0
fi

# ---- first run: create the repository -------------------------------------
if ! restic snapshots --json >/dev/null 2>&1; then
    say "repository does not exist yet - running 'restic init'"
    if ! restic init; then
        say "FAILED to init - file backups stay OFF until this works"
        exit 1
    fi
    say "repository created"
fi

# ---- what gets backed up --------------------------------------------------
TARGETS=()
# Restic deliberately covers Vaultwarden's folder even though litestream does
# NOT replicate its database - see litestream/litestream.yml for why. Restic
# only ever writes a copy, so it can never roll the live vault backwards.
for D in /app/data/pocketbase /app/data/openlist /app/data/chhoto /app/data/vaultwarden; do
    [ -d "$D" ] && TARGETS+=("$D")
done

if [ ${#TARGETS[@]} -eq 0 ]; then
    say "nothing to back up yet"
    exit 0
fi

say "backing up: ${TARGETS[*]}"
if restic backup "${TARGETS[@]}" \
       --tag private-stack \
       --exclude-caches \
       --exclude '*.tmp' \
       --exclude '*.lock' \
       --verbose=1; then
    say "backup OK"
    # keep a rolling window, then prune
    restic forget --tag private-stack \
                  --keep-hourly 6 --keep-daily 7 --keep-weekly 4 --keep-monthly 3 \
                  --prune
    say "old snapshots pruned"
else
    say "backup FAILED - previous snapshots are still intact"
    exit 1
fi