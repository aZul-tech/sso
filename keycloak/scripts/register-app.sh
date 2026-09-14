#!/usr/bin/env bash
#
# register-app.sh — register (or update) one OIDC client for an app that
# authenticates through Azul Tech SSO. Confidential client (the app's own
# server holds the secret, never the browser) + Standard Flow + PKCE S256 —
# the same posture as every other client in this realm.
#
# Rewritten 2026-09-14: the previous version called the Admin REST API
# directly over curl + jq, defaulted to the retired "azul-tech" realm name,
# and needed jq installed on whatever machine ran it. This version goes
# through kcadm.sh inside the Keycloak container instead — same pattern as
# configure-realm.sh, same .env, no extra tools required on the host, and
# idempotent (re-running updates settings without rotating an already-issued
# secret).
#
# Usage:
#   ./keycloak/scripts/register-app.sh <client-id> "<Display Name>" <redirect-uri> [web-origin]
#
# Example (a server-rendered app doing the Authorization Code exchange
# itself — no browser-side calls to Keycloak, so no web-origin needed):
#   ./keycloak/scripts/register-app.sh hrm "Azul Tech People" \
#     "http://localhost:5173/api/auth/sso/callback"
#
# Example (a public SPA calling Keycloak endpoints directly from the
# browser, like lunchify — needs its origin in webOrigins for CORS):
#   ./keycloak/scripts/register-app.sh some-spa "Some SPA" \
#     "http://localhost:5174/*" "http://localhost:5174"
#
# Reads ../../.env for KC_REALM / KC_CONTAINER / KEYCLOAK_ADMIN / KEYCLOAK_ADMIN_PASSWORD
# (same variables configure-realm.sh uses).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ $# -lt 3 ]; then
  echo "Usage: $0 <client-id> \"<Display Name>\" <redirect-uri> [web-origin]"
  echo "Example: $0 hrm \"Azul Tech People\" \"http://localhost:5173/api/auth/sso/callback\""
  exit 1
fi

CLIENT_ID="$1"
CLIENT_NAME="$2"
REDIRECT_URI="$3"
WEB_ORIGIN="${4:-}"

# shellcheck disable=SC1091
set -a; source "$ROOT_DIR/.env"; set +a

REALM="${KC_REALM:-azultech}"
CONTAINER="${KC_CONTAINER:-azul-tech-keycloak}"
ADMIN="${KEYCLOAK_ADMIN:-admin}"
ADMIN_PW="${KEYCLOAK_ADMIN_PASSWORD:?set KEYCLOAK_ADMIN_PASSWORD in .env}"

export MSYS_NO_PATHCONV=1
kc() { docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh "$@"; }

echo ">> authenticating"
kc config credentials --server http://localhost:8080 --realm master --user "$ADMIN" --password "$ADMIN_PW" >/dev/null

CID=$(kc get clients -r "$REALM" -q "clientId=$CLIENT_ID" --fields id --format csv --noquotes 2>/dev/null || true)
JUST_CREATED=0
if [ -z "$CID" ]; then
  echo ">> creating client '$CLIENT_ID'"
  kc create clients -r "$REALM" -s "clientId=$CLIENT_ID" -s "name=$CLIENT_NAME" >/dev/null
  CID=$(kc get clients -r "$REALM" -q "clientId=$CLIENT_ID" --fields id --format csv --noquotes)
  JUST_CREATED=1
else
  echo ">> client '$CLIENT_ID' exists — updating settings, secret is left untouched"
fi

WEB_ORIGINS_JSON="[]"
[ -n "$WEB_ORIGIN" ] && WEB_ORIGINS_JSON="[\"$WEB_ORIGIN\"]"

echo ">> configuring '$CLIENT_ID' (confidential, Standard Flow + PKCE S256, no direct-grant/service-account)"
kc update "clients/$CID" -r "$REALM" \
  -s enabled=true -s "name=$CLIENT_NAME" -s protocol=openid-connect \
  -s 'publicClient=false' -s 'standardFlowEnabled=true' \
  -s 'directAccessGrantsEnabled=false' -s 'implicitFlowEnabled=false' -s 'serviceAccountsEnabled=false' \
  -s "redirectUris=[\"$REDIRECT_URI\"]" \
  -s "webOrigins=$WEB_ORIGINS_JSON" \
  -s 'attributes."pkce.code.challenge.method"=S256' >/dev/null

# Only mint a secret the first time this client is created — regenerating it
# on every re-run would silently break whatever app already has the old one
# in its .env. Rotate deliberately: `kc create clients/<id>/client-secret`.
if [ "$JUST_CREATED" = "1" ]; then
  echo ">> generating client secret"
  kc create "clients/$CID/client-secret" -r "$REALM" >/dev/null
fi
SECRET=$(kc get "clients/$CID/client-secret" -r "$REALM" --fields value --format csv --noquotes)

PUBLIC_URL="${KC_HOSTNAME_URL:-http://localhost:${KC_HTTP_PORT:-8081}}"

echo ""
echo "========================================"
echo " Client '$CLIENT_ID' ready in realm '$REALM'"
echo "========================================"
echo "Client ID:      $CLIENT_ID"
echo "Client Secret:  $SECRET"
echo "Redirect URI:   $REDIRECT_URI"
echo ""
echo "Issuer:         $PUBLIC_URL/realms/$REALM"
echo "JWKS URI:       $PUBLIC_URL/realms/$REALM/protocol/openid-connect/certs"
echo "Auth URL:       $PUBLIC_URL/realms/$REALM/protocol/openid-connect/auth"
echo "Token URL:      $PUBLIC_URL/realms/$REALM/protocol/openid-connect/token"
echo ""
echo "Put the secret straight into that app's own .env (never into this repo,"
echo "never into chat) and discard this terminal output once it's copied."
echo "========================================"
