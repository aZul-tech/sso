#!/usr/bin/env bash
#
# configure-realm.sh — idempotent configuration of the "azul-tech" realm.
#
# This is the SOURCE OF TRUTH for how the realm is wired for SSO:
#   - Zoho as an upstream OIDC identity provider (users keep their Zoho Mail password)
#   - attribute mappers (email / given_name / family_name / username)
#   - a "first broker login azul" flow whose first step is the Email Domain Guard
#     script authenticator (denies any non-@azultech.rw account before a user is created)
#   - the "lunchify" public SPA client (Authorization Code + PKCE S256)
#
# Requirements: the Keycloak container is up (docker compose up -d) and the
# script authenticator JAR has been built (see build-providers.sh).
#
# Usage:  ./keycloak/scripts/configure-realm.sh
# Reads:  ../../.env  (ZOHO_CLIENT_ID, ZOHO_CLIENT_SECRET, ZOHO_ACCOUNTS_HOST,
#                      ALLOWED_EMAIL_DOMAINS, KEYCLOAK_ADMIN[_PASSWORD], KC_REALM)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
set -a; source "$ROOT_DIR/.env"; set +a

REALM="${KC_REALM:-azul-tech}"
CONTAINER="${KC_CONTAINER:-azul-tech-keycloak}"
ADMIN="${KEYCLOAK_ADMIN:-admin}"
ADMIN_PW="${KEYCLOAK_ADMIN_PASSWORD:?set KEYCLOAK_ADMIN_PASSWORD in .env}"
ZOHO_HOST="${ZOHO_ACCOUNTS_HOST:-accounts.zoho.com}"
ZOHO_ID="${ZOHO_CLIENT_ID:?set ZOHO_CLIENT_ID in .env}"
ZOHO_SECRET="${ZOHO_CLIENT_SECRET:?set ZOHO_CLIENT_SECRET in .env}"
DOMAINS="${ALLOWED_EMAIL_DOMAINS:-azultech.rw}"
SPA_REDIRECT="${LUNCHIFY_REDIRECT:-http://localhost:5173/*}"
SPA_ORIGIN="${LUNCHIFY_ORIGIN:-http://localhost:5173}"

export MSYS_NO_PATHCONV=1
kc() { docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh "$@"; }

echo ">> authenticating"
kc config credentials --server http://localhost:8080 --realm master --user "$ADMIN" --password "$ADMIN_PW" >/dev/null

# ---------------------------------------------------------------------------
# Realm — create it if this is a fresh Keycloak (prod `start --optimized` does
# not auto-import). Base security posture lives here so there is no realm JSON
# (with signing keys / secrets) to keep in git.
# ---------------------------------------------------------------------------
if kc get "realms/$REALM" >/dev/null 2>&1; then
  echo ">> realm '$REALM' exists"
else
  echo ">> creating realm '$REALM'"
  kc create realms \
    -s "realm=$REALM" -s 'enabled=true' \
    -s 'displayName=Azul Tech' -s 'displayNameHtml=<strong>Azul Tech</strong>' \
    -s 'sslRequired=external' \
    -s 'registrationAllowed=false' -s 'resetPasswordAllowed=true' \
    -s 'loginWithEmailAllowed=true' -s 'duplicateEmailsAllowed=false' \
    -s 'bruteForceProtected=true' \
    -s 'accessTokenLifespan=300' \
    -s 'ssoSessionIdleTimeout=1800' -s 'ssoSessionMaxLifespan=36000' \
    -s 'internationalizationEnabled=true' -s 'supportedLocales=["en","sw"]' -s 'defaultLocale=en' >/dev/null
fi

echo ">> realm attribute: allowedEmailDomains=$DOMAINS"
kc update "realms/$REALM" -s "attributes.allowedEmailDomains=$DOMAINS" >/dev/null

echo ">> login theme: azultech (deep navy / royal-blue background)"
kc update "realms/$REALM" -s 'loginTheme=azultech' >/dev/null
# Also brand the admin-console sign-in (master realm) so every login page matches.
kc update "realms/master" -s 'loginTheme=azultech' >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Purge artifacts of the deprecated setup-complete.ps1 (local password users,
# placeholder app clients with wildcard redirect URIs, unused groups). The
# current design has NO local users — everyone authenticates via Zoho — and
# only real, registered apps get a client. Safe to re-run.
# ---------------------------------------------------------------------------
echo ">> purging deprecated setup-complete.ps1 artifacts"
for c in hrm-app finance-app projects-mel zoho-mail; do
  cid=$(kc get clients -r "$REALM" -q "clientId=$c" --fields id --format csv --noquotes 2>/dev/null || true)
  [ -n "$cid" ] && { kc delete "clients/$cid" -r "$REALM" >/dev/null 2>&1 && echo "   - removed client $c"; } || true
done
for u in ronald hr.user finance.user pm.user dev.user; do
  uid=$(kc get users -r "$REALM" -q "username=$u" --fields id --format csv --noquotes 2>/dev/null | head -1 || true)
  [ -n "$uid" ] && { kc delete "users/$uid" -r "$REALM" >/dev/null 2>&1 && echo "   - removed user $u"; } || true
done
for g in "Azul Tech Admins" "Development Team" "Finance Department" "HR Department" "Projects Team"; do
  gid=$(kc get groups -r "$REALM" -q "search=$g" --fields id,name --format csv --noquotes 2>/dev/null | awk -F, -v n="$g" '$2==n{print $1}' | head -1 || true)
  [ -n "$gid" ] && { kc delete "groups/$gid" -r "$REALM" >/dev/null 2>&1 && echo "   - removed group $g"; } || true
done

# ---------------------------------------------------------------------------
# "first broker login azul" flow  +  Email Domain Guard  (idempotent)
# Must exist BEFORE the Zoho IdP, which references it by alias.
# ---------------------------------------------------------------------------
if ! kc get authentication/flows -r "$REALM" 2>/dev/null | grep -q '"first broker login azul"'; then
  echo ">> copying 'first broker login' -> 'first broker login azul'"
  kc create "authentication/flows/first%20broker%20login/copy" -r "$REALM" -s 'newName=first broker login azul' >/dev/null
fi

FLOW="first%20broker%20login%20azul"
GUARD_NAME="Azul Tech Email Domain Guard"

# "<id>,<displayName>,<requirement>" per execution — CSV avoids the SIGPIPE /
# multi-line-JSON parsing that made the old version abort under `set -o pipefail`.
flow_execs() {
  kc get "authentication/flows/$FLOW/executions" -r "$REALM" \
     --fields id,displayName,requirement --format csv --noquotes 2>/dev/null || true
}

guard_ids=$(flow_execs | awk -F, -v n="$GUARD_NAME" '$2==n{print $1}')
if [ -z "$guard_ids" ]; then
  echo ">> adding Email Domain Guard execution"
  kc create "authentication/flows/$FLOW/executions/execution" -r "$REALM" -s 'provider=script-domain-check.js' >/dev/null
  guard_ids=$(flow_execs | awk -F, -v n="$GUARD_NAME" '$2==n{print $1}')
fi

# Keep the first guard execution; drop any duplicates from earlier partial runs.
printf '%s\n' "$guard_ids" | tail -n +2 | while read -r dup; do
  [ -n "$dup" ] && { kc delete "authentication/executions/$dup" -r "$REALM" >/dev/null 2>&1 \
      && echo "   - removed duplicate guard execution"; } || true
done

GUARD_ID=$(printf '%s\n' "$guard_ids" | awk 'NF{print;exit}')
REVIEW_ID=$(flow_execs | awk -F, '$2=="Review Profile"{print $1; exit}')

# Guard REQUIRED + first; Review Profile DISABLED
[ -n "$GUARD_ID" ]  && kc update "authentication/flows/$FLOW/executions" -r "$REALM" -b "{\"id\":\"$GUARD_ID\",\"requirement\":\"REQUIRED\"}" >/dev/null
[ -n "$REVIEW_ID" ] && kc update "authentication/flows/$FLOW/executions" -r "$REALM" -b "{\"id\":\"$REVIEW_ID\",\"requirement\":\"DISABLED\"}" >/dev/null
if [ -n "$GUARD_ID" ]; then
  for _ in 1 2 3 4 5; do kc create "authentication/executions/$GUARD_ID/raise-priority" -r "$REALM" >/dev/null 2>&1 || true; done
fi

# ---------------------------------------------------------------------------
# Zoho identity provider
# ---------------------------------------------------------------------------
if kc get "identity-provider/instances/zoho" -r "$REALM" >/dev/null 2>&1; then
  echo ">> updating Zoho identity provider"
  ACTION=update; TARGET="identity-provider/instances/zoho"
else
  echo ">> creating Zoho identity provider"
  ACTION=create; TARGET="identity-provider/instances"
fi
kc "$ACTION" "$TARGET" -r "$REALM" \
  -s 'alias=zoho' -s 'providerId=oidc' -s 'displayName=Zoho' -s 'enabled=true' \
  -s 'trustEmail=true' -s 'storeToken=false' -s 'updateProfileFirstLoginMode=off' \
  -s 'firstBrokerLoginFlowAlias=first broker login azul' \
  -s "config.clientId=$ZOHO_ID" \
  -s "config.clientSecret=$ZOHO_SECRET" \
  -s 'config.clientAuthMethod=client_secret_post' \
  -s 'config.pkceEnabled=true' -s 'config.pkceMethod=S256' \
  -s 'config.defaultScope=openid email profile' \
  -s 'config.syncMode=FORCE' \
  -s "config.authorizationUrl=https://$ZOHO_HOST/oauth/v2/auth" \
  -s "config.tokenUrl=https://$ZOHO_HOST/oauth/v2/token" \
  -s "config.userInfoUrl=https://$ZOHO_HOST/oauth/v2/userinfo" \
  -s "config.jwksUrl=https://$ZOHO_HOST/oauth/v2/keys" \
  -s "config.issuer=https://$ZOHO_HOST" \
  -s 'config.useJwksUrl=true' -s 'config.validateSignature=true' >/dev/null

echo ">> Zoho attribute mappers"
# Read existing mappers once: lines of "<id> <name>"
MAPPER_LIST=$(kc get "identity-provider/instances/zoho/mappers" -r "$REALM" --format csv --fields id,name --noquotes 2>/dev/null || true)
ensure_mapper() {
  local name="$1" mapper="$2"; shift 2
  local existing
  existing=$(printf '%s\n' "$MAPPER_LIST" | awk -F, -v n="$name" '$2==n{print $1}')
  [ -n "$existing" ] && kc delete "identity-provider/instances/zoho/mappers/$existing" -r "$REALM" >/dev/null 2>&1 || true
  kc create "identity-provider/instances/zoho/mappers" -r "$REALM" \
    -s "name=$name" -s 'identityProviderAlias=zoho' -s "identityProviderMapper=$mapper" "$@" >/dev/null
}
ensure_mapper email     oidc-user-attribute-idp-mapper -s 'config.syncMode=INHERIT' -s 'config.claim=email'       -s 'config."user.attribute"=email'
ensure_mapper firstName oidc-user-attribute-idp-mapper -s 'config.syncMode=INHERIT' -s 'config.claim=given_name'  -s 'config."user.attribute"=firstName'
ensure_mapper lastName  oidc-user-attribute-idp-mapper -s 'config.syncMode=INHERIT' -s 'config.claim=family_name' -s 'config."user.attribute"=lastName'
ensure_mapper username  oidc-username-idp-mapper       -s 'config.syncMode=INHERIT' -s 'config.template=${CLAIM.email}' -s 'config.target=LOCAL'

# ---------------------------------------------------------------------------
# lunchify SPA client
# ---------------------------------------------------------------------------
LID=$(kc get clients -r "$REALM" -q clientId=lunchify --fields id --format csv --noquotes 2>/dev/null || true)
if [ -z "$LID" ]; then
  echo ">> creating lunchify client"
  kc create clients -r "$REALM" -s clientId=lunchify -s name=Lunchify -s enabled=true -s protocol=openid-connect >/dev/null
  LID=$(kc get clients -r "$REALM" -q clientId=lunchify --fields id --format csv --noquotes)
fi
echo ">> configuring lunchify client ($LID)"
kc update "clients/$LID" -r "$REALM" \
  -s 'publicClient=true' -s 'standardFlowEnabled=true' \
  -s 'directAccessGrantsEnabled=false' -s 'implicitFlowEnabled=false' -s 'serviceAccountsEnabled=false' \
  -s 'fullScopeAllowed=false' \
  -s "rootUrl=$SPA_ORIGIN" -s "baseUrl=$SPA_ORIGIN" \
  -s "redirectUris=[\"$SPA_REDIRECT\"]" \
  -s "webOrigins=[\"$SPA_ORIGIN\"]" \
  -s "attributes.\"post.logout.redirect.uris\"=$SPA_REDIRECT" \
  -s 'attributes."pkce.code.challenge.method"=S256' >/dev/null

echo ">> done. Realm '$REALM' configured."
