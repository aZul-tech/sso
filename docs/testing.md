# Testing the SSO flow

## 0. Prerequisites up

```bash
# Keycloak + Postgres
cd C:\Users\HP\Downloads\sso
docker compose up -d
curl -s http://localhost:8081/realms/azul-tech/.well-known/openid-configuration | grep issuer
#  -> "issuer":"http://localhost:8081/realms/azul-tech"

# Lunchify API
cd "C:\Users\HP\Downloads\lunch app\server" && npm start          # :3001

# Lunchify web
cd "C:\Users\HP\Downloads\lunch app\client" && npm run dev         # :5173
```

## 1. Keycloak → Zoho redirect (no browser needed)

```bash
curl -s -o /dev/null -w "%{redirect_url}\n" \
 "http://localhost:8081/realms/azul-tech/protocol/openid-connect/auth?client_id=lunchify&redirect_uri=http%3A%2F%2Flocalhost%3A5173%2F&response_type=code&scope=openid&state=x&kc_idp_hint=zoho&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256"
```
Follow the `broker/zoho/login` hop — it must land on
`https://accounts.zoho.com/oauth/v2/auth?...client_id=<your zoho id>...`.
If Zoho shows "invalid redirect_uri", the redirect URI in the Zoho API Console
doesn't match `http://localhost:8081/realms/azul-tech/broker/zoho/endpoint`.

## 2. Full browser login (the real test)

1. Open `http://localhost:5173` → redirected to `/login`.
2. Click **Continue with Azul Tech SSO**.
3. Keycloak sends you straight to Zoho → sign in with a real `@azultech.rw` Zoho
   Mail account (+ MFA if enabled).
4. Back to Lunchify, logged in, routed to `/employee` (or the role's dashboard).
5. Check the Keycloak user was created: Admin console → `azul-tech` → Users.

## 3. Domain guard rejects outsiders

Repeat step 2 with a **non-`@azultech.rw`** Zoho account. Expected: after Zoho auth,
Keycloak shows *"Your account (…) is not part of Azul Tech and cannot use this
sign-in."* and **no** user is created.

Guard logs:
```bash
docker logs azul-tech-keycloak 2>&1 | grep azul-domain-guard
```

## 4. Backend token verification

```bash
# no token -> 401
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3001/auth/me

# after a browser login, copy the access token from devtools (Network -> /auth/me
# request header) and:
curl -s -H "Authorization: Bearer <access-token>" http://localhost:3001/auth/me
```

## 5. Logout

Lunchify logout → Keycloak session ends → next visit requires Zoho login again.
