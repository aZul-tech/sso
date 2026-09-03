# Lunchify ↔ Azul Tech SSO

Lunchify is the reference integration. Repo: `C:\Users\HP\Downloads\lunch app`.

## Keycloak client

`lunchify` — public, OpenID Connect, Standard flow only, PKCE **S256** required.

| Setting | Dev value |
|---|---|
| Root/Home URL | `http://localhost:5173` |
| Valid redirect URIs | `http://localhost:5173/*` |
| Valid post-logout redirect URIs | `http://localhost:5173/*` |
| Web origins | `http://localhost:5173` |

## Frontend (`client/`)

| File | Role |
|---|---|
| `src/keycloak.js` | `keycloak-js` instance + `IDP_HINT` (`zoho`) |
| `src/main.jsx` | `keycloak.init({ onLoad: 'check-sso', pkceMethod: 'S256', silentCheckSsoRedirectUri })`, background token refresh |
| `public/silent-check-sso.html` | silent SSO check page |
| `src/context/AuthContext.jsx` | `login()` = `keycloak.login({ idpHint: 'zoho' })`; `apiFetch` attaches a fresh token; `demoLogin()` is **dev-only** |
| `src/pages/LoginPage.jsx` | one "Continue with Azul Tech SSO" button; email + demo accounts render only when `import.meta.env.DEV` |

`client/.env`:
```
VITE_KEYCLOAK_URL=http://localhost:8081
VITE_KEYCLOAK_REALM=azul-tech
VITE_KEYCLOAK_CLIENT_ID=lunchify
```

## Backend (`server/`)

| File | Role |
|---|---|
| `src/middleware/keycloakAuth.js` | verify Keycloak RS256 access token via JWKS; enforce `@azultech.rw`; map `email` → Lunchify user (auto-create EMPLOYEE on first login) |
| `src/middleware/auth.js` | `authenticate` is hybrid: RS256 Keycloak token **or** legacy HS256 demo token |
| `src/routes/sso.js` | `GET /auth/me` returns the Lunchify profile for either token type |

`server/.env`:
```
KEYCLOAK_ISSUER=http://localhost:8081/realms/azul-tech
KEYCLOAK_JWKS_URI=http://localhost:8081/realms/azul-tech/protocol/openid-connect/certs
KEYCLOAK_ALLOWED_AZP=lunchify
ALLOWED_EMAIL_DOMAIN=azultech.rw
```

## Roles

Kept in the Lunchify DB, keyed by email (`EMPLOYEE` / `RESTAURANT_MANAGER` /
`SUPER_ADMIN`). New SSO users default to `EMPLOYEE`; an admin promotes them in the
Employees screen. Keycloak is not involved in role assignment.

## Known gap

`server/src/db.js` is in-memory and reseeds on restart — SSO users created on
first login do not persist. Replace with a real database before go-live.
