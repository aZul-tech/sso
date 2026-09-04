#!/usr/bin/env bash
#
# create-break-glass-admin.sh — one realm-local admin account excluded from
# MFA, for the case where normal platform-admins are locked out (lost
# devices, MFA provider down, etc.). Per Rene's ask, this must exist before
# Phase 1 counts as "live".
#
# This account is DIFFERENT from every other user in this realm:
#   - No CONFIGURE_TOTP / CONFIGURE_RECOVERY_AUTHN_CODES required action —
#     MFA-mandatory-for-everyone is enforced by giving every OTHER
#     provisioned user those required actions; this one deliberately skips
#     them so it still works if the MFA path itself is the thing that's broken.
#   - Password is set directly here, not via execute-actions-email — this
#     credential must be sealed (printed, put in a safe / offline password
#     manager) immediately, not left sitting in an inbox.
#   - Member of /Platform-Admins (realm-admin), same as any platform-admin.
#
# IMPORTANT: run this yourself, directly in your own terminal — not through
# an assistant or CI job whose output you don't fully control. The password
# is printed exactly once, below, and is never written to a file or log by
# this script.
#
# Usage:  ./keycloak/scripts/create-break-glass-admin.sh <username>
# Reads:  ../../.env

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
USERNAME="${1:?usage: create-break-glass-admin.sh <username>}"

# shellcheck disable=SC1091
set -a; source "$ROOT_DIR/.env"; set +a

REALM="${KC_REALM:-azultech}"
CONTAINER="${KC_CONTAINER:-azul-tech-keycloak}"
ADMIN="${KEYCLOAK_ADMIN:-admin}"
ADMIN_PW="${KEYCLOAK_ADMIN_PASSWORD:?set KEYCLOAK_ADMIN_PASSWORD in .env}"

export MSYS_NO_PATHCONV=1
kc() { docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh "$@"; }

kc config credentials --server http://localhost:8080 --realm master --user "$ADMIN" --password "$ADMIN_PW" >/dev/null

group_id() {
  kc get groups -r "$REALM" -q "search=$1" --fields id,name --format csv --noquotes 2>/dev/null \
    | awk -F, -v n="$1" '$2==n{print $1}' | head -1
}
PLATFORM_ADMINS_GID=$(group_id Platform-Admins)
if [ -z "$PLATFORM_ADMINS_GID" ]; then
  echo "!! /Platform-Admins group not found — run configure-realm.sh first" >&2
  exit 1
fi

UID_EXISTING=$(kc get users -r "$REALM" -q "username=$USERNAME" --fields id --format csv --noquotes 2>/dev/null | head -1)
if [ -n "$UID_EXISTING" ]; then
  echo "!! user '$USERNAME' already exists — this script only creates new break-glass accounts." >&2
  echo "   To rotate its password, use the admin console directly." >&2
  exit 1
fi

# Generated locally, never sent anywhere, never logged after this run.
BREAK_GLASS_PW=$(openssl rand -base64 24)

echo ">> creating break-glass user '$USERNAME' in realm '$REALM'"
kc create users -r "$REALM" \
  -s "username=$USERNAME" -s 'enabled=true' -s 'emailVerified=true' \
  -s 'requiredActions=[]' >/dev/null
NEW_UID=$(kc get users -r "$REALM" -q "username=$USERNAME" --fields id --format csv --noquotes)

kc set-password -r "$REALM" --userid "$NEW_UID" --new-password "$BREAK_GLASS_PW" --temporary=false >/dev/null
kc update "users/$NEW_UID/groups/$PLATFORM_ADMINS_GID" -r "$REALM" -b '{}' >/dev/null

echo
echo "=================================================================="
echo " Break-glass account created: $USERNAME"
echo " Password (shown ONCE — copy it now):"
echo
echo "   $BREAK_GLASS_PW"
echo
echo " Do this immediately:"
echo "   1. Put this password in a sealed/offline store (physical safe,"
echo "      offline password manager) — NOT in git, chat, Slack, or a"
echo "      script. Nobody's day-to-day login should be this account."
echo "   2. Record who has access to that sealed store and when it's used"
echo "      (Rene asked for admin-event review — this account's logins"
echo "      show up in Keycloak's admin event log same as any other)."
echo "   3. This terminal's scrollback now has the password in it too —"
echo "      clear it once you've saved the value."
echo "=================================================================="
