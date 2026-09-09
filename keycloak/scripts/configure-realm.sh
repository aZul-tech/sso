#!/usr/bin/env bash
#
# configure-realm.sh — idempotent configuration of the "azultech" realm.
#
# Model (per Rene K.'s Phase 1 review, 2026-09-04):
#   - GROUPS model the organisation (departments), hierarchical. Membership
#     under /Departments grants the realm role "staff".
#   - REALM roles are reserved for genuinely cross-cutting things: staff,
#     contractor, platform-admin. They are NOT app permission tiers.
#   - CLIENT roles are the app-specific entitlements, namespaced per client
#     automatically (resource_access.<clientId>.roles) so a second app never
#     collides with Lunchify's role names.
#   - Permissions are granted to GROUPS, not individual users. App access
#     groups live under /App-Access/<app>/<role>; a user gets Lunchify access
#     by membership, not by a direct role-on-user assignment. This is what
#     makes an access review a "list group members" exercise instead of
#     clicking through users one at a time.
#   - Keycloak's own admin role (platform-admin, realm-management/realm-admin)
#     is granted via /Platform-Admins, on named personal accounts — separate
#     from any application's admin role, never shared.
#
# Exit test: `docker compose down -v && docker compose up -d && ./configure-realm.sh`
# on an empty server reproduces this realm completely. (Verified idempotent —
# re-running against an already-configured realm makes no changes and exits 0.)
#
# Usage:  ./keycloak/scripts/configure-realm.sh
# Reads:  ../../.env

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
set -a; source "$ROOT_DIR/.env"; set +a

REALM="${KC_REALM:-azultech}"
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
    -s 'offlineSessionMaxLifespanEnabled=false' \
    -s 'internationalizationEnabled=true' -s 'supportedLocales=["en","sw"]' -s 'defaultLocale=en' >/dev/null
fi

echo ">> login theme: azultech"
kc update "realms/$REALM" -s 'loginTheme=azultech' >/dev/null

# Brand the master realm's login too, so the built-in admin console
# (sso.azultech.rw/admin/master/console) matches the rest. Platform-admins
# should normally use the azultech realm console instead — this is only for
# the break-glass 'admin' account — but keeping one look avoids confusion.
echo ">> login theme: azultech (master realm admin console)"
kc update "realms/master" -s 'loginTheme=azultech' >/dev/null 2>&1 || true

echo ">> OTP policy: TOTP, 6 digits, 30s period"
kc update "realms/$REALM" -s 'otpPolicyType=totp' -s 'otpPolicyAlgorithm=HmacSHA1' \
  -s 'otpPolicyDigits=6' -s 'otpPolicyPeriod=30' -s 'otpPolicyLookAheadWindow=1' >/dev/null

echo ">> SMTP (for execute-actions-email onboarding — dev: MailHog, prod: real mail server)"
kc update "realms/$REALM" \
  -s "smtpServer.host=${SMTP_HOST:-mailhog}" -s "smtpServer.port=${SMTP_PORT:-1025}" \
  -s "smtpServer.from=${SMTP_FROM:-sso@azultech.rw}" -s "smtpServer.fromDisplayName=${SMTP_FROM_NAME:-Azul Tech SSO}" \
  -s "smtpServer.auth=${SMTP_AUTH:-false}" -s "smtpServer.user=${SMTP_USER:-}" -s "smtpServer.password=${SMTP_PASSWORD:-}" \
  -s "smtpServer.ssl=${SMTP_SSL:-false}" -s "smtpServer.starttls=${SMTP_STARTTLS:-false}" >/dev/null

# ---------------------------------------------------------------------------
# Realm roles — cross-cutting ONLY. App tiers live on the app's own client.
# ---------------------------------------------------------------------------
echo ">> realm roles (cross-cutting only)"
for r in staff contractor platform-admin; do
  kc get "roles/$r" -r "$REALM" >/dev/null 2>&1 || kc create roles -r "$REALM" -s "name=$r" >/dev/null
done

# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------
group_id() {
  kc get groups -r "$REALM" -q "search=$1" --fields id,name --format csv --noquotes 2>/dev/null \
    | awk -F, -v n="$1" '$2==n{print $1}' | head -1
}
ensure_top_group() {
  local name="$1"
  local gid; gid=$(group_id "$name")
  if [ -z "$gid" ]; then
    kc create groups -r "$REALM" -s "name=$name" >/dev/null
    gid=$(group_id "$name")
  fi
  echo "$gid"
}
ensure_subgroup() {
  local parent_id="$1" name="$2"
  local existing
  existing=$(kc get "groups/$parent_id/children" -r "$REALM" --fields id,name --format csv --noquotes 2>/dev/null | awk -F, -v n="$name" '$2==n{print $1}' | head -1)
  if [ -z "$existing" ]; then
    kc create "groups/$parent_id/children" -r "$REALM" -s "name=$name" >/dev/null
    existing=$(kc get "groups/$parent_id/children" -r "$REALM" --fields id,name --format csv --noquotes 2>/dev/null | awk -F, -v n="$name" '$2==n{print $1}' | head -1)
  fi
  echo "$existing"
}

