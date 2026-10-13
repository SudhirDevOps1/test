# Private Cloud Stack

> **Apna khud ka cloud — 5 open-source apps, 1 password, ₹0, bina credit card, bina domain.**

Ek hi Docker container, ek hi public port (**7860**), aur sab apps apne-apne
sub-path pe. Backend ke ports bahar se **bilkul** nahi dikhte.

```
http://localhost:7860/         →  password gate + menu
├── /pb/     PocketBase        →  auth + database + files
├── /files/  OpenList          →  30+ cloud storages + WebDAV
├── /rss/    Miniflux          →  RSS reader
├── /vw/     Vaultwarden       →  password manager
└── /s/      Chhoto URL        →  URL shortener
```

---

## 📋 Apps

| Path | App | Lang | Stars | Kya karta hai |
|---|---|---|---|---|
| `/pb/` | **PocketBase** | 🐹 Go | 61,388 | Auth + SQLite + file upload + realtime API |
| `/files/` | **OpenList** | 🐹 Go | 25,046 | 30+ cloud storages ek jagah + WebDAV |
| `/rss/` | **Miniflux** | 🐹 Go | 9,793 | RSS reader, single binary |
| `/vw/` | **Vaultwarden** | 🦀 Rust | 68,964 | Password manager (Bitwarden compatible) |
| `/s/` | **Chhoto URL** | 🦀 Rust | 987 | URL shortener, <10 MB RAM |

**Infra andar hi:** nginx (reverse proxy), supervisord (process manager),
litestream (live SQLite replication), restic (encrypted backups).

**~280 MB RAM.** Sab static binaries — **na Node.js, na PHP, na compile.**

---

## 🚀 Quick Start

