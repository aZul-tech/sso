# Phase 1 — the `azultech` realm

Keycloak is the identity provider. Users are local to Keycloak; staff see
**only** Keycloak's own login page (the `azultech` theme). There is no
upstream broker — this supersedes the earlier Zoho-OIDC-broker design
(`docs/zoho-integration.md`, `docs/architecture.md` — kept for history, not
current). Phase 2 makes Zoho a *downstream* SAML application of this realm.

`azultech` (no hyphen) is the permanent realm name — it's baked into the
issuer URL and every client config, so it doesn't change later.

## Exit test (passing)

```bash
cd sso
docker compose down -v && docker compose up -d   # empty server
./keycloak/scripts/configure-realm.sh            # rebuilds the whole realm
./keycloak/scripts/provision-users.sh keycloak/scripts/pilot-users.example.csv
```

Verified 2026-09-04 on a from-scratch Keycloak **26.7.3** (upgraded from the
EOL 20.0.5): realm, roles, groups, the `lunchify` client and its client
roles, and the group→token claim mapping all come back identically on a
second run (`configure-realm.sh` exits 0 reporting no changes — it's
idempotent, safe to re-run against a live realm). Nothing in this realm
exists only as clicks in the admin console.

Separately verified end-to-end with real, unbypassed browser tests
(Playwright, no mocked steps) for both pilot users — see "Onboarding" and
"MFA" below.

## Group / role model

Rene's correction from the first pass: groups model the **organisation**
(they are not roles), and realm roles are reserved for genuinely
cross-cutting concerns only. App-tier concepts live as **client roles** on
that app's own client, and permissions are granted to **groups**, never
directly to users — so an access review is "list the group's members," not
clicking through users one at a time.

| Layer | Purpose | Values |
|---|---|---|
| **Realm role** | cross-cutting only | `staff`, `contractor`, `platform-admin` |
| **Group — `/Departments/*`** | org structure (Executive, Engineering, ...); parent grants `staff`, inherited by subgroups | e.g. `/Departments/Engineering` |
| **Group — `/Platform-Admins`** | Keycloak operators — named personal accounts, never shared, separate from any app's own admin role | grants `platform-admin` + the built-in `realm-management`/`realm-admin` client role |
| **Group — `/App-Access/<App>/<Tier>`** | entitlement to one app, at one tier | e.g. `/App-Access/Lunchify/SuperAdmins` |
| **Client role** (per app, e.g. `lunchify`) | in-app permission, scoped to that client's own token claim | `lunchify`: `super-admin`, `restaurant-manager`, `employee` |

`/App-Access/Lunchify/*` groups carry the matching `lunchify` client role
(`super-admin` / `restaurant-manager` / `employee`), assigned to the group,
not the user. Client roles are scoped to their own client
(`resource_access.<clientId>.roles`), so a second app (Taqwa, Fikia, the HR
system) defines its own roles without touching or colliding with Lunchify's.

Keycloak's own admin role (`platform-admin` + `realm-management`) is kept
strictly separate from any app's admin role (`lunchify`'s `super-admin`) —
being a Keycloak operator does not imply being a Lunchify admin, or vice
versa.

## Token claim contract

Standard Keycloak OIDC claims — no invented top-level claims, so any
standard OIDC library on a future app reads the token with zero
special-casing:

| Claim | Source | Notes |
|---|---|---|
| `sub` | Keycloak standard | **the only claim an app may key its user records on** — email/username change, `sub` doesn't |
| `email`, `preferred_username` | Keycloak standard | identity display only, never a lookup key |
| `groups` | group-membership mapper on the `lunchify` client | e.g. `["/App-Access/Lunchify/SuperAdmins", "/Departments/Executive"]` |
| `department` | user-attribute mapper on the `lunchify` client | e.g. `"Engineering"` — sourced from the `department` user attribute set at provisioning |
| `realm_access.roles` | Keycloak built-in | e.g. `["staff"]` |
| `resource_access.lunchify.roles` | Keycloak built-in, per client | e.g. `["employee"]` — **authoritative role source** for Lunchify (`server/src/middleware/keycloakAuth.js`); a role change in Keycloak (moving a person between `/App-Access/Lunchify/*` groups) takes effect on their next login |

**Lunchify keys `resolveLunchifyUser()` off `sub` first**, falling back to
email only to link up pre-existing records that predate this rule — that
match then backfills `keycloak_sub` so every later lookup goes through
`sub`. Verified: both pilot users' Lunchify records carry the correct
`keycloak_sub` after real SSO login.

## Onboarding — nobody sets a password on a user's behalf

Per Rene's second-pass correction: no temporary passwords, ever — not in a
script's stdout, not in a message, no admin ever knowing a user's
credentials.

