# Azul Tech SSO

> **Architecture changed 2026-09-04 — read `docs/PHASE-1-REALM.md` first.**
> Keycloak is now the identity provider itself (local users, our own login
> page, MFA enforced at login). The Zoho-broker design below is superseded;
> Zoho becomes a *downstream* SAML app of this realm in Phase 2.

Single Sign-On for Azul Tech. In the target end-state, employees sign in to
every company app on Keycloak's own login page — no separate Zoho password.

## How it worked (superseded — kept for history)

Keycloak used to be a broker: it did **not** store passwords, it forwarded
authentication upstream to Zoho, then issued tokens to the apps.

```
  Lunchify ┐
  hrm-app  ├─ trust ─▶  Keycloak (realm: azul-tech, :8081)  ─ brokers ─▶  Zoho (accounts.zoho.com)
  finance  ┘             issues app tokens, holds SSO session              password + MFA authority
  projects-mel                    │
                          Email Domain Guard: only @azultech.rw gets in
```

Full detail: **`docs/architecture.md`**.

## Quick start

```bash
cd sso
cp .env.example .env         # fill ZOHO_CLIENT_ID / ZOHO_CLIENT_SECRET / passwords
./keycloak/scripts/build-providers.sh          # (Windows: build-providers.ps1)
docker compose up -d                           # Keycloak -> http://localhost:8081
./keycloak/scripts/configure-realm.sh          # wire Zoho IdP + guard + clients (idempotent)
```

Admin console: `http://localhost:8081/admin` (`admin` / `KEYCLOAK_ADMIN_PASSWORD`).

## Docs

| File | What |
|---|---|
| `docs/architecture.md` | the trust model and components |
| `docs/zoho-integration.md` | Zoho ↔ Keycloak setup (what's configured, what you do in the Zoho console) |
| `docs/lunchify-integration.md` | the Lunchify front/back wiring (reference integration) |
| `docs/oidc-integration.md` | integrating another OIDC app (hrm-app, finance-app, projects-mel) |
| `docs/testing.md` | how to test the flow end to end |
| `docs/branding.md` | the custom navy/royal-blue login theme (`azultech`) |
| `docs/HANDOFF-TO-IT.md` | **hosting runbook** — what IT does to deploy, and the decisions the company must make |
| `DEPLOYMENT-CHECKLIST.md` | local → production checklist |

## Realm config is code

`keycloak/scripts/configure-realm.sh` is idempotent and is the **source of truth**
for how the realm is wired. The full realm JSON export is git-ignored (it contains
client secrets and password hashes).

## Provisioning & roles

Users are auto-created in Keycloak on first Zoho login (the domain guard makes
that safe). Application roles live **in each app**, keyed by email — Keycloak only
proves identity.

## Note on older scripts

`setup-complete.ps1` / `setup.ps1` predate this design — they create local
Keycloak users with passwords on an `@azul-tech.com` domain. They are **not** part
of the Zoho-brokered flow; use `configure-realm.sh` instead.
