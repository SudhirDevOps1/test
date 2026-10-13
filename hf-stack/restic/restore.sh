#!/bin/bash
# =============================================================================
#  restic restore - manual recovery
#
#  Run it INSIDE the container (or in a temporary alpine container that has
#  the same env vars). It is not called automatically on purpose: a restore
#  overwrites live data, so it should always be a deliberate action.
#
#      docker exec -it <container> /app/restic/restore.sh
#
#  First, see what is available:
#      restic snapshots
#
#  Restore everything into a scratch directory (SAFEST - nothing is touched):
#      ./restore.sh /tmp/verify
#
#  Restore in place (overwrites current data):
#      ./restore.sh /app/data
# =============================================================================
set -uo pipefail

TARGET="${1:-/tmp/verify}"

export RESTIC_REPOSITORY="s3:${B2_ENDPOINT}/${B2_BUCKET}/files"
export AWS_ACCESS_KEY_ID="${B2_KEY_ID:-}"
export AWS_SECRET_ACCESS_KEY="${B2_APP_KEY:-}"
export RESTIC_CACHE_DIR="/tmp/restic-cache"
export RESTIC_PASSWORD="${RESTIC_PASSWORD:-}"

if [ -z "$RESTIC_PASSWORD" ] || [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo "ERROR: RESTIC_PASSWORD / B2_KEY_ID not set in this environment"
    exit 1
fi

echo "repository : $RESTIC_REPOSITORY"
echo "target     : $TARGET"
echo
echo "available snapshots:"
restic snapshots || { echo "cannot read the repository - aborting"; exit 1; }
echo

mkdir -p "$TARGET"

case "$TARGET" in
  /tmp/*)
    echo "Restoring into a scratch dir (nothing live is touched)..."
    restic restore latest --target "$TARGET" --tag private-stack
    ;;
  *)
    echo "WARNING: restoring OVER live data in $TARGET"
    printf "Type 'yes' to continue: "
    read -r ANS
    [ "$ANS" = "yes" ] || { echo "aborted"; exit 0; }
    restic restore latest --target "$TARGET" --tag private-stack
    ;;
esac

echo
echo "done. verify integrity with:  restic check"