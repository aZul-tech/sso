# HRM ("Azul Tech People") ↔ Azul Tech SSO

Repo: `C:\Users\HP\Downloads\HRM`. Second app on this realm, after Lunchify —
see `docs/lunchify-integration.md` for that one and how it differs from this.

## Why this integration looks different from Lunchify's

Lunchify is a public SPA: the browser talks to Keycloak directly
(`keycloak-js`, PKCE, no client secret), gets an access token, and sends it
as a `Bearer` header on every API call. That's the right shape for an app
with no server-side session of its own.

HRM already has its own server-side session (an httpOnly `hrm_token` cookie,
signed by its own `JWT_SECRET`) and holds sensitive personal data (IDs,
contracts, payroll) behind Admin/HR/Employee roles stored in its own
database. For that shape, doing the Authorization Code exchange **on the
server**, with a confidential client secret the browser never sees, and then
issuing HRM's own existing session cookie, is the better fit — it's strictly
more contained than handing the browser a Keycloak token, and every existing
route (`requireAuth`, `requireRole`, every Admin/HR/Employee check) needed
**zero changes**.

## Provisioning policy — SSO signs in, it does not sign up

Unlike Lunchify (any `@azultech.rw` account auto-provisions as EMPLOYEE on
first SSO login), **HRM never auto-creates an account from SSO**. An Admin
still creates every login (Admin/HR/Employee) deliberately in **User
Accounts**, exactly as before. SSO is matched to an existing HRM account by
email; if there isn't one, the person is sent back to the login page with
*"Your Azul Tech SSO account isn't linked to an HRM login. Ask your Admin to
create one for you first."* This matches HRM's existing philosophy (every
login is a deliberate grant) and keeps Keycloak out of the Admin/HR/Employee
role decision for a system that holds this much sensitive data.

## Keycloak client

`hrm` — **confidential** (has a secret), OpenID Connect, Standard Flow only,
PKCE **S256** required, no direct grants, no service account. Registered
with the (rewritten) `register-app.sh`:

```bash
cd sso
./keycloak/scripts/register-app.sh hrm "Azul Tech People" "http://localhost:4000/api/auth/sso/callback"
```

Re-running it updates settings without rotating the secret. To deliberately
rotate the secret: `kcadm.sh create clients/<id>/client-secret` (see the
script) — remember to update the app's `.env` at the same time.

| Setting | Dev value |
|---|---|
| Redirect URI | `http://localhost:4000/api/auth/sso/callback` — the **browser-facing** origin. HRM normally runs as a single production-mode container (`docker compose up`, no separate Vite dev server), so this is the container's own published port. If you instead run HRM with `npm run dev` (Vite on :5173 proxying `/api` to :4000), re-register with `http://localhost:5173/api/auth/sso/callback` instead — Keycloak only accepts an exact match, so the two modes need re-registering when you switch between them. |
| Web origins | none — nothing in the browser calls Keycloak directly, so no CORS is needed |

## Server (`server/`)

| File | Role |
|---|---|
| `src/lib/keycloakClient.js` | OIDC discovery + client, via `openid-client` v5 (pinned — the server is CommonJS, v6 is ESM-only). `ssoEnabled()` is false unless all four `KEYCLOAK_*` vars are set. When `KEYCLOAK_SERVER_URL` differs from `KEYCLOAK_ISSUER` (Docker networking), discovery is fetched via the server URL but tokens are verified against the issuer — endpoint URLs are rewritten so HTTP calls reach Keycloak from inside the container. |
| `src/routes/auth.js` | `GET /sso/status` (used by the login page to decide whether to show the button), `GET /sso/login` (builds the PKCE authorization URL, stores `{state, code_verifier}` in a short-lived signed cookie), `GET /sso/callback` (exchanges the code, verifies the ID token, looks up the local user **by email only — never creates one**, mints the same `hrm_token` cookie password login does) |

