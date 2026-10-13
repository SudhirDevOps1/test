---
title: Private Cloud Stack
emoji: 🔒
colorFrom: blue
colorTo: purple
sdk: docker
pinned: false
app_port: 7860
---

# 🔒 Private Cloud Stack — 1 HF Space · Sub-path · ₹0 · Bina Card

Ek hi container me **5 self-hosted apps**, sab sub-path pe, ek hi
password ke peeche, **bina credit card**, **bina domain**.

> ⚠️ **Space PRIVATE rakho.** Ye poori security isi baat par tikti hai —
> Nginx ka password gate tabhi kaam karta hai jab repo khud private ho.

---

## 📋 Kya Chal Raha Hai

| Path | App | Lang | Stars | Kya karta hai |
|---|---|---|---|---|
| `/pb/` | **PocketBase** | 🐹 Go | 61,388 | Auth + SQLite DB + file upload + realtime API |
| `/files/` | **OpenList** | 🐹 Go | 25,046 | 30+ cloud storages ek jagah + WebDAV |
| `/rss/` | **Miniflux** | 🐹 Go | 9,793 | RSS reader, single binary |
| `/vw/` | **Vaultwarden** | 🦀 Rust | 68,964 | Password manager (Bitwarden compatible) |
| `/s/` | **Chhoto URL** | 🦀 Rust | 987 | URL shortener, <10 MB RAM |

**RAM ~280 MB of 16 GB (2%).** Sab static binaries — **na Node.js, na PHP, na compile.**

---

## 🔐 SECURITY — "Mere alava koi use na kare"

Ye section sabse zaroori hai. Yahan **9 layers** hain, aur har ek ka kaam alag hai.

### Layer 1 — Password kabhi git me NAHI jaata

Tera password **kisi file me likha hi nahi hai**. Container start hote hi
`htpasswd` usse **bcrypt ($2y$)** se hash karke `/home/user/.htpasswd` banata hai —
sirf RAM/disk pe, kabhi repo me nahi.

```
BASIC_AUTH_PASSWORD (HF Secret)
        │
        ▼  entrypoint.sh  →  htpasswd -nbB
/home/user/.htpasswd   ← sirf hash, password kahin nahi
        │
        ▼  nginx auth_basic
har route 401 deta hai
```

> **Kyun zaroori:** agar hash repo me committed ho, toh koi bhi use **offline
> crack** kar sakta hai jitna chahe. Ab hash container se bahar hi nahi jaata.

### Layer 2 — Har route band hai

```
/health   →  khula  (sirf keep-alive pinger ke liye, koi data nahi)
/pb/  /files/  /rss/  /s/  →  401 UNAUTHORIZED  (auth_basic)
/vw/                    →  apna Vaultwarden gate (neeche dekh)
/*  (root)              →  401 UNAUTHORIZED
```

Root `/` pe bhi password maangta hai.

> **Ek jaan-boojh ka exception:** `/vw/` pe `auth_basic off` hai. Bitwarden
> clients (browser extension, mobile app, CLI) **HTTP Basic bolte hi nahi** —
> agar gate on rakho to wo har API call pe 401 kha kar kabhi connect nahi
> honge. Vaultwarden ke paas apna **Argon2 master password** hai, aur data
> **end-to-end encrypted** rehta hai (server pe ciphertext), to raw HTTP
> access se bhi kuch padh nahi sakta. Sirf web-vault chahiye to
> `nginx/conf.d/vaultwarden.conf` me `auth_basic` ON kar de — double gate,
> par extension/mobile band.

### Layer 3 — Fail-closed: galat setup = service hi nahi chalti

Password file generate na ho to container **khud exit** ho jaata hai:

```bash
[ ! -s "$HTPASSWD" ] && die "refusing to start an open service"
```

> **Kyun zaroori:** agar `htpasswd` kisi wajah se fail ho jaye to nginx
> **bina password ke** sab kuch serve kar deta. Fail-closed ka matlab —
> ya to password hai, ya service chalti hi nahi.

### Layer 4 — Brute force slow

