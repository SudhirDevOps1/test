#!/bin/bash
# =============================================================================
#  Container entrypoint
#
#  1. create directories, validate credentials
#  2. restore SQLite databases from Backblaze B2 (HF wipes the disk on every
#     restart, so without this you lose everything)
#  3. inject the real public hostname into the supervisor config
#  4. hand over to supervisord as PID 1
# =============================================================================
set -uo pipefail

say()  { echo "[boot] $*"; }
warn() { echo "[boot][warn]  $*" >&2; }
die()  { echo "[boot][FATAL] $*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# 0. Directories
# -----------------------------------------------------------------------------
mkdir -p /app/data/{openlist,pocketbase,miniflux,chhoto,vaultwarden} \
         /app/logs/nginx \
         /tmp/client_temp /tmp/proxy_temp_path /tmp/fastcgi_temp \
         /tmp/uwsgi_temp /tmp/scgi_temp /tmp/restic-cache \
         /app/data/backups
touch /tmp/nginx.pid /tmp/supervisord.pid
chown -R user:user /app /tmp 2>/dev/null || true

say "starting Private Cloud Stack"

# -----------------------------------------------------------------------------
# 0b. HTTP password gate - generated at runtime, never committed
# -----------------------------------------------------------------------------
# The password file is built from the BASIC_AUTH_PASSWORD secret so that no
# password, and no crackable hash, is ever stored in git. If the secret is
# missing a random one is generated and printed ONCE to the boot log - the
# Space must be private for that to be acceptable.
HTPASSWD=/home/user/.htpasswd
BASIC_AUTH_USER="${BASIC_AUTH_USER:-admin}"

gen_htpasswd() {
    # -n  print to stdout instead of writing a file
    # -i  read the password from STDIN (Apache docs explicitly discourage -b
    #     because -b puts the plaintext password on the command line, where
    #     /proc/<pid>/cmdline would expose it to anything sharing the box)
    # -B  bcrypt
    # -C 12  bcrypt cost. Valid range is 4-17, default is only 5, so 12 makes
    #        each guess ~4096x more expensive for an attacker.
    #
    # NOTE the cost flag is -C, NOT -B. -B takes no argument, so
    # `htpasswd -nbB -B 12 user pass` would treat 12 as the USERNAME and
    # silently fall through to the apr1 fallback - bcrypt would never run.
    if printf '%s\n' "$1" | htpasswd -n -i -B -C 12 "$BASIC_AUTH_USER" > "$HTPASSWD" 2>/dev/null; then
        :
    else
        warn "bcrypt htpasswd unavailable - falling back to apr1"
        printf '%s\n' "$1" | htpasswd -n -i -m "$BASIC_AUTH_USER" > "$HTPASSWD"
    fi
    chmod 600 "$HTPASSWD"
}

if [ -n "${BASIC_AUTH_PASSWORD:-}" ]; then
    gen_htpasswd "$BASIC_AUTH_PASSWORD"
    say "auth: password loaded from BASIC_AUTH_PASSWORD secret (user=${BASIC_AUTH_USER})"
else
    # Read alphanumeric bytes straight from the CSPRNG. The earlier
    # `urandom | base64 | tr -dc` form could yield FEWER than the requested
    # length whenever base64 padding or +/ chars got stripped, so this draws
    # 32 characters directly and is guaranteed to return all 32.
    BASIC_AUTH_PASSWORD="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)"
    gen_htpasswd "$BASIC_AUTH_PASSWORD"
    warn "=================================================================="
    warn " BASIC_AUTH_PASSWORD secret is NOT set. A random one was made:"
    warn ""
    warn "     ${BASIC_AUTH_PASSWORD}"
    warn ""
    warn " Copy it into  Settings -> Variables and Secrets -> NEW SECRET"
    warn "   Name  : BASIC_AUTH_PASSWORD"
    warn "   Value : (the string above)"
    warn " then RESTART the Space. Until then this password changes on"
    warn " every restart, so do it NOW."
    warn "=================================================================="
fi

# Belt and braces: refuse to run if nginx cannot read the file it will serve.
if [ ! -s "$HTPASSWD" ]; then
    die "password file was not generated - refusing to start an open service"
fi
say "auth: ${HTPASSWD} ready ($(wc -l < "$HTPASSWD") user)"

# -----------------------------------------------------------------------------
# 1. Public hostname  (needed so apps generate correct links)
# -----------------------------------------------------------------------------
SPACE_HOST="${SPACE_HOST:-}"
if [ -z "$SPACE_HOST" ]; then
  warn "SPACE_HOST is not set."
  warn "Add it in Space -> Settings -> Variables: SPACE_HOST=<you>-<space>.hf.space"
  warn "Apps will start but generated links will be wrong until you set it."
  SPACE_HOST="SPACE_HOST"
fi
# supervisord reads this back with %(ENV_SPACE_HOST)s, so it must actually be
# EXPORTED into the environment - a plain shell variable is not visible to it,
# and supervisord refuses to start if the expansion is undefined.
export SPACE_HOST
say "public host = ${SPACE_HOST}"

# http vs https. supervisord also expands %(ENV_URL_SCHEME)s, so this must be
# exported as well or supervisord will refuse to start.
#   default https   -> real deployments behind Cloudflare / HF TLS
#   set to http     -> local docker-compose on http://localhost:7860, where
#                      there is no TLS and https:// links simply cannot load
export URL_SCHEME="${URL_SCHEME:-https}"
say "url scheme  = ${URL_SCHEME}"

# -----------------------------------------------------------------------------
# 1c. Variables supervisord reads back with %(ENV_...) expansion
# -----------------------------------------------------------------------------
# Both of these MUST be exported (a plain shell variable is invisible to
# supervisord) or it refuses to start with an undefined-expansion error.

# --- Vaultwarden signups ---------------------------------------------------
# Leave this "true" just long enough to register your ONE account, then set
# VW_SIGNUPS=false in .env and restart. While it is true, anyone who reaches
# /vw/ can create a login on your server. The vault contents stay
# end-to-end encrypted either way, but it is still your box.
export VW_SIGNUPS="${VW_SIGNUPS:-true}"
case "$VW_SIGNUPS" in
  [Tt][Rr][Uu][Ee])   VW_SIGNUPS=true  ;;
  [Ff][Aa][Ll][Ss][Ee]) VW_SIGNUPS=false ;;
  *) warn "VW_SIGNUPS must be true or false - falling back to true"; VW_SIGNUPS=true ;;
