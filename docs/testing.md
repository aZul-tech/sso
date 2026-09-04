# Testing the SSO flow

Superseded the Zoho-redirect test this doc used to describe — Keycloak is
now the identity provider itself, so there's no upstream hop to follow.
Every step below has actually been run end-to-end (Playwright, real browser,
no mocked steps) against a from-scratch realm; this is the same sequence.

## 0. Bring everything up

```bash
cd sso
docker compose up -d                           # Keycloak, Postgres, MailHog
curl -s http://localhost:8081/realms/azultech/.well-known/openid-configuration | grep issuer
#  -> "issuer":"http://localhost:8081/realms/azultech"

./keycloak/scripts/configure-realm.sh
./keycloak/scripts/provision-users.sh keycloak/scripts/pilot-users.csv

cd "../lunch app/server" && npm run dev         # :3001
cd "../lunch app/client" && npm run dev         # :5173
```

## 1. Onboarding (no-password, self-service)

1. Open MailHog: `http://localhost:8025`. Each provisioned user has an
   "Update Your Account" email with a one-time link.
2. Click it. First screen: **Click here to proceed** (consumes the
   action-token).
3. Set a password (this becomes the user's real Keycloak password — nobody
   else ever knows it).
4. `Unable to scan?` on the TOTP screen reveals the raw secret; enrol with
   any authenticator app (or compute a code from the secret directly —
   RFC 6238, HMAC-SHA1, 6 digits, 30s step — for scripted testing).
5. Recovery-codes screen: check **both** "I have saved these codes
   somewhere safe" — there are two checkboxes on this screen ("...saved
   these codes" and "Sign out from other devices"); only the first gates
   the submit button — then **Complete setup**.
6. Lands on Keycloak's **"Account updated"** page → **« Back to
   Application** returns to Lunchify's redirect URI.

## 2. Full browser login (the real test)

1. Open `http://localhost:5173/login`.
2. Click **Continue with Azul Tech SSO** → Keycloak's own branded login
   page (no third-party redirect).
3. Sign in with the password set in step 1.
4. TOTP challenge — enter the current code. If the account has more than
   one enrolled device (e.g. from repeated test runs), Keycloak shows a
   device picker; the wrong one selected here is the most common cause of
   "Invalid authenticator code" in testing, not a real code mismatch.
5. Lands back on Lunchify, on the dashboard matching the token's
   `resource_access.lunchify.roles` claim — `/employee` for `employee`,
   `/admin` for `super-admin`, etc. Verified for both pilot users
   (Ronald → Employee dashboard, Yvonne → Admin panel).

## 3. Backend token verification

```bash
# no token -> 401
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3001/auth/me

# after a browser login, copy the access token from devtools (Network -> any
# /api/* request's Authorization header) and:
curl -s -H "Authorization: Bearer <access-token>" http://localhost:3001/auth/me
```

## 4. Confirm `sub`-keying

The token's `sub` should match the Lunchify user record's `keycloak_sub` —
not looked up by email after the first login:

```bash
grep -A3 '"email": "ronard.musinguzi@azultech.rw"' "../lunch app/server/data/lunchify.json"
```

## 5. Logout

Lunchify logout → Keycloak session ends → next visit to a protected route
requires signing in again.

## 6. Realm-as-code idempotency

```bash
./keycloak/scripts/configure-realm.sh   # first run: creates everything
./keycloak/scripts/configure-realm.sh   # second run: exits 0, reports no changes
```