```nginx
limit_req_zone ... zone=perip:10m     rate=10r/s;   # normal browsing
limit_req_zone ... zone=authgate:10m  rate=3r/s;    # password gate
limit_conn_zone ... zone=connlimit:10m;
```
Password gate pe sirf **3 req/s** per IP, burst 10, aur **20 parallel
connections** max. Password guess karne wale ko hazaaron saal lagenge.

### Layer 5 — Sirf port 7860 khula

PocketBase (8090), OpenList (5244), Miniflux (8080), Chhoto URL (4567),
Vaultwarden (8222) — **sab 127.0.0.1 pe**. Bahar se seedha inhe hit karna
**impossible** hai.

### Layer 6 — Security headers

```nginx
X-Content-Type-Options    nosniff
X-Frame-Options           SAMEORIGIN          # clickjacking band
Referrer-Policy           strict-origin-when-cross-origin
Strict-Transport-Security max-age=31536000    # HTTPS force
```

### Layer 7 — Non-root (UID 1000)

Container **root nahi** chalta. HF khud root block karta hai; hamara Dockerfile
`USER user` use karta hai. Container escape mushkil ho jaata hai.

### Layer 8 — Client-side encryption

`restic` backup **AES-256 se pehle encrypt** karke upload karta hai. B2 pe
sirf **unreadable blobs** jaate hain — provider ke employees bhi padh nahi sakte.

### Layer 9 — 🔒 OPTIONAL: IP allowlist (sabse strict)

Agar tu chahta hai ki **bilkul sirf tere IP se** chale — `nginx/nginx.conf`
me commented block hai. Uncomment karke apna IP daal:

```nginx
# nginx/nginx.conf ke server block ke top pe:
allow 203.0.113.7;      # tera IP
deny  all;
```

Apna IP nikal: `curl https://ifconfig.me`

> ⚠️ **Warning:** mobile pe IP badalta rehta hai — tu bhi lock ho jayega.
> Isliye optional hai. Use only if tu fixed IP (home/office) se access karta hai.

---

## 🧂 HF Secrets — Exact Kya Daalna Hai

**Space → Settings → Variables and Secrets → NEW SECRET**

| # | Name | Value kya hai | Zaruri? |
|---|---|---|---|
| 1 | `BASIC_AUTH_PASSWORD` | 32-char random string | ✅ **Pehla kaam yahi** |
| 2 | `CHHOTO_PASSWORD` | 32-char **ALPHANUMERIC** string | ⬜ optional — chhoda to boot pe random ban jaata hai (log me print) |
| 3 | `B2_KEY_ID` | B2 → App Keys → Key ID | backup ke liye |
| 4 | `B2_APP_KEY` | B2 → App Keys → Application Key | backup ke liye |
| 5 | `RESTIC_PASSWORD` | 32-char random string | backup ke liye |
| 6 | `DATABASE_URL_MINIFLUX` | Neon URL + `?sslmode=require` | ✅ `/rss/` ke liye |

> `CHHOTO_PASSWORD` me **sirf `A-Za-z0-9`** aur **16+ characters**. Supervisord
> apni `environment=` line ko comma-separated `KEY="value"` parse karta hai —
> usme comma/quote aate hi **aage ki har variable gir jaati hai** aur app
> config ke bina start ho jaata hai. entrypoint.sh isse validate karke
> galat hone par khud random generate kar deta hai.

**Random string banane ka command:**
```bash
python -c "import secrets;print(secrets.token_urlsafe(32))"
```

## 📊 HF Variables — Non-sensitive

**Settings → Variables and Secrets → NEW VARIABLE**

| # | Name | Value | Zaruri? |
|---|---|---|---|
| 1 | `SPACE_HOST` | `<you>-<space>.hf.space` (ya `localhost:7860`) | ✅ **sabse zaroori** |
| 2 | `URL_SCHEME` | `https` (default) / `http` (local test) | ✅ |
| 3 | `B2_BUCKET` | tera bucket naam | backup ke liye |
| 4 | `B2_ENDPOINT` | `s3.us-west-004.backblazeb2.com` | backup ke liye |
| 5 | `VW_SIGNUPS` | `true` → account banate hi **`false`** | ✅ `/vw/` ke liye |

