# =============================================================================
#  Private Cloud Stack
#
#  Apps inside (all sub-path capable):
#    /pb/    PocketBase   (Go)     backend + auth + sqlite
#    /files/ OpenList     (Go)     cloud storage aggregator + WebDAV
#    /rss/   Miniflux     (Go)     RSS reader
#    /vw/    Vaultwarden  (Rust)   password manager
#    /s/     Chhoto URL   (Rust)   URL shortener
#
#  BASE IMAGE IS debian:trixie-slim, NOT ubuntu:22.04.
#  The official Vaultwarden binary is linked against glibc 2.41 (Debian 13 /
#  trixie - their own runtime image is debian:trixie-slim). Ubuntu 22.04 ships
#  glibc 2.35, so that binary would refuse to start with
#  "GLIBC_2.36 not found". Matching our base to Vaultwarden's build
#  environment lets us COPY both Rust binaries straight out of their official
#  images, so there is ZERO compilation at build time (a from-source build of
#  Vaultwarden alone costs ~15 minutes). All five Go binaries are static and
#  run happily on any glibc, so the swap costs them nothing.
#
#  Binary sources:
#    PocketBase / OpenList / Miniflux / litestream / restic
#        -> GitHub "latest release" API (resolved at BUILD time, never stale)
#    Vaultwarden / Chhoto URL
#        -> official Docker images; their release tags ship source only
#           (0 assets), so there is nothing to download from GitHub.
# =============================================================================
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/user \
    LITESTREAM_CONFIG=/etc/litestream/litestream.yml