echo ">> /Departments (org structure — placeholders until Yvonne's staff list lands)"
DEPTS_GID=$(ensure_top_group Departments)
kc add-roles -r "$REALM" --gid "$DEPTS_GID" --rolename staff >/dev/null 2>&1 || true
DEPT_EXEC_GID=$(ensure_subgroup "$DEPTS_GID" Executive)
DEPT_ENG_GID=$(ensure_subgroup "$DEPTS_GID" Engineering)

echo ">> /Platform-Admins (Keycloak operators — named accounts, separate from any app admin role)"
PLATFORM_ADMINS_GID=$(ensure_top_group Platform-Admins)
kc add-roles -r "$REALM" --gid "$PLATFORM_ADMINS_GID" --rolename platform-admin >/dev/null 2>&1 || true
kc add-roles -r "$REALM" --gid "$PLATFORM_ADMINS_GID" --cclientid realm-management --rolename realm-admin >/dev/null 2>&1 || true

echo ">> /App-Access/Lunchify/* (entitlement groups — grant the client role, not direct user role assignment)"
APP_ACCESS_GID=$(ensure_top_group App-Access)
LUNCHIFY_ACCESS_GID=$(ensure_subgroup "$APP_ACCESS_GID" Lunchify)
LUNCHIFY_SUPERADMINS_GID=$(ensure_subgroup "$LUNCHIFY_ACCESS_GID" SuperAdmins)
LUNCHIFY_RESTAURANT_MGRS_GID=$(ensure_subgroup "$LUNCHIFY_ACCESS_GID" RestaurantManagers)
LUNCHIFY_EMPLOYEES_GID=$(ensure_subgroup "$LUNCHIFY_ACCESS_GID" Employees)

# ---------------------------------------------------------------------------
# lunchify SPA client — own client-role namespace so a second app defines its
# own roles without touching this one. fullScopeAllowed=false + one client
# per app keeps a user's token scoped to that app only (no role sprawl).
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

echo ">> lunchify client roles (app entitlement tiers live HERE, not as realm roles)"
for r in super-admin restaurant-manager employee; do
  kc get "clients/$LID/roles/$r" -r "$REALM" >/dev/null 2>&1 || \
    kc create "clients/$LID/roles" -r "$REALM" -s "name=$r" >/dev/null
done

echo ">> wiring App-Access groups to their lunchify client role"
kc add-roles -r "$REALM" --gid "$LUNCHIFY_SUPERADMINS_GID" --cclientid lunchify --rolename super-admin >/dev/null 2>&1 || true
kc add-roles -r "$REALM" --gid "$LUNCHIFY_RESTAURANT_MGRS_GID" --cclientid lunchify --rolename restaurant-manager >/dev/null 2>&1 || true
kc add-roles -r "$REALM" --gid "$LUNCHIFY_EMPLOYEES_GID" --cclientid lunchify --rolename employee >/dev/null 2>&1 || true

echo ">> token claim mappers on lunchify: groups + department (standard claims otherwise — sub/email/preferred_username/realm_access/resource_access need no mapper)"
add_mapper_if_missing() {
  local name="$1"; shift
  local exists
  exists=$(kc get "clients/$LID/protocol-mappers/models" -r "$REALM" --fields name --format csv --noquotes 2>/dev/null | grep -c "^$name\$" || true)
  if [ "$exists" = "0" ]; then
    kc create "clients/$LID/protocol-mappers/models" -r "$REALM" -s "name=$name" "$@" >/dev/null
  fi
}
add_mapper_if_missing groups \
  -s 'protocol=openid-connect' -s 'protocolMapper=oidc-group-membership-mapper' \
  -s 'config."full.path"=true' -s 'config."id.token.claim"=true' -s 'config."access.token.claim"=true' \
  -s 'config."userinfo.token.claim"=true' -s 'config."claim.name"=groups'
add_mapper_if_missing department \
  -s 'protocol=openid-connect' -s 'protocolMapper=oidc-usermodel-attribute-mapper' \
  -s 'config."user.attribute"=department' -s 'config."claim.name"=department' \
  -s 'config."id.token.claim"=true' -s 'config."access.token.claim"=true' -s 'config."userinfo.token.claim"=true' \
  -s 'config."jsonType.label"=String'

echo ">> done. Realm '$REALM' configured."
echo "   Departments=$DEPTS_GID  Platform-Admins=$PLATFORM_ADMINS_GID"
echo "   App-Access/Lunchify: SuperAdmins=$LUNCHIFY_SUPERADMINS_GID RestaurantManagers=$LUNCHIFY_RESTAURANT_MGRS_GID Employees=$LUNCHIFY_EMPLOYEES_GID"
echo "   Claim contract + group/role model -> docs/PHASE-1-REALM.md"