> ⚠️ **`SPACE_HOST` ke bina** apps start to ho jayenge, par **CSS/JS 404**
> honge → blank pages. Ye ek variable **paancho apps** ke base-path me jaata hai:
>
> | App | Setting | Kahan |
> |---|---|---|
> | PocketBase | `POCKETBASE_BASE_URL` | supervisord → `%(ENV_URL_SCHEME)s://%(ENV_SPACE_HOST)s/pb/` |
> | OpenList | `SITE_URL` | supervisord → `%(ENV_URL_SCHEME)s://%(ENV_SPACE_HOST)s/files/` |
> | Miniflux | `MINIFLUX_BASE_URL` | supervisord → `%(ENV_URL_SCHEME)s://%(ENV_SPACE_HOST)s/rss/` |
> | Vaultwarden | `DOMAIN` | supervisord → `.../vw/` — **trailing slash zaroori**, warna har asset 404 |
> | Chhoto URL | `CHHOTO_SITE_URL` | supervisord → `.../s` — **slash NAHI**, warna link `/s//slug` banega |

---

## 💳 Bina Card — Sab Free

| Service | Free limit | Card? |
|---|---|---|
| **Hugging Face** | 16 GB RAM, 2 vCPU, 50 GB, 1 port | ❌ Nahi |
| **Backblaze B2** | 10 GB + 3× free egress | ❌ Nahi |
| **Neon Postgres** | $0, 1 GB, 100 CU-hrs | ❌ Nahi |
| **GitHub Actions** | 2000 min/mo | ❌ Nahi |
| ~~Cloudflare R2~~ | — | 🔴 **Card chahiye — isliye B2** |

> ⚠️ **Neon ka catch:** Free plan me **5 min idle pe compute suspend**, disable
> nahi ho sakta. Miniflux kuch der na chala ho to pehli request **5-10 sec
> slow**. Personal use ke liye theek.

---

## 🚀 Deploy — Step by Step

### Step 0 — Banao (5 min, bina card)

| Kya | Kahan | Kya karna |
|---|---|---|
| **Hugging Face** | huggingface.co | Free account |
| **Backblaze B2** | backblaze.com/cloud-storage | Start Free → bucket banao → App Keys (sirf us bucket ki scope) |
| **Neon** | neon.tech | Free plan → project banao → connection string copy |

> B2 me **endpoint region alag** hota hai — Buckets → tera bucket → **Endpoint**
> copy karo. Jaise `s3.us-west-004.backblazeb2.com`.

### Step 1 — Space banao

`huggingface.co/new-space`

| Setting | Value |
|---|---|
| SDK | **Docker** |
| Visibility | 🔴 **Private** ← **zaroori** |
| Hardware | CPU Basic (free) |

### Step 2 — Code push karo

```bash
cd hf-stack
git init
git add .
git commit -m "feat: private cloud stack"

# seedha HF pe
git remote add hf https://huggingface.co/spaces/<TU>/<SPACE>
git branch -M main
git push hf main --force
```

> `sher-pocketbase/` folder `.gitignore` me hai — **push nahi hoga** (usme
> nested `.git` hai jo HF builder ko confuse karta).

### Step 3 — Secrets + Variables daalo

Upar wale 2 tables follow karo. **Pehle `BASIC_AUTH_PASSWORD` zaroor daal.**

### Step 4 — Build hone do

Pehli baar **3-5 min**. Space page pe **Logs** tab live dikhega.

> Agar `FATAL: ... has no release asset` aaye — upstream ne asset naming badli.
> Exact message bhej dena, 30 second me fix ho jayega.

### Step 5 — Verify

```bash
# health (bina password, 200 chahiye)
curl -i https://<TU>-<SPACE>.hf.space/health

# protected route (401 aana CHAHIYE - matlab gate kaam kar raha hai)
curl -i https://<TU>-<SPACE>.hf.space/pb/api/health

# password daal ke (200 chahiye)
curl -i -u admin:<TERA_PASSWORD> https://<TU>-<SPACE>.hf.space/pb/api/health
```

### Step 6 — Keep-alive (48h sleep rokne ke liye)

HF free Space **48 ghante** tak request na aaye toh so jata hai → **disk wipe**.

**Tarika A (recommended, no 3rd party):**
GitHub repo → `.github/workflows/keep-alive.yml` already hai.
→ Repo → **Settings → Actions → Variables** → `SPACE_HOST` daal do.
Har **15 min** `/health` ping karega.

