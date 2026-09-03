# Deployment Checklist — Azul Tech SSO

Architecture: **Keycloak brokers to Zoho** (see `docs/architecture.md`).
Hosting runbook for IT: **`docs/HANDOFF-TO-IT.md`**.

> Company email domain is assumed to be **`azultech.rw`** throughout (matches
> `.env.example`, nginx config, the domain guard). ⚠️ Confirm with IT before
> go-live and change `ALLOWED_EMAIL_DOMAINS` in `.env` if different.

## Phase 1 — Local (done / verify)

- [x] `.env` created from `.env.example` with real secrets
- [x] `docker compose up -d` → Keycloak on `http://localhost:8081`, Postgres healthy
- [x] Realm `azul-tech` present; `configure-realm.sh` applied
- [x] Zoho identity provider wired (real client id/secret, PKCE S256, mappers)
- [x] Email Domain Guard JAR built + bound as step 0 of `first broker login azul`
- [x] `lunchify` client hardened (public, PKCE S256, post-logout URIs)
- [x] Zoho API Console: redirect URI `http://localhost:8081/realms/azul-tech/broker/zoho/endpoint`
- [x] Custom `azultech` login theme (navy/royal-blue) — `docs/branding.md`
- [x] Deprecated `setup-complete.ps1` artifacts purged (demo users, `*`-redirect clients)
- [x] Prod image build fixed (`docker-compose.prod.yml` build context)
- [ ] **Browser E2E:** real `@azultech.rw` Zoho login through Lunchify (`docs/testing.md`)
- [ ] Confirm the guard rejects a non-`@azultech.rw` account

## Phase 2 — Production readiness

### Secrets
- [ ] Rotate Zoho client secret (was shared in plaintext)
- [ ] Strong `POSTGRES_PASSWORD`, `KEYCLOAK_ADMIN_PASSWORD`
- [ ] Lunchify: real `JWT_SECRET`, `SESSION_SECRET`

### Keycloak hardening
- [x] Prod override exists: `docker-compose.prod.yml` (`start --optimized`, `KC_PROXY=edge`)
- [ ] Deploy with it: `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build`
- [ ] `.env`: `KC_HOSTNAME_URL=https://sso.azultech.rw`, `KC_HOSTNAME_STRICT=true`
- [ ] nginx reverse proxy + Let's Encrypt TLS in front of `:8081` (`nginx/azultech-sso.conf.example`)
- [x] Realm base: short access-token lifespan, SSO idle/max timeouts, brute-force (set by `configure-realm.sh`)
- [ ] Plan Keycloak 20 → current upgrade (test DB migration on a copy)

### Domain / DNS
- [ ] `sso.<domain>` → server
- [ ] Add prod redirect URIs: Keycloak `lunchify` client + Zoho API Console

### Lunchify
- [ ] Replace `server/src/db.js` in-memory store with a real database
- [ ] Build client with prod `VITE_KEYCLOAK_URL`; deploy behind TLS
- [ ] `server/.env`: prod `KEYCLOAK_ISSUER` / `KEYCLOAK_JWKS_URI`

## Phase 3 — Other apps (later)

No app clients exist yet except `lunchify` — the old placeholders were removed.
When another app is ready:

- [ ] `./keycloak/scripts/register-app.sh <id> "<name>" "https://<host>/*"` (see `docs/oidc-integration.md`)
- [ ] Exact redirect URIs — never `*`
- [ ] The app enforces the `@azultech.rw` email-claim check on its side
- [ ] Pilot group → all staff

## Commands

```bash
cd sso
docker compose up -d
docker compose logs -f keycloak
./keycloak/scripts/configure-realm.sh    # re-apply realm config (idempotent)
./keycloak/scripts/build-providers.sh    # rebuild the domain-guard JAR
```
