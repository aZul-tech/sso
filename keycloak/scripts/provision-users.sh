#!/usr/bin/env bash
#
# provision-users.sh — bulk-create local Keycloak users (Phase 1: Keycloak is
# the IdP, so every person needs a Keycloak account).
#
# No SMTP is configured yet, so this PRINTS each temporary password once —
# relay it to the person out-of-band. They're forced to set their own password
# (and, if in Admins, enrol MFA) on first login; nobody but them ever knows
# the real one after that.
#
# Usage:
#   ./keycloak/scripts/provision-users.sh users.csv
#
# CSV columns (header row required): name,email,group,lunchify_role
#   group          Admins | Employees   (realm group -> realm role)
#   lunchify_role  super-admin | restaurant-manager | employee | (blank = skip)
#
# Example row:
#   Yvonne Uwantege,u.yvonne@azultech.rw,Admins,super-admin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CSV="${1:?usage: provision-users.sh <path-to-users.csv>}"

# shellcheck disable=SC1091
set -a; source "$ROOT_DIR/.env"; set +a

REALM="${KC_REALM:-azul-tech}"
CONTAINER="${KC_CONTAINER:-azul-tech-keycloak}"
ADMIN="${KEYCLOAK_ADMIN:-admin}"
ADMIN_PW="${KEYCLOAK_ADMIN_PASSWORD:?set KEYCLOAK_ADMIN_PASSWORD in .env}"
LID_CACHE=""

export MSYS_NO_PATHCONV=1
kc() { docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh "$@"; }

kc config credentials --server http://localhost:8080 --realm master --user "$ADMIN" --password "$ADMIN_PW" >/dev/null

lunchify_id() {
  [ -n "$LID_CACHE" ] && { echo "$LID_CACHE"; return; }
  LID_CACHE=$(kc get clients -r "$REALM" -q clientId=lunchify --fields id --format csv --noquotes)
  echo "$LID_CACHE"
}

group_id() {
  kc get groups -r "$REALM" -q "search=$1" --fields id,name --format csv --noquotes 2>/dev/null \
    | awk -F, -v n="$1" '$2==n{print $1}' | head -1
}

random_pw() {
  # 16 chars, letters+digits+symbols — printed once, replaced on first login.
  # (subshell + pipefail off: `head -c` closing the pipe early SIGPIPEs `tr`,
  # which would otherwise trip `set -o pipefail` above and run past this into
  # a predictable fallback suffix — a real bug caught while testing this script.)
  ( set +o pipefail; tr -dc 'A-Za-z0-9!@#%^*' < /dev/urandom 2>/dev/null | head -c 16 )
}

echo "email,temporary_password" > /tmp/provisioned-passwords.csv 2>/dev/null || true

tail -n +2 "$CSV" | while IFS=, read -r name email group lunchify_role; do
  [ -z "$email" ] && continue
  first="${name%% *}"; last="${name#* }"
  [ "$first" = "$last" ] && last=""

  uid=$(kc get users -r "$REALM" -q "email=$email" --fields id --format csv --noquotes 2>/dev/null | head -1)
  if [ -z "$uid" ]; then
    echo ">> creating $email"
    kc create users -r "$REALM" \
      -s "username=$email" -s "email=$email" -s 'emailVerified=true' -s 'enabled=true' \
      -s "firstName=$first" -s "lastName=$last" \
      -s 'requiredActions=["UPDATE_PASSWORD"]' >/dev/null
    uid=$(kc get users -r "$REALM" -q "email=$email" --fields id --format csv --noquotes)
  else
    echo ">> $email already exists — updating group/role only"
  fi

  PW=$(random_pw)
  kc set-password -r "$REALM" --userid "$uid" --new-password "$PW" --temporary >/dev/null
  echo "   temp password: $PW   (they set their own on first login)"
  echo "$email,$PW" >> /tmp/provisioned-passwords.csv 2>/dev/null || true

  if [ "$group" = "Admins" ]; then
    gid=$(group_id Admins)
    kc update "users/$uid/groups/$gid" -r "$REALM" -b '{}' >/dev/null 2>&1 || true
    # Admins must enrol MFA before they can do anything else.
    current=$(kc get "users/$uid" -r "$REALM" --fields requiredActions --format csv --noquotes 2>/dev/null || echo '')
    if ! echo "$current" | grep -q CONFIGURE_TOTP; then
      kc update "users/$uid" -r "$REALM" -s 'requiredActions=["UPDATE_PASSWORD","CONFIGURE_TOTP"]' >/dev/null
    fi
  elif [ "$group" = "Employees" ]; then
    gid=$(group_id Employees)
    kc update "users/$uid/groups/$gid" -r "$REALM" -b '{}' >/dev/null 2>&1 || true
  fi

  if [ -n "${lunchify_role:-}" ]; then
    LID=$(lunchify_id)
    kc add-roles -r "$REALM" --uusername "$email" --cclientid lunchify --rolename "$lunchify_role" >/dev/null 2>&1 || true
  fi

  echo "   group=$group  lunchify_role=${lunchify_role:-none}"
done

echo
echo "Done. Temporary passwords also saved to /tmp/provisioned-passwords.csv — relay them out-of-band and delete that file."