**Tarika B:** cron-job.org ya UptimeRobot → har 10 min
`https://<TU>-<SPACE>.hf.space/health` ping.

### Step 7 — Har app ka admin banao

| App | Pehla kaam |
|---|---|
| **PocketBase** | `/pb/_/` kholo → superuser form aayega |
| **OpenList** | `/files/` kholo → admin create karo → phir storage mount |
| **Miniflux** | `/rss/` kholo → "Create account" |
| **Vaultwarden** | `/vw/` kholo → apna master password set karo → 🔴 **phir `.env` me `VW_SIGNUPS=false`** karke restart |
| **Chhoto URL** | `/s/admin/manage` → apna login password (`CHHOTO_PASSWORD`) daal ke entry banao |

> **Vaultwarden ka `VW_SIGNUPS` `false` karna ZAROORI hai.** Warna `true`
> rehne tak koi bhi jo `/vw/` dhoondh le, tumhare server pe apna login
> bana lega. Data end-to-end encrypted rehta hai — par server tumhara hai,
> aur stray accounts tumhare storage/bandwidth kharch karenge.
>
> **Bitwarden extension / mobile app** chalane ho to `nginx/conf.d/vaultwarden.conf`
> me `auth_basic` **off** rehne do (default). HTTP basic auth in clients bolte
> hi nahi, to wo 401 kha kar kabhi connect nahi honge. Sirf browser ka
> web-vault use karna hai to `auth_basic` ON karke double gate le lo.

---

## 🗂️ Structure

```
hf-stack/                              21 files · 1 local stack
├── README.md                          ← ye file
├── start.bat                          Windows double-click launcher
├── docker-compose.yml                 5 named volumes · single port 7860
├── Dockerfile                         7 binaries · 5 from GitHub + 2 from images
├── .dockerignore
├── .gitignore                         sher-pocketbase excluded
├── .env.example                       template — .env KABHI commit mat karo
│
├── nginx/
│   ├── nginx.conf                     non-root · 2 rate-limit zones · headers
│   └── conf.d/
│       ├── pocketbase.conf            /pb/    → 8090
│       ├── openlist.conf              /files/ → 5244
│       ├── miniflux.conf              /rss/   → 8080
│       ├── vaultwarden.conf           /vw/    → 8222 (+308 slash redirect)
│       └── chhoto.conf                /s/     → 4567
│
├── supervisor/supervisord.conf        8 programs · %(ENV_SPACE_HOST)s
│
├── litestream/
│   ├── litestream.yml                 SQLite → B2  (Vaultwarden kabhi nahi)
│   └── restore.sh                     startup pe B2 se wapas
│
├── restic/
│   ├── backup.sh                      har 6 ghante · client-side AES-256
│   └── restore.sh                     manual recovery
│
├── scripts/
│   ├── entrypoint.sh                  startup · password gen · restore
│   └── health-check.sh                sab services test
│
└── .github/workflows/keep-alive.yml   48h sleep rokta hai
```

---

## 🔧 Local Test (deploy se pehle)

```bash
cd hf-stack
cp .env.example .env        # values bhar do
docker build -t stack .
docker run --rm --env-file .env -p 7860:7860 stack

# doosre terminal me
curl http://localhost:7860/health
docker exec -it <container-id> /app/scripts/health-check.sh
```

---

## ⚠️ Common Problems

