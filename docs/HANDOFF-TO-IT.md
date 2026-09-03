# Azul Tech SSO — hand-off to IT

This is everything needed to take the SSO from "works on my laptop" to
**hosted and serving Lunchify**. Other company apps come later — each is a
5-minute `register-app.sh` once it exists.

The SSO itself is **built and configured**. What's left is infrastructure
(server, DNS, TLS) and three decisions only the company can make — all flagged
with ⚠️ below.

---

## What's already done (in this repo)

- Keycloak 20 + Postgres, Docker Compose, with a production override
  (`docker-compose.prod.yml`, `start --optimized`).
- Realm `azul-tech` fully wired by **`keycloak/scripts/configure-realm.sh`**
  (idempotent, the single source of truth — no realm JSON with secrets in git):
  - Zoho as the upstream login (employees use their Zoho Mail account, no new password)
  - **Email Domain Guard** — rejects any non-company email before an account is created
  - `lunchify` client (Authorization Code + PKCE)
  - custom navy/royal-blue login theme (`docs/branding.md`)
- The old `setup-complete.ps1` / `setup.ps1` are **deprecated**. `configure-realm.sh`
  now also purges what they left behind (demo users with passwords, placeholder
  app clients). Don't run them.

---

## ⚠️ Three decisions needed before go-live

| # | Decision | Where it goes |
|---|----------|---------------|
| 1 | **Company email domain(s)** for sign-in (who is allowed in). Repo assumes `azultech.rw`. | `.env` → `ALLOWED_EMAIL_DOMAINS` |
| 2 | **Public hostnames.** Repo assumes `sso.azultech.rw` (Keycloak) and `lunch.azultech.rw` (Lunchify). | `.env`, nginx config, Zoho console |
| 3 | **Rotate the Zoho client secret.** The current one was shared in plaintext during development — generate a fresh one in the Zoho API Console. | `.env` → `ZOHO_CLIENT_SECRET` |

---

## Deploy steps (server)

Prereqs: a Linux VM with Docker + Docker Compose + nginx + certbot, and DNS
`A` records for both hostnames pointing at the VM.

```bash
git clone <this repo> /opt/azultech/sso
cd /opt/azultech/sso

cp .env.example .env
```

Edit `.env` — set the production block:

```
POSTGRES_PASSWORD=<openssl rand -hex 24>
KEYCLOAK_ADMIN_PASSWORD=<openssl rand -hex 24>
KC_HOSTNAME_URL=https://sso.azultech.rw
KC_HOSTNAME_ADMIN_URL=https://sso.azultech.rw
KC_HOSTNAME_STRICT=true
KC_HOSTNAME_STRICT_HTTPS=true
ALLOWED_EMAIL_DOMAINS=azultech.rw            # decision #1
LUNCHIFY_ORIGIN=https://lunch.azultech.rw
LUNCHIFY_REDIRECT=https://lunch.azultech.rw/*
ZOHO_CLIENT_ID=<from Zoho API Console>
ZOHO_CLIENT_SECRET=<freshly rotated — decision #3>
```

Build the domain-guard provider and start in production mode:

```bash
./keycloak/scripts/build-providers.sh
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

Wait for health, then apply the realm configuration (creates the realm on a
fresh DB, idempotent so it's safe to re-run):

```bash
curl -sf http://127.0.0.1:8081/health/ready && echo ready
./keycloak/scripts/configure-realm.sh
```

TLS + reverse proxy:

```bash
cp nginx/azultech-sso.conf.example /etc/nginx/sites-available/azultech-sso.conf
# edit hostnames + the Lunchify upstream port if not 3001
ln -s /etc/nginx/sites-available/azultech-sso.conf /etc/nginx/sites-enabled/
certbot --nginx -d sso.azultech.rw -d lunch.azultech.rw
nginx -t && systemctl reload nginx
```

---

## Zoho API Console (decision #2 + #3)

In <https://api-console.zoho.com/> open the OIDC client used for SSO and:

1. **Add the production redirect URI:**
   `https://sso.azultech.rw/realms/azul-tech/broker/zoho/endpoint`
2. **Regenerate the client secret**, put the new value in `.env`, re-run
   `./keycloak/scripts/configure-realm.sh`.

---

## Smoke test

```bash
curl -s https://sso.azultech.rw/realms/azul-tech/.well-known/openid-configuration | grep -o '"issuer":"[^"]*"'
# -> "issuer":"https://sso.azultech.rw/realms/azul-tech"
```

Then in a browser: open Lunchify → **Continue with Azul Tech SSO** →
sign in with a **real `@azultech.rw` Zoho account** → you land back in Lunchify.
Confirm a non-company Google/Zoho account is **rejected** with the guard's
"not part of Azul Tech" page.

Admin console: `https://sso.azultech.rw/admin/` (`admin` / `KEYCLOAK_ADMIN_PASSWORD`).

---

## Adding another company app later

```bash
KEYCLOAK_URL=https://sso.azultech.rw ADMIN_PASSWORD=... \
  ./keycloak/scripts/register-app.sh <client-id> "<App Name>" "https://<app-host>/*"
```

Give the printed client ID/secret + issuer URL to that app's developers. The app
must also enforce the `@azultech.rw` email claim on its side.

---

## Backups (cron)

```bash
docker exec azul-tech-postgres pg_dump -U keycloak keycloak | gzip > kc-$(date +%F).sql.gz
```

---

## Still open / not this repo's job

- **Lunchify's own deployment** (its API + web, its database) — see the Lunchify
  repo's `DEPLOYMENT.md`. Lunchify still ships an in-memory store that must be
  swapped for a real DB before production.
- Monitoring / alerting on the SSO endpoint.
- Keycloak 20 → newer upgrade (test on a DB copy first).
