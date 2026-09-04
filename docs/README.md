# Azul Tech SSO

> **Architecture changed 2026-09-04 — read `docs/PHASE-1-REALM.md` first.**
> Keycloak is the identity provider itself: local users, our own branded
> login page, MFA mandatory for everyone from day one, no admin-set
> passwords (self-service via emailed one-time links). The Zoho-broker
> design below is superseded; Zoho becomes a *downstream* SAML app of this
> realm in Phase 2.

Single Sign-On for Azul Tech. Employees sign in to every company app on
Keycloak's own login page.

## How it worked before (superseded — kept for history)

Keycloak used to be a broker: it did **not** store passwords, it forwarded
authentication upstream to Zoho, then issued tokens to the apps. Rejected
because a Zoho-dependent auth path doesn't fit a reference architecture
meant for government clients with in-country identity control, and because
an LDAP-bind fallback would have handed Keycloak the plaintext password to
replay — see `docs/PHASE-1-REALM.md` for the full reasoning.

```
  Lunchify ┐
  hrm-app  ├─ trust ─▶  Keycloak (realm: azul-tech, :8081)  ─ brokers ─▶  Zoho (accounts.zoho.com)
  finance  ┘             issues app tokens, holds SSO session              password + MFA authority
  projects-mel                    │
                          Email Domain Guard: only @azultech.rw gets in
```

Full detail (historical): `docs/architecture.md`, `docs/zoho-integration.md`.

## Quick start

```bash
cd sso
cp .env.example .env                           # fill in passwords, SMTP, etc.
docker compose up -d                           # Keycloak -> http://localhost:8081
./keycloak/scripts/configure-realm.sh          # wire the realm: roles, groups, lunchify client (idempotent)
./keycloak/scripts/provision-users.sh keycloak/scripts/pilot-users.csv   # create real users, email them onboarding links
```

Admin console: `http://localhost:8081/admin` (`admin` / `KEYCLOAK_ADMIN_PASSWORD`).
Dev SMTP catcher (MailHog): `http://localhost:8025`.

## Docs

| File | What |
|---|---|
| `docs/PHASE-1-REALM.md` | **current model** — realm, groups/roles, claim contract, onboarding, MFA |
| `docs/mfa-recovery-procedure.md` | identity-verified lost-device MFA recovery |
| `docs/patching-cadence.md` | proposed Keycloak patching cadence for the ISMS |
| `docs/HANDOFF-TO-IT.md` | **hosting runbook** — what IT does to deploy, and the decisions the company must make |
| `docs/lunchify-integration.md` | the Lunchify front/back wiring (reference integration) |
| `docs/oidc-integration.md` | integrating another OIDC app (hrm-app, finance-app, projects-mel) — authorize on your client role, not on groups |
| `docs/testing.md` | how to test the flow end to end |
| `docs/branding.md` | the custom navy/royal-blue login theme (`azultech`) |
| `docs/architecture.md`, `docs/zoho-integration.md`, `docs/quick-reference.md`, `docs/app-integration-checklist.md` | superseded Zoho-broker design — kept for history only, don't follow |
| `DEPLOYMENT-CHECKLIST.md` | local → production checklist |

## Realm config is code

`keycloak/scripts/configure-realm.sh` is idempotent (verified: a second run
against a live realm exits 0 reporting no changes) and is the **source of
truth** for how the realm is wired. The full realm JSON export is
git-ignored (it contains client secrets and password hashes).

## Provisioning & roles

Users are explicitly provisioned via `provision-users.sh` from Yvonne's real
staff roster — never auto-created, never derived from a mailbox list. Nobody
sets a password on a user's behalf; each person gets a one-time email link
to set their own password and enrol MFA. Application-tier permissions
(`lunchify`'s `super-admin` / `restaurant-manager` / `employee`) are granted
to **groups** (`/App-Access/Lunchify/*`), never to individual users — see
`docs/PHASE-1-REALM.md`.

## Note on older scripts

`setup-complete.ps1` / `setup.ps1` predate this design — they create local
Keycloak users with passwords on an `@azul-tech.com` domain. They are **not**
part of the current flow; use `configure-realm.sh` + `provision-users.sh`
instead.
