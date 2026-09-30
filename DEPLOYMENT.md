# Hosting Azul Tech SSO + Lunchify

> For the **SSO only**, the focused hand-off runbook is **`docs/HANDOFF-TO-IT.md`**.
> This file covers both services together.

Two repos, deployed on one Linux server (Docker + nginx):

- `sso/` — Keycloak + Postgres  → `https://sso.azultech.rw`
- `lunch app/` — Lunchify (API + web) → `https://lunchify.azultech.rw`

Lunchify talks to Keycloak over its **public URL** (for JWKS), so the two stacks
are independent — no shared Docker network required.

---

## 0. Prerequisites (IT)

- A VM with Docker + Docker Compose + nginx + certbot
- DNS `A` records: `sso.azultech.rw` and `lunchify.azultech.rw` → the VM's public IP
- Both repos copied to the server (e.g. `/opt/azultech/sso`, `/opt/azultech/lunch-app`)

---

## 1. Keycloak (`sso/`)

```bash
cd /opt/azultech/sso
cp .env.example .env
```

Edit `.env`:
```
POSTGRES_PASSWORD=<openssl rand -hex 24>
KEYCLOAK_ADMIN_PASSWORD=<openssl rand -hex 24>
KC_HOSTNAME_URL=https://sso.azultech.rw
KC_HOSTNAME_ADMIN_URL=https://sso.azultech.rw
KC_HOSTNAME_STRICT=true
ALLOWED_EMAIL_DOMAINS=azultech.rw
ZOHO_ACCOUNTS_HOST=accounts.zoho.com
ZOHO_CLIENT_ID=<from Zoho API Console>
ZOHO_CLIENT_SECRET=<from Zoho API Console — ROTATE the one shared earlier>
```

> **`KC_HOSTNAME_URL` / `KC_HOSTNAME_ADMIN_URL` are the single most important
> two lines in this file.** They decide every URL Keycloak hands to a browser —
> the issuer apps read, the post-login redirect, and the link in each onboarding
> email. Get them wrong and a deployed app's "Continue with Azul Tech SSO" button
> sends users to `http://localhost:8081`, a port on *their own machine*.
>
> Three guards now stop that from shipping:
> - `.env.example` no longer contains a localhost value to copy by accident.
> - `docker-compose.prod.yml` **aborts** `up -d` if either variable is missing.
> - `preflight-prod-env.sh` also rejects loopback and plain-http values.

Build the domain-guard provider, then start in production mode:
```bash
./keycloak/scripts/build-providers.sh          # creates providers/azul-domain-guard.jar
./keycloak/scripts/preflight-prod-env.sh       # must pass before starting
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

Apply the realm wiring (idempotent):
```bash
./keycloak/scripts/configure-realm.sh
```

Then in the Keycloak admin console (`https://sso.azultech.rw/admin`):
- **Clients → lunchify → Valid redirect URIs**: `https://lunchify.azultech.rw/*`
- same for **Web origins** and **Valid post logout redirect URIs**

In the **Zoho API Console**, add the production redirect URI to the app:
`https://sso.azultech.rw/realms/azul-tech/broker/zoho/endpoint`

---

## 2. Lunchify (`lunch app/`)

```bash
cd /opt/azultech/lunch-app
cp .env.docker.example .env.docker
```

Edit `.env.docker`:
```
FRONTEND_URL=https://lunchify.azultech.rw
KEYCLOAK_ISSUER=https://sso.azultech.rw/realms/azul-tech
KEYCLOAK_JWKS_URI=https://sso.azultech.rw/realms/azul-tech/protocol/openid-connect/certs
ALLOWED_EMAIL_DOMAIN=azultech.rw
BOOTSTRAP_ADMIN_EMAILS=u.yvonne@azultech.rw
JWT_SECRET=<openssl rand -hex 32>
SESSION_SECRET=<openssl rand -hex 32>
```

**Who can log in:** every `@azultech.rw` Zoho account. The SSO button is universal —
anyone in the company clicks it, signs in with their work account, and gets in as
an **EMPLOYEE** automatically (no pre-registration).

**`BOOTSTRAP_ADMIN_EMAILS`** only decides who starts as **SUPER_ADMIN** instead of
EMPLOYEE on first login — just Yvonne Uwantege (`u.yvonne@azultech.rw`), the
company admin. She logs in, then assigns every other role (more admins, the
kitchen manager) from **Admin → Team**. The setting only ever promotes, never
demotes; you can blank it once she has logged in.

Build the SSO URL is baked into the web bundle and start:
```bash
VITE_KEYCLOAK_URL=https://sso.azultech.rw \
docker compose up -d --build
```

> ⚠️ **The single most common cause of the SSO button going to localhost.**
> `VITE_KEYCLOAK_URL` is baked into the web bundle **at build time** — it is not
> read at runtime, so a running container keeps the value it was built with.
> Build it without the variable (or with the dev default from
> `docs/lunchify-integration.md`) and the button navigates to
> `http://localhost:8081` forever, no matter how correct the SSO repo's `.env`
> is. There is no way to patch this at runtime — **rebuild the web image** with
> the public URL set.

Data persists in the `lunchify_data` volume (`docker volume inspect lunch-app_lunchify_data`).

---

## 3. nginx + TLS

```bash
cp /opt/azultech/sso/nginx/azultech-sso.conf.example /etc/nginx/sites-available/azultech-sso.conf
ln -s /etc/nginx/sites-available/azultech-sso.conf /etc/nginx/sites-enabled/
certbot --nginx -d sso.azultech.rw -d lunchify.azultech.rw
nginx -t && systemctl reload nginx
```

---

## 4. Smoke test

```bash
./keycloak/scripts/verify-endpoints.sh
```

That asserts the **live** issuer over the public URL. It catches the class of bug
where `.env` is right but the running container still advertises localhost:

```
   issuer: https://sso.azultech.rw/realms/azul-tech
ok: live issuer matches the configured hostname
VERIFY PASSED — Keycloak is advertising its public https URL.
```

It reads `.env`, so running it locally is harmless — a dev box reports a
`localhost` issuer and passes. Pass the URL explicitly to pin it:

```bash
./keycloak/scripts/verify-endpoints.sh https://sso.azultech.rw
```

Manual equivalent:
```bash
curl -s https://sso.azultech.rw/realms/azul-tech/.well-known/openid-configuration | grep issuer
#  -> "issuer":"https://sso.azultech.rw/realms/azul-tech"
curl -s https://lunchify.azultech.rw/api/health
```

Then in a browser: `https://lunchify.azultech.rw` → **Continue with Azul Tech SSO** →
sign in with a real `@azultech.rw` Zoho account → lands in Lunchify. The
`BOOTSTRAP_ADMIN_EMAILS` account becomes SUPER_ADMIN; everyone else is EMPLOYEE.

If that button lands on `localhost:8081`, the issuer is fine but the **web bundle
was built without `VITE_KEYCLOAK_URL`** — rebuild it (section 2). If the *Keycloak
login page itself* is unreachable, run `verify-endpoints.sh` and fix `.env`.

---

## 5. Backups

```bash
# Keycloak DB
docker exec azul-tech-postgres pg_dump -U keycloak keycloak | gzip > kc-$(date +%F).sql.gz
# Lunchify data
docker run --rm -v lunch-app_lunchify_data:/d -v "$PWD":/b alpine \
  sh -c 'cp /d/lunchify.json /b/lunchify-$(date +%F).json'
```
Schedule both with cron.