| Problem | Solution |
|---|---|
| **Har jagah 401** | Ye **expected** hai — password daalna mat bhoolna |
| **Blank page** | `SPACE_HOST` variable set nahi hai |
| **`FATAL: no release asset`** | Upstream ne asset naming badli — exact message bhejo |
| **`402 Payment Required`** | R2 use ho raha hai. **B2** use karo (no card) |
| **Miniflux "not configured"** | `DATABASE_URL_MINIFLUX` missing — embedded DB nahi hai |
| **Pehli RSS load slow** | Neon 5-min suspend — normal hai |
| **Vaultwarden blank / assets 404** | `/vw` bina trailing slash aa raha hai → `nginx/conf.d/vaultwarden.conf` ka `location = /vw { return 308 /vw/; }` check kar, aur `DOMAIN` me `/vw/` (slash sahit) hona chahiye |
| **`GLIBC_2.36 not found`** | Base image ubuntu:22.04 reh gayi. `Dockerfile` me `FROM debian:trixie-slim` hona chahiye (Vaultwarden binary glibc 2.41 maangta hai) |
| **Vaultwarden me koi aur account bana raha hai** | `VW_SIGNUPS` abhi bhi `true` hai → `.env` me `false` karke restart |
| **Bitwarden extension / mobile 401** | `/vw/` pe `auth_basic` ON hai → `vaultwarden.conf` me `off` kar do (clients Basic bolte hi nahi) |
| **Chhoto link `.../s//slug` ban raha** | `CHHOTO_SITE_URL` me trailing slash hai → `/s` rakho (slash ke baad app khud `/slug` lagata hai) |
| **supervisord `environment variable ... not defined`** | entrypoint.sh se `export` nahi hua (`URL_SCHEME` / `VW_SIGNUPS` / `CHHOTO_PASSWORD`) — logs me entrypoint ka error dikhega |
| **502 kisi app ka** | Logs tab dekho, ya `health-check.sh` chalao |
| **nginx permission denied** | UID 1000 temp paths — already `/tmp` me set hain |
| **Build 10 min+** | GitHub API rate limit — 5 min baad retry |
| **Space so gaya** | 48h sleep. Keep-alive setup karo. Cold start **30-90 sec** |

---

## 📊 Verified Facts (source ke saath)

| Fact | Source |
|---|---|
| PocketBase **v0.40.5**, asset `pocketbase_0.40.5_linux_amd64.zip` | GitHub releases API |
| OpenList **v4.2.6**, asset `openlist-linux-amd64.tar.gz` | GitHub releases API |
| OpenList `SITE_URL` env = base path | `internal/conf/config.go` → `env:"SITE_URL"` |
| Miniflux **2.3.3**, asset `miniflux-linux-amd64` | GitHub releases API |
| Navidrome `BaseURL` supports sub-path | `conf/configuration.go` |
| **Vaultwarden releases = 0 assets** (v1.37.4), chhoto-url bhi **0 assets** (7.8.3) → seedha direct URL **404** | GitHub releases API (`.assets.Count`) |
| Vaultwarden official image = `/vaultwarden` (binary) + `/web-vault` (frontend) | `vaultwarden/main/Dockerfile` |
| Vaultwarden binary **glibc 2.41** (Debian 13 / trixie) → Ubuntu 22.04 (glibc 2.35) par **chalega nahi** | same Dockerfile: `FROM debian:trixie-slim` |
| Vaultwarden sub-path: `/vw` **bina slash** pe har asset 404, maintainer ne **"not planned"** me band kiya | GitHub issue **#6287**, closed by BlackDex |
| chhoto-url image = `/app/chhoto-url` + `/app/frontend`, **musl static** → kahin bhi chalta hai | `deploy/Containerfile.scratch` |
| chhoto-url *"link will work at any URL as long as accessible there"* → **relative URL generation**, sub-path safe | `docs/INSTALLATION.md` (`CHHOTO_SITE_URL`) |
| chhoto-url `/admin/manage` pe panel, `CHHOTO_PASSWORD` se login | same docs |
| Litestream `replica:` singular = current; `replicas:` = **deprecated par chalta hai** | `cmd/litestream/main.go` source |
| `litestream restore -if-replica-exists -config X <local>` | official docs |
| B2 = **no credit card**, 10 GB free | backblaze.com |
| Neon Free = **$0, 1 GB, 100 CU-hrs, 5-min scale-to-zero** | neon.tech/docs/plans |
| HF = 1 port (7860), 48h sleep, ephemeral disk, UID 1000 | HF docs |
| Memos / Shiori = **no base-path support found** | source search |
| restic is now **Go** (was Rust) | `go.mod` |

### 🐛 Ye galat maan jaane se bachata hai

