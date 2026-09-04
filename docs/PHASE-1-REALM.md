# Phase 1 — the `azul-tech` realm

Keycloak is the identity provider. Users are local to Keycloak; staff see
**only** Keycloak's own login page (the `azultech` theme). There is no
upstream broker — this supersedes the earlier Zoho-OIDC-broker design
(`docs/zoho-integration.md`, `docs/architecture.md` — kept for history, not
current). Phase 2 makes Zoho a *downstream* SAML application of this realm.

## Exit test (passing)

```bash
cd sso
docker compose down -v && docker compose up -d   # empty server
./keycloak/scripts/configure-realm.sh            # rebuilds the whole realm
./keycloak/scripts/provision-users.sh keycloak/scripts/pilot-users.csv
```
Verified 2026-09-04 on a from-scratch Keycloak **26.7.3** (upgraded from the
EOL 20.0.5): realm, roles, groups, the `lunchify` client and its client
roles, and the group→token claim mapping all come back identically. Nothing
in this realm exists only as clicks in the admin console.

## Group / role model

| Layer | Purpose | Values |
|---|---|---|
| **Realm role** | cross-app tier | `admin`, `employee` |
| **Group** | org membership; grants the realm role | `/Admins` → `admin`, `/Employees` → `employee` |
| **Client role** (per app, e.g. `lunchify`) | in-app permission | `lunchify`: `super-admin`, `restaurant-manager`, `employee` |

Client roles are scoped to their own client (`resource_access.<clientId>.roles`),
so a second app (Taqwa, Fikia, the HR system) defines its own roles without
touching or colliding with Lunchify's. This is the answer to "claim naming
gets painful once four apps consume it."

Department-level subgroups are deferred to Phase 3 (HR system integration) —
kept flat for now rather than guessed at.

## Token claim contract

| Claim | Source | Notes |
|---|---|---|
| `email`, `given_name`, `family_name`, `preferred_username` | Keycloak standard | unchanged if we add more apps |
| `groups` | realm group-membership mapper on the `lunchify` client | e.g. `["/Admins"]` |
| `realm_access.roles` | Keycloak built-in | e.g. `["admin"]` |
| `resource_access.lunchify.roles` | Keycloak built-in, per client | e.g. `["super-admin"]` — **authoritative role source** for Lunchify (`server/src/middleware/keycloakAuth.js`); a role change in Keycloak takes effect on the person's next login |

No custom top-level claims were invented — this is Keycloak's default token
shape, so any standard OIDC library on a future app reads it with zero
special-casing.

## MFA

- OTP policy: TOTP, 6 digits, 30s step (realm default).
- `Admins` group members get `CONFIGURE_TOTP` as a **required action** at
  provisioning — enforced at the Keycloak login itself, before any app is
  reached. Verified: an admin account cannot pass login with password alone;
  Keycloak challenges for the one-time code on every subsequent login too.
- `Employees` are not yet required to enrol MFA. To make it mandatory for
  everyone (the Phase 2 cutover target), add `CONFIGURE_TOTP` to
  `provision-users.sh`'s Employees branch, or set it as a realm-wide default
  required action.

## Session / token lifetimes

`accessTokenLifespan=300s`, `ssoSessionIdleTimeout=1800s` (30 min),
`ssoSessionMaxLifespan=36000s` (10h). Adjustable in `configure-realm.sh`;
flagged for Rene to confirm against the eventual ISO 27001 session policy.

## User provisioning

`keycloak/scripts/provision-users.sh <csv>` — CSV of `name,email,group,lunchify_role`.
Creates the user with a random 16-char temporary password (`UPDATE_PASSWORD`
required action forces them to set their own on first login) and, for
`Admins`, also requires MFA enrolment before anything else. No SMTP is wired
up yet, so the script prints each temp password once for out-of-band relay —
wiring real email delivery is an open item before the full staff rollout.

## Break-glass

Not yet implemented: a realm-local admin account excluded from MFA
enforcement, credentials sealed/stored outside the normal secret store. Add
before Phase 1 is considered "live" per Rene's ask.

## Still open (tracked, not done here)

- HA (2+ Keycloak nodes, Postgres failover) — infra, needs servers
- Tested backup/restore, key rotation schedule
- Break-glass account
- SMTP for password-reset / provisioning emails
- Offboarding checklist: disable in Keycloak **and** Zoho same day (interim,
  until Phase 2 removes the second identity store)
- Phase 2: confirm Zoho Directory "Custom Authentication (SAML)" is on the
  plan; build the SAML client
