# Azul Tech SSO — hand-off to IT

This is everything needed to take the SSO from "works on my laptop" to
**hosted and serving Lunchify**. Other company apps come later — each is a
5-minute `register-app.sh` once it exists. Zoho is **not** part of Phase 1 —
see the note at the bottom.

The SSO itself is **built and configured**. What's left is infrastructure
(server, DNS, TLS, real SMTP) and decisions only the company can make — all
flagged with ⚠️ below.

---

## What's already done (in this repo)

- Keycloak **26.7.3** + Postgres 15, Docker Compose, with a production
  override (`docker-compose.prod.yml`, `start --optimized`).
- Realm **`azultech`** (no hyphen — permanent, baked into the issuer URL)
  fully wired by **`keycloak/scripts/configure-realm.sh`** (idempotent, the
  single source of truth — no realm JSON with secrets in git). Keycloak is
  the identity provider itself: local users, its own branded login page, no
  upstream Zoho broker. Full model in `docs/PHASE-1-REALM.md`.
- Group/role structure: `/Departments/*` (org membership), `/Platform-Admins`
  (Keycloak operators), `/App-Access/Lunchify/*` (app entitlement tiers,
  each carrying the matching `lunchify` client role).
- MFA (TOTP) **mandatory for every user from day one**, with recovery codes
  issued at enrolment. Lost-device procedure: `docs/mfa-recovery-procedure.md`.