`server/.env` (see `.env.example`):
```
KEYCLOAK_ISSUER=http://localhost:8081/realms/azultech
KEYCLOAK_CLIENT_ID=hrm
KEYCLOAK_CLIENT_SECRET=<from register-app.sh>
KEYCLOAK_REDIRECT_URI=http://localhost:4000/api/auth/sso/callback
KEYCLOAK_SERVER_URL=http://host.docker.internal:8081
```
`KEYCLOAK_ISSUER` is what Keycloak puts in the `iss` claim of every issued
token — it must match `KC_HOSTNAME_URL` on the Keycloak side. When running
the HRM inside Docker, `localhost` inside the container is itself, so
`KEYCLOAK_SERVER_URL` provides the URL the server actually uses to reach
Keycloak for OIDC discovery (the `extra_hosts` mapping in
`docker-compose.yml` handles the DNS). Outside Docker, leave
`KEYCLOAK_SERVER_URL` blank and it defaults to `KEYCLOAK_ISSUER`.

All four `KEYCLOAK_*` vars blank → SSO routes 404 and the login page shows
only the password form. Nothing else about the server needs to change to
disable it.

## Client (`client/`)

| File | Role |
|---|---|
| `src/pages/Login.jsx` | Fetches `/auth/sso/status` on mount; if enabled, shows a **"Continue with Azul Tech SSO"** button below the existing password form (`window.location.href = '/api/auth/sso/login'` — a real page navigation, not a fetch, since Keycloak's login page needs one). Maps `?sso_error=<code>` (set by the server on failure) to a human message. |

No `keycloak-js` on the client — unlike Lunchify, the browser never talks to
Keycloak's token/userinfo endpoints itself, only follows two redirects.

## Roles

Unchanged from today: Admin/HR/Employee live in HRM's own `users` table.
Keycloak proves *who* someone is (their email); it is not involved in *what*
they're allowed to do. See "Provisioning policy" above.

## Rate limiting

`/sso/login` and `/sso/callback` are not behind `express-rate-limit` the way
`/login` is — there's no password to brute-force here, and Keycloak's own
`bruteForceProtected` covers credential stuffing on its side. Worth revisiting
if this ever looks abused in practice.

## Not done here

- **Single logout.** HRM's own logout only clears `hrm_token`; it doesn't end
  the Keycloak session too. A user who clicks "Continue with Azul Tech SSO"
  again right after logging out will be signed back in silently (still-valid
  Keycloak session) rather than seeing a login prompt. Low-risk for now,
  worth a follow-up (Keycloak's `end_session_endpoint`).
- **Production redirect URI.** Once HRM has a real hostname, register it
  with `register-app.sh` again (updates the existing client, secret stays
  the same) and set `KEYCLOAK_REDIRECT_URI` to match exactly.

## Verified with a real run (2026-09-14)

Built and started the actual `docker compose` container (not `npm run dev`),
and drove the real Authorization Code + PKCE exchange with curl through
Keycloak's actual login form — a disposable Keycloak test user, real
credentials, no mocked steps:

```
GET  /api/auth/sso/login    -> 302 to Keycloak, correct client_id/redirect_uri/PKCE
GET  <Keycloak's login page>  -> 200, real form
POST <form action, real username+password> -> 302 back to HRM's callback with ?code=...
GET  /api/auth/sso/callback -> 302 to /, Set-Cookie: hrm_token=... (Secure; HttpOnly)
GET  /api/auth/me           -> the correct HRM user; audit_log: login_success_sso
```

Also verified the safety property that matters most here: a second Keycloak
user with **no matching HRM account** goes through the identical flow and is
correctly refused — `Location: /login?sso_error=no_account`, no `hrm_token`
issued, no row created in HRM's `users` table, `audit_log` gets
`login_failed_sso`. Both test accounts deleted afterward.

This run is also what caught a real bug in the Docker-discovery path (fixed
in the same session, see the `keycloakClient.js` git history): the
`.well-known` URL built from `KEYCLOAK_SERVER_URL` was missing the realm
path (`/realms/azultech`), so discovery 404'd and `/sso/login` always
returned 503 from inside the container. Fixing that surfaced a second,
subtler issue — Keycloak (hostname-strict off in dev) reflects whatever
host:port a request used into *every* URL in its discovery document,
`issuer` included, so naively trusting that response would have set the
OIDC issuer to the Docker-internal address, which never matches the `iss`
claim on tokens actually issued to the browser. The fix keeps `issuer` and
`authorization_endpoint` rooted at `KEYCLOAK_ISSUER` (browser-facing) and
only `token_endpoint`/`userinfo_endpoint`/`jwks_uri` rooted at
`KEYCLOAK_SERVER_URL` (calls the server makes for itself).
