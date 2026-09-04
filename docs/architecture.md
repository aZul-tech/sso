# Azul Tech SSO — Architecture

> **Superseded 2026-09-04 — see `docs/PHASE-1-REALM.md`.** Keycloak is now
> the identity provider (local users, MFA at login); Zoho becomes a
> downstream SAML app in Phase 2. Kept below for history / the reasoning
> that led to the change.

## Decision (2026-09-02): Keycloak brokers to Zoho

Employees already have Zoho Mail accounts on `@azultech.rw`. We want them to sign in
to company apps with **that** account and **that** password — nothing new to set up.

So the trust chain is:

```
company apps  ──trust──▶  Keycloak (realm: azul-tech)  ──brokers to──▶  Zoho (accounts.zoho.com)
   Lunchify                    the SSO hub                              the password authority
   hrm-app                 issues tokens to apps                        + MFA + the login screen
   finance-app             manages SSO sessions
   projects-mel            enforces @azultech.rw
```

Keycloak never sees the Zoho password. It receives signed tokens from Zoho after
Zoho has authenticated the user, then mints its own tokens for the apps.

### Why not the other direction?

Making Keycloak the master identity store (and Zoho Mail a SAML SP of Keycloak)
would force every employee to set a Keycloak password or require a directory
federation — the opposite of the goal. Revisit only if Azul Tech leaves Zoho as
its identity source.

## Components

| Component | Where | Notes |
|---|---|---|
| Keycloak | `azul-tech-keycloak` container, `:8081` | image 20.0.5, `start-dev`, realm `azul-tech` |
| Postgres | `azul-tech-postgres` container | Keycloak's DB; realm config persists here |
| Zoho IdP | Keycloak → Identity providers → `zoho` | OIDC, PKCE S256 |
| Email Domain Guard | `providers/azul-domain-guard.jar` | script authenticator, step 0 of `first broker login azul` |
| `lunchify` client | Keycloak → Clients | public SPA, Authorization Code + PKCE |
| `hrm-app`/`finance-app`/`projects-mel` | Keycloak → Clients | confidential OIDC (see `oidc-integration.md`) |

## Realm configuration is code

`keycloak/scripts/configure-realm.sh` is idempotent and is the **source of truth**.
The full realm JSON export is git-ignored (contains secrets + password hashes).

To rebuild the realm from scratch on a clean machine:

```bash
cd sso
cp .env.example .env            # fill in ZOHO_CLIENT_ID / ZOHO_CLIENT_SECRET / passwords
./keycloak/scripts/build-providers.sh      # or build-providers.ps1 on Windows
docker compose up -d
./keycloak/scripts/configure-realm.sh
```

## Token flow (Lunchify example)

1. SPA loads, `keycloak-js` `check-sso` → not authenticated.
2. User clicks **Continue with Azul Tech SSO** → `keycloak.login({ idpHint: 'zoho' })`.
3. Keycloak → Zoho login → back to Keycloak `/broker/zoho/endpoint`.
4. First login: Email Domain Guard runs → user created from Zoho claims.
5. Keycloak redirects to the SPA with an auth code; `keycloak-js` exchanges it
   (PKCE) for access / ID / refresh tokens.
6. SPA calls `GET /auth/me` with `Authorization: Bearer <access token>`.
7. Lunchify server (`server/src/middleware/keycloakAuth.js`) verifies the token
   against Keycloak's JWKS, checks the `@azultech.rw` domain, maps `email` → Lunchify
   user (creating an EMPLOYEE record on first login), returns the profile.
8. `keycloak-js` silently refreshes the access token in the background.

## Production notes (not yet deployed)

- Run Keycloak with `start` (not `start-dev`), behind nginx + TLS.
- Set `KC_HOSTNAME_URL=https://sso.<domain>` and `KC_HOSTNAME_STRICT=true`.
- Add production redirect URIs in both Keycloak (`lunchify` client) and the Zoho
  API Console (`.../broker/zoho/endpoint`).
- Plan a Keycloak 20 → current upgrade.