- No-password onboarding: `keycloak/scripts/provision-users.sh <csv>`
  creates each user with no password and emails them a one-time link
  (Keycloak's `execute-actions-email`) to set their own password and enrol
  MFA. **No admin ever sets or sees a user's password.** Requires real SMTP
  in production (decision #3 below) — dev uses MailHog.
- The old `setup-complete.ps1` / `setup.ps1` are **deprecated** and describe
  neither this nor the earlier Zoho-broker design. Don't run them.

---

## ⚠️ Decisions needed before go-live

| # | Decision | Where it goes |
|---|----------|---------------|
| 1 | **Company email domain(s)** for the `ALLOWED_EMAIL_DOMAIN` check on the app side (Lunchify). Repo assumes `azultech.rw`. | Lunchify's `.env` → `ALLOWED_EMAIL_DOMAIN` |
| 2 | **Public hostnames.** Repo assumes `sso.azultech.rw` (Keycloak) and `lunch.azultech.rw` (Lunchify). | `.env`, nginx config |
| 3 | **Real SMTP credentials** for onboarding/password-reset emails (`execute-actions-email` won't deliver without them). | `.env` → `SMTP_*` |
| 4 | **`KEYCLOAK_ADMIN_PASSWORD`** and every other secret in `.env` — generate fresh values, don't reuse anything from local dev. | `.env` |

---

## Deploy steps (server)

Prereqs: a Linux VM with Docker + Docker Compose + nginx + certbot, and DNS
`A` records for both hostnames pointing at the VM. This deployment does
**not** need to be in-country for Phase 1 to be correct, but Rene's stated
reason for moving off the Zoho-broker design was in-country identity
control for government-client reference architecture — factor that into
where this VM actually sits.

```bash
git clone <this repo> /opt/azultech/sso
cd /opt/azultech/sso

cp .env.example .env
```

Edit `.env` — set the production block:

```
POSTGRES_PASSWORD=<openssl rand -hex 24>
KEYCLOAK_ADMIN_PASSWORD=<openssl rand -hex 24>
KC_REALM=azultech
KC_HOSTNAME_URL=https://sso.azultech.rw
KC_HOSTNAME_ADMIN_URL=https://sso.azultech.rw
KC_HOSTNAME_STRICT=true
KC_HOSTNAME_STRICT_HTTPS=true
SMTP_HOST=<real SMTP host>                    # decision #3
SMTP_PORT=587
SMTP_FROM=sso@azultech.rw
SMTP_FROM_NAME="Azul Tech SSO"
SMTP_USER=<smtp username>
SMTP_PASSWORD=<smtp password>
SMTP_STARTTLS=true
SMTP_AUTH=true
PLATFORM_ADMIN_EMAILS=<comma-separated named platform-admin accounts>
```

Start in production mode:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

Wait for health, then apply the realm configuration (creates the realm on a
fresh DB, idempotent so it's safe to re-run):

```bash
curl -sf http://127.0.0.1:8081/health/ready && echo ready
./keycloak/scripts/configure-realm.sh
```

Provision real staff (roster from Yvonne, **not** derived from any mailbox
list):

```bash
./keycloak/scripts/provision-users.sh keycloak/scripts/<real-staff>.csv
```

Create the break-glass admin account (run this yourself, directly — see the
script's header for why):

```bash
./keycloak/scripts/create-break-glass-admin.sh <break-glass-username>
```

Schedule Lunchify's data-file backup (cron; `BACKUP_DIR` should itself be
synced off this box):

```bash
crontab -e
# 0 2 * * * DATA_FILE=/app/server/data/lunchify.json BACKUP_DIR=/var/backups/lunchify /app/server/scripts/backup-data.sh
```

TLS + reverse proxy:

```bash
cp nginx/azultech-sso.conf.example /etc/nginx/sites-available/azultech-sso.conf
# edit hostnames + the Lunchify upstream port if not 3001
ln -s /etc/nginx/sites-available/azultech-sso.conf /etc/nginx/sites-enabled/
certbot --nginx -d sso.azultech.rw -d lunch.azultech.rw
nginx -t && systemctl reload nginx
```

**Important — the internal-vs-public URL nuance** (see
`docs/PHASE-1-REALM.md`, "Onboarding"): any admin tooling that mints a link
for a human to click (`execute-actions-email` and similar) must call the
Admin API against the **public** hostname, not `localhost` / the internal
Docker network address, or the resulting link's issuer won't validate in a
browser. `provision-users.sh` already does this correctly — keep that
pattern if you script anything else that emails a Keycloak link.

---

## Smoke test

```bash
curl -s https://sso.azultech.rw/realms/azultech/.well-known/openid-configuration | grep -o '"issuer":"[^"]*"'
# -> "issuer":"https://sso.azultech.rw/realms/azultech"
```

Then in a browser: open Lunchify → **Continue with Azul Tech SSO** → land on
Keycloak's own branded login page (not a Zoho redirect) → sign in as a
provisioned test user → complete the onboarding required actions (password,
TOTP, recovery codes) on first login → land back in Lunchify on the correct
role-based dashboard.

Admin console: `https://sso.azultech.rw/admin/` (`admin` /
`KEYCLOAK_ADMIN_PASSWORD`).

---

## Adding another company app later

```bash
KEYCLOAK_URL=https://sso.azultech.rw ADMIN_PASSWORD=... \
  ./keycloak/scripts/register-app.sh <client-id> "<App Name>" "https://<app-host>/*"
```

Give the printed client ID/secret + issuer URL to that app's developers.
That app must key its own user records off the token's `sub` claim, never
off email or username (see `docs/PHASE-1-REALM.md`, "Token claim contract").

---

## Backups (cron)

```bash
docker exec azul-tech-postgres pg_dump -U keycloak keycloak | gzip > kc-$(date +%F).sql.gz
```

---

## About Zoho

Zoho is **not** part of this Phase 1 deployment — Keycloak is the identity
provider on its own, with local users. Zoho becomes a *downstream* SAML
application of this realm in **Phase 2** (Rene is handling that plan
directly); there is nothing to configure in the Zoho API Console for Phase 1
go-live.

---

## Still open / not this repo's job

- **Lunchify's own deployment** (its API + web) — see the Lunchify repo's
  `README.md`. Its data store is a single JSON file with atomic,
  immediate writes (not just periodic) — adequate at this headcount; what it
  actually lacked was backups leaving the box, which
  `server/scripts/backup-data.sh` now covers. Revisit a real database if/when
  write volume or headcount grows well past the pilot.
- Monitoring / alerting on the SSO endpoint.
- HA (2+ Keycloak nodes, Postgres failover) — not needed for the pilot; see
  `docs/PHASE-1-REALM.md`.
- Break-glass admin account (excluded from MFA, sealed credentials) — see
  `docs/PHASE-1-REALM.md`.
