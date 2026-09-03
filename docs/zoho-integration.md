# Zoho ↔ Keycloak Integration (Azul Tech SSO)

> **Direction of trust:** Zoho is the identity provider. Keycloak **brokers** to Zoho.
> Employees keep their existing Zoho Mail password — they never set a Keycloak password.
>
> (An earlier draft of this doc described the opposite setup — Keycloak as IdP and
> Zoho Mail as a SAML service provider. That is **not** what we run. See
> `docs/architecture.md`.)

```
Browser ─▶ App (e.g. Lunchify)
             │  not logged in
             ▼
        Keycloak  realm: azul-tech
             │  kc_idp_hint=zoho  →  straight to Zoho
             ▼
        accounts.zoho.com  ← employee types their Zoho Mail email + password (+ MFA)
             │  authorization code
             ▼
        Keycloak  /broker/zoho/endpoint
             │  • verifies tokens from Zoho
             │  • Email Domain Guard: reject if not @azultech.rw
             │  • first login → create local user from Zoho claims
             ▼
        App  ← Keycloak access + ID + refresh tokens (RS256)
```

## What was configured in Keycloak

All of this is reproduced by `keycloak/scripts/configure-realm.sh` (the source of truth).

### 1. Zoho registered as an OpenID Connect identity provider

| Setting | Value |
|---|---|
| Alias | `zoho` |
| Provider | OpenID Connect v1.0 |
| Authorization URL | `https://accounts.zoho.com/oauth/v2/auth` |
| Token URL | `https://accounts.zoho.com/oauth/v2/token` |
| User Info URL | `https://accounts.zoho.com/oauth/v2/userinfo` |
| JWKS URL | `https://accounts.zoho.com/oauth/v2/keys` |
| Issuer | `https://accounts.zoho.com` |
| Client authentication | `Client secret sent as POST` |
| Client ID / Secret | from the Zoho API Console (`ZOHO_CLIENT_ID` / `ZOHO_CLIENT_SECRET` in `.env`) |
| Scopes | `openid email profile` |
| PKCE | enabled, S256 |
| Trust email | ON |
| Sync mode | FORCE |

> **Data center:** the URLs above are the US/global DC. For `.eu` / `.in` / `.com.au`
> change `ZOHO_ACCOUNTS_HOST` in `.env` and re-run `configure-realm.sh`.

### 2. Attribute mappers (`zoho` → local user)

`email → email`, `given_name → firstName`, `family_name → lastName`,
`${CLAIM.email} → username`.

### 3. Company domain restriction

`keycloak/providers-src/domain-check.js`, packaged as
`providers/azul-domain-guard.jar` (a `scripts`-feature script authenticator).

- It is **step 0 (REQUIRED)** of the `first broker login azul` authentication flow.
- It reads the incoming Zoho email and rejects anything not ending in a domain
  listed in the realm attribute `allowedEmailDomains` (currently `azultech.rw`)
  **before** a Keycloak user is created.
- Belt-and-braces: every app should also check the `email` claim domain
  (Lunchify does — `ALLOWED_EMAIL_DOMAIN`).

## What you do in the Zoho API Console

1. `https://api-console.zoho.com` → **Add Client → Server-based Applications**
2. Client Name: `Azul Tech SSO`
3. Homepage URL: your app URL (dev: `http://localhost:5173`)
4. **Authorized Redirect URIs:**
   `http://localhost:8081/realms/azul-tech/broker/zoho/endpoint`
   (add the production URL — `https://sso.<domain>/realms/azul-tech/broker/zoho/endpoint` — later)
5. Copy the **Client ID** and **Client Secret** into `sso/.env`, then run
   `keycloak/scripts/configure-realm.sh`.

## Provisioning & roles

- Users are auto-created in Keycloak on first Zoho login (the domain guard makes
  this safe).
- Application-specific role/permission data stays **in each app**, keyed by email.
  Keycloak only proves identity. (Optionally, Keycloak groups can carry roles in
  the token later — not required today.)

## Leavers

When Zoho disables an account the user can no longer get a **new** Keycloak
session. Existing access tokens live until expiry (default 5 min) and the
Keycloak SSO session until its idle/max timeout — keep those short.