# ---- base packages ---------------------------------------------------------
# NOTE: no Node.js, no PHP, and nothing is compiled here. The five Go
# binaries are static, and the two Rust ones are lifted from their official
# images further down.
#
# apache2-utils is NOT for Apache - we only need its `htpasswd` binary so the
# container can generate the password file at RUNTIME from a Hugging Face
# secret. That way no password (and no usable hash) is ever committed to git.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget tar unzip bzip2 util-linux \
      nginx supervisor git git-lfs jq tzdata sqlite3 \
      apache2-utils \
      libpq5 libmariadb3 openssl \
 && rm -rf /var/lib/apt/lists/*
# ^ libpq5 / libmariadb3 / openssl are for Vaultwarden only: it is shipped
#   compiled with --features sqlite,mysql,postgresql, so the binary carries
#   DT_NEEDED entries for libpq and libmariadb even when we only ever use
#   SQLite. Skip these and the dynamic loader will not even start it.

# ---- UID 1000: never root --------------------------------------------------
# A container escape is far more damaging when the process inside is root, so
# the whole stack runs as this unprivileged user (Dockerfile ends with
# `USER user`).
RUN useradd -m -u 1000 -s /bin/bash user

# ---- resolve + download every binary --------------------------------------
# The helper greps the releases/latest JSON for a filename pattern that is
# ANCHORED at the end of the URL, so ".sha256" / ".asc" sidecars never match.
RUN set -eux; \
    mkdir -p /opt/dl /tmp/pkgx; \
    fetch() { \
      repo="$1"; pat="$2"; out="$3"; \
      url="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
             | grep -o "\"browser_download_url\": *\"[^\"]*${pat}\"" \
             | head -1 | cut -d'"' -f4)"; \
      if [ -z "$url" ]; then \
        echo "FATAL: ${repo} has no release asset matching: ${pat}"; exit 1; \
      fi; \
      echo "  ${repo}  ->  ${url}"; \
      curl -fsSL "$url" -o "/opt/dl/${out}"; \
    }; \
    fetch pocketbase/pocketbase   'pocketbase_[0-9.]+_linux_amd64\.zip'    pb.zip; \
    fetch OpenListTeam/OpenList   'openlist-linux-amd64\.tar\.gz'           openlist.tar.gz; \
    fetch miniflux/v2             'miniflux-linux-amd64'                   miniflux.bin; \
    fetch benbjohnson/litestream   'litestream_[0-9.]+_linux_amd64\.tar\.gz' litestream.tar.gz; \
    fetch restic/restic           'restic_[0-9.]+_linux_amd64\.bz2'         restic.bz2

# ---- unpack / install ------------------------------------------------------
RUN set -eux; \
    # PocketBase: the zip already contains a file named "pocketbase"
    mkdir -p /opt/pocketbase && unzip -qo /opt/dl/pb.zip -d /opt/pocketbase; \
    test -x /opt/pocketbase/pocketbase || { echo "FATAL: pocketbase missing"; exit 1; }; \
    # OpenList: tarball holds a binary called "openlist"
    mkdir -p /opt/openlist && tar -xzf /opt/dl/openlist.tar.gz -C /opt/openlist; \
    test -x /opt/openlist/openlist || { echo "FATAL: openlist missing"; exit 1; }; \
    # Miniflux: raw single binary
    mkdir -p /opt/miniflux && cp /opt/dl/miniflux.bin /opt/miniflux/miniflux; \
    # Litestream: tarball holds "litestream"
    tar -xzf /opt/dl/litestream.tar.gz -C /tmp/pkgx && \
      find /tmp/pkgx -type f -name litestream -exec cp {} /usr/local/bin/litestream \; ; \
    # Restic: bzip2 single binary
    bunzip2 -c /opt/dl/restic.bz2 > /usr/local/bin/restic; \
    chmod +x /usr/local/bin/litestream /usr/local/bin/restic \
             /opt/openlist/openlist /opt/miniflux/miniflux; \
    rm -rf /opt/dl /tmp/pkgx; \
    litestream version; restic version

# ---- Rust binaries, lifted from the official images (see header) ----------
# These two projects tag source-only releases, so there is no asset to fetch.
# Their published images are already built, so we take the artefacts from
# there instead of spending 15+ minutes compiling Rust on every rebuild.
COPY --from=vaultwarden/server:1.37.4    /vaultwarden      /opt/vaultwarden/vaultwarden
COPY --from=vaultwarden/server:1.37.4    /web-vault        /web-vault
COPY --from=sintan1729/chhoto-url:7.8.3  /app/chhoto-url   /app/chhoto-url
COPY --from=sintan1729/chhoto-url:7.8.3  /app/frontend     /app/frontend

# ---- directories + ownership ----------------------------------------------
RUN mkdir -p /app/data/{openlist,pocketbase,miniflux,chhoto,vaultwarden} \
             /app/frontend/final \
             /app/logs/nginx \
             /etc/litestream \
             /var/log/nginx /var/lib/nginx \
             /tmp/client_temp /tmp/proxy_temp_path /tmp/fastcgi_temp \
             /tmp/uwsgi_temp /tmp/scgi_temp /tmp/restic-cache \
 && touch /tmp/nginx.pid /tmp/supervisord.pid \
 && chown -R user:user /app /home/user /etc/litestream \
                          /var/log/nginx /var/lib/nginx /tmp

# ---- configs ---------------------------------------------------------------
# NOTE: there is deliberately NO htpasswd file in this repo. It is generated at
# container start from the BASIC_AUTH_PASSWORD secret (see scripts/entrypoint.sh).
# Shipping a password hash in git means anyone who can read the repo can mount
# an offline cracking attack against it - so the hash never leaves the box.
COPY nginx/nginx.conf      /etc/nginx/nginx.conf
COPY nginx/conf.d/         /etc/nginx/conf.d/
COPY supervisor/           /etc/supervisor/conf.d/
COPY litestream/           /etc/litestream/
COPY restic/               /app/restic/
COPY scripts/              /app/scripts/

RUN chmod +x /app/scripts/*.sh /app/restic/*.sh /etc/litestream/*.sh \
             /opt/vaultwarden/vaultwarden /app/chhoto-url \
 && chmod -R a+rX /web-vault /app/frontend \
 && chown -R user:user /app /home/user /etc/litestream

# ---- non-root + single public port ----------------------------------------
USER user
WORKDIR /app
EXPOSE 7860

HEALTHCHECK --interval=5m --timeout=10s --start-period=90s --retries=3 \
  CMD curl -fsS http://127.0.0.1:7860/health || exit 1

ENTRYPOINT ["/app/scripts/entrypoint.sh"]