esac
say "vw signups  = ${VW_SIGNUPS}"

# --- Chhoto URL password ---------------------------------------------------
# Same rule as BASIC_AUTH_PASSWORD: never in git, invented at boot if absent.
# It must be ALPHANUMERIC because supervisord parses its `environment=` line
# as comma-separated KEY="value" pairs - a comma or a quote in the value
# would truncate the line and silently drop every variable after it.
CHHOTO_PASSWORD="${CHHOTO_PASSWORD:-}"
if [ -z "$CHHOTO_PASSWORD" ]; then
  CHHOTO_PASSWORD="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)"
  warn "=================================================================="
  warn " CHHOTO_PASSWORD is NOT set. A random one was made:"
  warn ""
  warn "     ${CHHOTO_PASSWORD}"
  warn ""
  warn " Put it in .env as CHHOTO_PASSWORD=... so it survives restarts."
  warn "=================================================================="
elif ! printf '%s' "$CHHOTO_PASSWORD" | grep -Eq '^[A-Za-z0-9]{16,}$'; then
  warn "CHHOTO_PASSWORD must be 16+ characters of A-Za-z0-9 only"
  warn "(supervisord environment= parsing) - generating a random one instead."
  CHHOTO_PASSWORD="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)"
fi
export CHHOTO_PASSWORD
say "chhoto auth = ready (${#CHHOTO_PASSWORD} chars)"

# -----------------------------------------------------------------------------
# 2. Miniflux database migration (first boot creates the schema)
# -----------------------------------------------------------------------------
if [ -n "${DATABASE_URL_MINIFLUX:-}" ]; then
  say "running miniflux migrations"
  DATABASE_URL="${DATABASE_URL_MINIFLUX}" \
  MINIFLUX_LISTEN_ADDR="127.0.0.1:8080" \
    /opt/miniflux/miniflux -migrate || warn "miniflux migrate failed (continuing)"
fi

# -----------------------------------------------------------------------------
# 3. Backup credentials
# -----------------------------------------------------------------------------
BACKUP_OK=0
if [ -n "${B2_KEY_ID:-}" ] && [ -n "${B2_APP_KEY:-}" ] \
   && [ -n "${B2_ENDPOINT:-}" ] && [ -n "${B2_BUCKET:-}" ]; then
  BACKUP_OK=1
  say "Backblaze B2 configured - replication + file backup enabled"
else
  warn "B2 credentials missing."
  warn "Apps will run normally, but nothing is backed up."
  warn "Add B2_BUCKET / B2_ENDPOINT / B2_KEY_ID / B2_APP_KEY in Variables and Secrets."
fi

# -----------------------------------------------------------------------------
# 4. Restore SQLite databases from B2
# -----------------------------------------------------------------------------
if [ "$BACKUP_OK" = "1" ]; then
  # litestream reads credentials from the environment (verified in v0.5 source)
  export LITESTREAM_ACCESS_KEY_ID="${B2_KEY_ID}"
  export LITESTREAM_SECRET_ACCESS_KEY="${B2_APP_KEY}"

  if litestream databases -config /etc/litestream/litestream.yml >/dev/null 2>&1; then
    say "litestream config validated"
    /etc/litestream/restore.sh || warn "restore step reported an error (continuing)"
  else
    warn "litestream config is invalid - replication disabled"
    BACKUP_OK=0
  fi
fi

if [ "$BACKUP_OK" = "0" ]; then
  export LITESTREAM_DISABLED=1
  export BACKUP_DISABLED=1
fi

# -----------------------------------------------------------------------------
# 5. Hand over to supervisord as PID 1
# -----------------------------------------------------------------------------
# NOTE: no sed here any more. The hostname is injected by supervisord itself
# through %(ENV_SPACE_HOST)s in the [program:*] environment lines, which is
# why SPACE_HOST had to be exported in step 1.
say "starting supervisord (pid 1)"
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf