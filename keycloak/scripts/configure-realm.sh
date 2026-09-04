#!/usr/bin/env bash
#
# configure-realm.sh — idempotent configuration of the "azul-tech" realm.
#
# ARCHITECTURE (revised): Keycloak is the identity provider. Users are local
# to Keycloak — staff see ONLY Keycloak's own login page (the "azultech"
# theme). Zoho is not consulted for authentication. (Phase 2 will make Zoho a
# downstream SAML application of this realm — see docs/PHASE-1-REALM.md.)
#
# This script is the SOURCE OF TRUTH for the realm:
#   - realm base settings (token/session lifetimes, brute-force, theme)
#   - realm roles (admin, employee) + groups (Admins, Employees) that grant them
#   - the "lunchify" public SPA client, with its own client roles
#     (super-admin / restaurant-manager / employee) so a second app can define
#     its own roles later without colliding with Lunchify's
#   - a "groups" claim mapper so group membership rides in the token
#
# Exit test: `docker compose down -v && docker compose up -d && ./configure-realm.sh`
# on an empty server reproduces this realm completely.
#
# Usage:  ./keycloak/scripts/configure-realm.sh
# Reads:  ../../.env  (KEYCLOAK_ADMIN[_PASSWORD], KC_REALM, LUNCHIFY_ORIGIN/REDIRECT)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
set -a; source "$ROOT_DIR/.env"; set +a

REALM="${KC_REALM:-azul-tech}"
CONTAINER="${KC_CONTAINER:-azul-tech-keycloak}"
ADMIN="${KEYCLOAK_ADMIN:-admin}"
ADMIN_PW="${KEYCLOAK_ADMIN_PASSWORD:?set KEYCLOAK_ADMIN_PASSWORD in .env}"
SPA_REDIRECT="${LUNCHIFY_REDIRECT:-http://localhost:5173/*}"
SPA_ORIGIN="${LUNCHIFY_ORIGIN:-http://localhost:5173}"

export MSYS_NO_PATHCONV=1
kc() { docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh "$@"; }

echo ">> authenticating"
kc config credentials --server http://localhost:8080 --realm master --user "$ADMIN" --password "$ADMIN_PW" >/dev/null

# ---------------------------------------------------------------------------
# Realm
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
    -s 'bruteForceProtected=true' -s 'permanentLockout=false' \
    -s 'failureFactor=5' -s 'maxFailureWaitSeconds=900' \
    -s 'accessTokenLifespan=300' \
    -s 'ssoSessionIdleTimeout=1800' -s 'ssoSessionMaxLifespan=36000' \
    -s 'internationalizationEnabled=true' -s 'supportedLocales=["en","sw"]' -s 'defaultLocale=en' >/dev/null
fi

echo ">> login theme: azultech (deep navy / royal-blue background — the only login page staff see)"
kc update "realms/$REALM" -s 'loginTheme=azultech' -s 'accountTheme=azultech' >/dev/null 2>&1 || \
  kc update "realms/$REALM" -s 'loginTheme=azultech' >/dev/null
kc update "realms/master" -s 'loginTheme=azultech' >/dev/null 2>&1 || true

echo ">> OTP policy: TOTP, 6 digits, 30s period"
kc update "realms/$REALM" -s 'otpPolicyType=totp' -s 'otpPolicyAlgorithm=HmacSHA1' \
  -s 'otpPolicyDigits=6' -s 'otpPolicyPeriod=30' -s 'otpPolicyLookAheadWindow=1' >/dev/null

# ---------------------------------------------------------------------------
# Realm roles — the cross-app tier. Per-app permission detail lives on each
# client's OWN roles (see the lunchify client roles below), so a second app
# never has to reuse or renegotiate Lunchify's role names.
# ---------------------------------------------------------------------------
echo ">> realm roles"
for r in admin employee; do
  kc get "roles/$r" -r "$REALM" >/dev/null 2>&1 || kc create roles -r "$REALM" -s "name=$r" >/dev/null
done

# ---------------------------------------------------------------------------
# Groups — org structure. Membership grants the realm role. Department-level
# subgroups arrive with the HR system (Phase 3); kept flat for now.
# ---------------------------------------------------------------------------
echo ">> groups"
ensure_group() {
  local name="$1" role="$2"
  local gid
  gid=$(kc get groups -r "$REALM" -q "search=$name" --fields id,name --format csv --noquotes 2>/dev/null | awk -F, -v n="$name" '$2==n{print $1}' | head -1)
  if [ -z "$gid" ]; then
    kc create groups -r "$REALM" -s "name=$name" >/dev/null
    gid=$(kc get groups -r "$REALM" -q "search=$name" --fields id,name --format csv --noquotes 2>/dev/null | awk -F, -v n="$name" '$2==n{print $1}' | head -1)
  fi
  kc add-roles -r "$REALM" --gid "$gid" --rolename "$role" >/dev/null 2>&1 || true
  echo "$gid"
}
ADMINS_GID=$(ensure_group Admins admin)
EMPLOYEES_GID=$(ensure_group Employees employee)

# ---------------------------------------------------------------------------
# lunchify SPA client — its own client-role namespace so a second app (Taqwa,
# Fikia, the HR system) defines its own roles without touching this one.
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

echo ">> lunchify client roles"
for r in super-admin restaurant-manager employee; do
  kc get "clients/$LID/roles/$r" -r "$REALM" >/dev/null 2>&1 || \
    kc create "clients/$LID/roles" -r "$REALM" -s "name=$r" >/dev/null
done

echo ">> groups claim mapper on lunchify's dedicated scope"
MAPPER_EXISTS=$(kc get "clients/$LID/protocol-mappers/models" -r "$REALM" --fields name --format csv --noquotes 2>/dev/null | grep -c '^groups$' || true)
if [ "$MAPPER_EXISTS" = "0" ]; then
  kc create "clients/$LID/protocol-mappers/models" -r "$REALM" \
    -s 'name=groups' -s 'protocol=openid-connect' -s 'protocolMapper=oidc-group-membership-mapper' \
    -s 'config."full.path"=false' -s 'config."id.token.claim"=true' -s 'config."access.token.claim"=true' \
    -s 'config."userinfo.token.claim"=true' -s 'config."claim.name"=groups' >/dev/null
fi

echo ">> done. Realm '$REALM' configured. Groups: Admins=$ADMINS_GID Employees=$EMPLOYEES_GID"
echo "   Token claim contract: email/given_name/family_name/preferred_username (standard),"
echo "   groups (this realm's group mapper), realm_access.roles, resource_access.lunchify.roles"
echo "   -> see docs/PHASE-1-REALM.md"