```
❌ releases/latest/download/pocketbase_linux_amd64.zip
   Assets VERSIONED hain -> hamesha 404. Pattern se match karo.

❌ vaultwarden/releases/latest/download/vaultwarden
   Releases me 0 assets hain -> direct URL 404. Official IMAGE se COPY karo
   (hum yahi karte hain: COPY --from=vaultwarden/server:1.37.4).

❌ ubuntu:22.04 base + Vaultwarden official binary
   glibc 2.41 vs 2.35 -> "GLIBC_2.36 not found". Base trixie-slim rakho.

❌ /vw  (bina trailing slash)
   Har asset 404, page blank. Nginx ko `location = /vw { return 308 /vw/; }`
   chahiye - upstream issue #6287 me "not planned" hai.

❌ chhoto-url pe comma/quote wala password
   supervisord `environment=` comma-separated KEY="value" parse karta hai,
   comma aate hi aage ki har variable gir jaati hai. Sirf A-Za-z0-9.

❌ ROCKET_PORT=80
   Non-root privileged port (<1024) bind nahi kar sakta.

❌ nginx.conf me `user user;`
   Master non-root ho to Nginx error deta hai.

❌ litestream restore -o <path> s3://...
   v0.5: litestream restore -if-replica-exists -config X <local-path>

❌ PASSWORD kisi file me likh dena
   Offline crack hoga. Sirf HF Secret se runtime generate karo.
```

---

## 🧭 Ye 1 Stack Me NAHI Ho Sakta

| App | Stars | Kyun |
|---|---|---|
| **Memos** | 63,754 | Source me **koi base-path config nahi** |
| **Shiori** | 11,671 | Base-path support nahi |
| **Gnat** | ~9 | Repo verify nahi hua, v0.1.0 |
| FileBrowser | — | Upstream **archived** |
| Uptime Kuma | — | JavaScript (out of scope) |

> Inhe thoosna = **guaranteed blank page**.

### ❌ Pehle yahan Vaultwarden bhi tha — ab wo chal raha hai

Purana version kehta tha *"Vaultwarden ko root `/` chahiye, aur uski SQLite unsafe
hai."* Dono baatein verify karke **galat** nikli:

| Purana daava | Sach |
|---|---|
| *"Absolute asset paths → root chahiye"* | 🔴 **Galat.** Web-vault **relative** URLs serve karta hai, isliye sub-path par **chalta hai** — bas `/vw` (bina trailing slash) pe har asset 404 hota hai. Upstream ne issue #6287 **"not planned"** me band kiya, so nginx khud `308 /vw/` deta hai. |
| *"SQLite unsafe → Postgres mandatory"* | 🔴 **Overstatement.** Asli khatra **litestream ka auto-restore** hai: woh container boot pe purana replica lautata hai, jisse naye passwords wapas chale jaate hain. Permanently locked kuch nahi hota — sirf data loss. **Fix: Vaultwarden ko litestream se bahar rakho** (sirf restic backup, jo kabhi live DB overwrite nahi karta). |

**Chhoto URL ke liye ulta hai** — uski SQLite **litestream mein hai** kyunki
short links me koi crypto key nahi, to auto-restore safe hai.

### ➕ Aur daal sakte ho (sub-path safe, verified)

| App | Lang | Stars | Setting |
|---|---|---|---|
| **Navidrome** 🎵 | Go | 24,137 | `BaseURL` (`ND_BASEURL`) |
| **Forgejo** | Go | — | `ROOT_URL` (self-hosted Git, Gitea's community fork) |

---

## 🎯 Deploy Ke Baad Ka Order

1. `SPACE_HOST` set → `/health` check → **200**
2. `/pb/` → superuser banao
3. `/files/` → admin banao → B2 mount karo (**Crypt driver** use karo)
4. `/rss/` → account banao → feeds add
5. `/vw/` → master password set karo → 🔴 **`VW_SIGNUPS=false`** + restart
6. `/s/` → `CHHOTO_PASSWORD` se entry banao → ek short link test karo
7. **B2 backup chalu** → 🔴 **ek test restore zaroor karo**

---

> ### 🎯 Sabse Zaroori
> **Bina test restore kiye backup, backup nahi hota — sirf umeed hota hai.**
>
> ```bash
> docker exec -it <container> restic snapshots
> docker exec -it <container> /app/restic/restore.sh /tmp/verify
> ```
>
> `/tmp/verify` me files dikhi? Tabhi backup real hai.