**Requirements:** [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed.

```powershell
git clone https://github.com/SudhirDevOps1/test.git
cd test\hf-stack
start.bat          # double-click bhi chalega
```

Pehli baar **random password** banega — wo boot log me ek baar dikhega:

```bash
docker logs private-cloud-stack
# ... A random one was made: <TERA_PASSWORD>
```

Verify:

```bash
curl http://localhost:7860/health          # {"status":"ok",...}
```

> `.env` file banana zaroori hai — `hf-stack/.env.example` copy karke values
> bhar do. `.env` **kabhi commit mat karo** (`.gitignore` me hai).

---

## 🔐 Security — "mere alava koi use na kare"

| # | Layer | Kya karta hai |
|---|---|---|
| 1 | **Password git me nahi** | Boot pe runtime bcrypt hash banta hai, repo me kabhi nahi |
| 2 | **Har route band** | `/health` ke alawa sab pe 401 |
| 3 | **Fail-closed** | Hash generate na ho to container **khud exit** — khula service kabhi nahi |
| 4 | **Rate limit** | Password gate pe 3 req/s per IP, 20 connections max |
| 5 | **Single port** | Backends 127.0.0.1 pe, bahar se hit karna impossible |
| 6 | **Security headers** | nosniff, SAMEORIGIN, HSTS, Referrer-Policy |
| 7 | **Non-root** | UID 1000, root nahi |
| 8 | **E2E / encrypted backup** | restic AES-256 se pehle encrypt karke upload |

**Do jaan-boojh ke exceptions:**
- `/health` khula hai (keep-alive pinger ke liye, koi data nahi)
- `/vw/` pe `auth_basic off` — Bitwarden clients HTTP Basic bolte hi nahi.
  Vaultwarden ka **Argon2 master password** hi gate hai, aur data
  **end-to-end encrypted** rehta hai. Sirf browser web-vault chahiye to
  `nginx/conf.d/vaultwarden.conf` me `auth_basic` ON kar do.

---

## 🗂️ Structure

```
hf-stack/
├── Dockerfile                         7 binaries · 5 GitHub + 2 official images
├── docker-compose.yml                 5 named volumes · single port 7860
├── start.bat                          Windows double-click launcher
├── .env.example                       template — .env KABHI commit mat karo
├── nginx/
│   ├── nginx.conf                     1 server block + include (dekh neeche)
│   ├── index.html                     root menu — disk se serve hota hai
│   └── conf.d/
│       ├── pocketbase.conf            /pb/    → 8090
│       ├── openlist.conf              /files/ → 5244
│       ├── miniflux.conf              /rss/   → 8080
│       ├── vaultwarden.conf           /vw/    → 8222 (+308 slash redirect)
│       └── chhoto.conf                /s/     → 4567
├── supervisor/supervisord.conf        8 programs
├── litestream/                        live SQLite → B2  (Vaultwarden kabhi nahi)
├── restic/                            har 6 ghante · client-side AES-256
└── scripts/                           entrypoint + health-check
```

### ⚠️ Do bugs jo fix kiye gaye (doosra developer yahi dohraata hai)

**1. `conf.d` me `server {}` block mat rakho**

nginx har request ko **ek hi server block** me bhejta hai — exact
`server_name` match, phir wildcard, phir `default_server`. `server_name _;`
ek literal naam hai jo kisi Host header se match nahi hota, isliye agar har
conf apna alag `server {}` rakhe, to wo **kabhi select hi nahi hote** — har
request `default_server` pe jaati aur `/pb/`, `/files/` sab **404** dete.

Empirically verify kiya: alag `server{}` layout pe `/pb/` → **404**.
Fix: `include conf.d/*.conf` **server block ke andar**, aur conf files me
sirf `location` blocks.

**2. `return 200` auth_basic bypass karta hai**

nginx `return` ko **rewrite phase** me chalata hai, jo `auth_basic` wale
**access phase** se **pehle** aata hai. Matlab:

```nginx
location = / {
    auth_basic "Private Stack";
    return 200 '<html>...';    # ← ye BINA PASSWORD serve hota hai
}
```

Verify kiya: `return`+auth → **200**, `try_files`+auth → **401**,
`proxy_pass`+auth → **401** (same auth directives).

Fix: root index ko **file** se serve karo (`nginx/index.html`), taaki response
content phase me aaye — auth ke baad.

---

## 💳 Sab Free (koi card nahi)

| Service | Free limit | Card? |
|---|---|---|
| **Docker Desktop** | Personal use | ❌ Nahi |
| **Backblaze B2** | 10 GB + 3× free egress | ❌ Nahi |
| **Neon Postgres** | $0, 1 GB, 100 CU-hrs | ❌ Nahi |
| **GitHub** | public/private repos | ❌ Nahi |

> 🔴 **Card mandatory wale:** Cloudflare R2, Fly.io, Koyeb, Oracle, Heroku
> (free khatam 2022), PlanetScale (free khatam 2024), CockroachDB (free band
> 15 Sep 2026). Isliye sab B2 + Neon use hua hai.

> **Neon ka catch:** 5 min idle pe compute suspend → Miniflux ki pehli request
> 5–10 sec slow. Personal use ke liye theek.

Poora free-tier research: [`FREE-TIERS-2026.md`](FREE-TIERS-2026.md)
(88 services, ✅ official / 🔶 community / 🔴 dead markers ke saath).

---

## 📖 Full Documentation

**Saari detail [`hf-stack/README.md`](hf-stack/README.md) me hai** —
9 security layers, exact env tables, deploy order, troubleshooting,
verified facts source ke saath.

---

## 🧭 Is stack me NAHI ho sakta

| App | Kyun |
|---|---|
| **Memos** | Source me koi base-path config hi nahi |
| **Shiori** | Base-path support nahi |
| **FileBrowser** | Upstream archived |
| **Uptime Kuma** | JavaScript (scope bahar) |

Aur daalne layak (sub-path safe, verified): **Navidrome** (`ND_BASEURL`),
**Forgejo** (`ROOT_URL`).

---

## License

Apna hai, jo karna hai kar. 🧘