`keycloak/scripts/provision-users.sh <csv>` (CSV: `name,email,department,lunchify_group`,
sourced from Yvonne's actual staff roster, not derived from Zoho mailboxes)
creates each user with **no password** and required actions
`VERIFY_EMAIL`, `UPDATE_PASSWORD`, `CONFIGURE_TOTP`,
`CONFIGURE_RECOVERY_AUTHN_CODES`, places them in `/Departments/<department>`
and `/App-Access/Lunchify/<group>`, then triggers Keycloak's
`execute-actions-email` so the person gets a one-time link and sets
everything up themselves. Dev SMTP is MailHog (`http://localhost:8025`);
production points at the real mail server.

One nuance worth documenting: the action-token link's issuer is minted from
whatever URL the Admin API call was made against. `provision-users.sh` talks
to Keycloak over the internal Docker network for everything else, but calls
`execute-actions-email` via the realm's **public** URL specifically — an
internal-only address would mint a link a browser can't validate. Any future
admin tooling that mints links for humans needs to do the same.

**Verified end-to-end for both pilot users** (Playwright, real browser, no
bypassed steps): clicked the emailed link → set their own password → scanned
the TOTP secret and completed enrolment with a real computed one-time code →
confirmed recovery codes → Keycloak's "Account updated" page → redirected to
Lunchify → signed in with the password + TOTP they just set → landed on the
correct role-based dashboard (Ronald: Employee dashboard at `/employee`;
Yvonne: Admin panel at `/admin`, `SuperAdmin`).

## MFA

- OTP policy: TOTP, 6 digits, 30s step (realm default).
- **Mandatory for everyone from day one**, not just admins — every user
  provisioned by `provision-users.sh` gets `CONFIGURE_TOTP` and
  `CONFIGURE_RECOVERY_AUTHN_CODES` as required actions, enforced at the
  Keycloak login itself before any app is reached.
- Recovery codes are issued at enrolment (12 single-use codes, shown once).
  The identity-verified lost-device recovery procedure Rene set as a
  prerequisite for mandating MFA is documented in
  `docs/mfa-recovery-procedure.md`.
- Verified: TOTP is challenged on every login after enrolment (not just the
  first), using a from-scratch RFC 6238 implementation to compute real
  codes against Keycloak-issued secrets — not a bypassed or mocked check.

## Session / token lifetimes

`accessTokenLifespan=300s` (5 min), `ssoSessionIdleTimeout=1800s` (30 min),
`ssoSessionMaxLifespan=36000s` (10h), offline tokens disabled. These already
matched what Rene asked for in the second-pass review — no change needed.

## Realm-as-code

`configure-realm.sh` wraps `kcadm.sh` imperatively but is written to be
idempotent — checking for existing roles/groups/clients/mappers before
creating — and this is now verified, not assumed: running it twice against
the same realm exits 0 the second time reporting no changes.

Rene asked whether a declarative tool (`keycloak-config-cli`, or realm JSON
export/import) would be a better artifact to hand a client or auditor, and
easier to diff in review. Position: yes, and worth adopting — but as a
follow-up after the Tuesday deadline, not a tooling swap under time
pressure. The current script is proven idempotent and is what's been
exit-tested; migrating to `keycloak-config-cli` is a good Phase 1.1 item
once the realm shape is stable.

## Preview features

Keycloak 26.7's preview features (SCIM provisioning, simplified
multi-cluster HA) are **not** enabled in this deployment — confirmed by
inspecting `docker-compose.yml`: no `KC_FEATURES` / `--features` flag is
set anywhere in the Keycloak service definition, so only stable features are
active. Per Rene's instruction, this stays off for this reference
deployment.

## HA

Explicitly **not** a Phase 1 blocker per Rene — single Keycloak node,
single Postgres instance is fine for the pilot. Needed before a third app
migrates onto this realm, not before. Not scoped or built here.

## Fine-grained admin permissions

Delegating per-client role/group-membership management to an app owner
(e.g. letting a Lunchify owner manage `/App-Access/Lunchify/*` membership
without being a `platform-admin`) is supported by Keycloak's fine-grained
admin permissions, scoped to the `lunchify` client. This requires enabling
"Permissions" on the client in the Admin Console (Clients → lunchify →
Advanced → Fine grain permission → Enable) and then granting the specific
generated permissions (e.g. `manage-group-membership.permission.<gid>`) to
the delegated user or group via Authorization → Permissions. This is a
manual admin-console procedure for now — `kcadm.sh` doesn't have first-class
support for the fine-grained-permissions endpoints, so scripting it
declaratively is deferred; noted as a candidate for the
`keycloak-config-cli` migration above.

## Break-glass

`keycloak/scripts/create-break-glass-admin.sh <username>` creates a
realm-local admin account (member of `/Platform-Admins`) with no MFA
required actions and a password generated and shown exactly once, so it
still works if the normal MFA path itself is what's broken. Run it directly
in your own terminal, not through anything whose output you don't fully
control — the point of "break-glass" is this credential lives in a sealed
store (physical safe / offline password manager), not day-to-day use, not
git, not chat.

## Patching cadence

Proposed cadence for the ISMS is in `docs/patching-cadence.md`.

## Still open (tracked, not done here)

- HA (2+ Keycloak nodes, Postgres failover) — infra, needs servers; not a
  Phase 1 blocker (see above)
- Admin-event archival to an append-only store, version-controlled routine
  entitlement changes — flagged by Rene as Finance/HR-migration-time work,
  not needed now
- `keycloak-config-cli` migration (see "Realm-as-code" above)
- Fine-grained admin permissions scripted as code, rather than a manual
  console procedure
- Offboarding checklist: disable in Keycloak **and** Zoho same day (interim,
  until Phase 2 removes the second identity store)
- Phase 2: confirm Zoho Directory "Custom Authentication (SAML)" is on the
  plan; build the SAML client
