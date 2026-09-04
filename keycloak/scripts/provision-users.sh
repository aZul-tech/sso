#!/usr/bin/env bash
#
# provision-users.sh — create local Keycloak users the way Rene specified:
# nobody sets a password on a user's behalf, ever. No temporary passwords in
# messages, no admin ever knowing a user's credentials.
#
# Each user is created with NO password and required actions
# VERIFY_EMAIL + UPDATE_PASSWORD + CONFIGURE_TOTP + CONFIGURE_RECOVERY_AUTHN_CODES,
# then Keycloak's "execute actions email" is triggered so the person sets
# their own password (and enrols MFA + gets recovery codes) via a one-time
# link, over the realm's configured SMTP. In dev that's MailHog
# (http://localhost:8025) — nothing to relay by hand; in prod it's real mail.
#
# The list of people comes from Yvonne (the actual staff roster), NOT derived
# from the Zoho mailbox list — mailboxes and people diverge (shared boxes,
# aliases, dormant accounts).
#
# Usage:
#   ./keycloak/scripts/provision-users.sh users.csv
#
# CSV columns (header row required): name,email,department,lunchify_group
#   department      free text -> /Departments/<department> (created if new),
#                    also stored as the `department` user attribute (claim)
#   lunchify_group   SuperAdmins | RestaurantManagers | Employees | (blank)
#                    -> membership in /App-Access/Lunchify/<group>, which
#                       carries the matching lunchify client role. Access is
#                       granted by group membership, never role-on-user.
#
# Example row:
#   Yvonne Uwantege,u.yvonne@azultech.rw,Executive,SuperAdmins

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CSV="${1:?usage: provision-users.sh <path-to-users.csv>}"

# shellcheck disable=SC1091
set -a; source "$ROOT_DIR/.env"; set +a

REALM="${KC_REALM:-azultech}"
CONTAINER="${KC_CONTAINER:-azul-tech-keycloak}"
ADMIN="${KEYCLOAK_ADMIN:-admin}"
ADMIN_PW="${KEYCLOAK_ADMIN_PASSWORD:?set KEYCLOAK_ADMIN_PASSWORD in .env}"
ACTION_LIFESPAN="${ONBOARDING_LINK_LIFESPAN_SECONDS:-259200}"  # 72h to set up

export MSYS_NO_PATHCONV=1
kc() { docker exec "$CONTAINER" /opt/keycloak/bin/kcadm.sh "$@"; }

kc config credentials --server http://localhost:8080 --realm master --user "$ADMIN" --password "$ADMIN_PW" >/dev/null

# execute-actions-email must be triggered against the PUBLIC-facing URL
# (same host:port a browser uses), not the internal docker network address —
# the resulting action-token bakes in whatever issuer it was minted against,
# and Keycloak rejects the link if that doesn't match the realm's real
# issuer. kcadm above talks to Keycloak over the internal Docker network
# (port 8080), so calls that mint a link for a human to click go through curl
# against the public URL instead.
PUBLIC_KC_URL="${KC_HOSTNAME_URL:-http://localhost:8081}"
PUBLIC_ADMIN_TOKEN=$(curl -s -X POST "$PUBLIC_KC_URL/realms/master/protocol/openid-connect/token" \
  -d client_id=admin-cli -d "username=$ADMIN" -d "password=$ADMIN_PW" -d grant_type=password \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).access_token))')

send_execute_actions_email() {
  local uid="$1" resp code
  # (avoid `-o /dev/null -w` — flaky in this shell; capture body+code together instead)
  resp=$(curl -s -w $'\n%{http_code}' -X PUT \
    "$PUBLIC_KC_URL/admin/realms/$REALM/users/$uid/execute-actions-email?client_id=lunchify&redirect_uri=$(node -e "console.log(encodeURIComponent(process.argv[1]))" "${LUNCHIFY_REDIRECT_BASE:-http://localhost:5173/}")&lifespan=$ACTION_LIFESPAN" \
    -H "Authorization: Bearer $PUBLIC_ADMIN_TOKEN" -H 'Content-Type: application/json' \
    -d '["VERIFY_EMAIL","UPDATE_PASSWORD","CONFIGURE_TOTP","CONFIGURE_RECOVERY_AUTHN_CODES"]' || true)
  code=$(echo "$resp" | tail -1)
  echo "$code"
}

group_id() {
  kc get groups -r "$REALM" -q "search=$1" --fields id,name --format csv --noquotes 2>/dev/null \
    | awk -F, -v n="$1" '$2==n{print $1}' | head -1
}
subgroup_id() {
  local parent_id="$1" name="$2"
  kc get "groups/$parent_id/children" -r "$REALM" --fields id,name --format csv --noquotes 2>/dev/null \
    | awk -F, -v n="$name" '$2==n{print $1}' | head -1
}
ensure_department_group() {
  local dept="$1"
  local depts_gid; depts_gid=$(group_id Departments)
  local gid; gid=$(subgroup_id "$depts_gid" "$dept")
  if [ -z "$gid" ]; then
    echo "   (new department group: /Departments/$dept)"
    kc create "groups/$depts_gid/children" -r "$REALM" -s "name=$dept" >/dev/null
    gid=$(subgroup_id "$depts_gid" "$dept")
  fi
  echo "$gid"
}

LUNCHIFY_ACCESS_GID=""
lunchify_group_id() {
  [ -n "$LUNCHIFY_ACCESS_GID" ] || LUNCHIFY_ACCESS_GID=$(subgroup_id "$(group_id App-Access)" Lunchify)
  subgroup_id "$LUNCHIFY_ACCESS_GID" "$1"
}

tail -n +2 "$CSV" | while IFS=, read -r name email department lunchify_group; do
  [ -z "$email" ] && continue
  first="${name%% *}"; last="${name#* }"
  [ "$first" = "$last" ] && last=""

  uid=$(kc get users -r "$REALM" -q "email=$email" --fields id --format csv --noquotes 2>/dev/null | head -1)
  is_new=""
  if [ -z "$uid" ]; then
    echo ">> creating $email"
    is_new="yes"
    dept_attr_args=()
    [ -n "$department" ] && dept_attr_args=(-s "attributes.department=[\"$department\"]")
    kc create users -r "$REALM" \
      -s "username=$email" -s "email=$email" -s 'emailVerified=false' -s 'enabled=true' \
      -s "firstName=$first" -s "lastName=$last" \
      "${dept_attr_args[@]}" \
      -s 'requiredActions=["VERIFY_EMAIL","UPDATE_PASSWORD","CONFIGURE_TOTP","CONFIGURE_RECOVERY_AUTHN_CODES"]' >/dev/null
    uid=$(kc get users -r "$REALM" -q "email=$email" --fields id --format csv --noquotes)
  else
    echo ">> $email already exists — updating department/group only, no password touched"
    [ -n "$department" ] && kc update "users/$uid" -r "$REALM" -s "attributes.department=[\"$department\"]" >/dev/null
  fi

  if [ -n "$department" ]; then
    dept_gid=$(ensure_department_group "$department")
    kc update "users/$uid/groups/$dept_gid" -r "$REALM" -b '{}' >/dev/null 2>&1 || true
  fi

  if [ -n "${lunchify_group:-}" ]; then
    lg_gid=$(lunchify_group_id "$lunchify_group")
    if [ -n "$lg_gid" ]; then
      kc update "users/$uid/groups/$lg_gid" -r "$REALM" -b '{}' >/dev/null 2>&1 || true
    else
      echo "   !! unknown lunchify_group '$lunchify_group' — skipped (expected SuperAdmins|RestaurantManagers|Employees)"
    fi
  fi

  echo "   department=$department  lunchify_group=${lunchify_group:-none}"

  pending="$is_new"
  if [ -z "$pending" ]; then
    # Existing user: only resend the onboarding email if they still have
    # required actions outstanding (haven't finished setting themselves up).
    # A fully onboarded user (Yvonne, Ronald, ...) must never be forced back
    # through password + MFA setup just because this script ran again.
    user_json=$(kc get "users/$uid" -r "$REALM")
    pending=$(echo "$user_json" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const u=JSON.parse(s);process.stdout.write((u.requiredActions&&u.requiredActions.length)?"yes":"")}catch(e){}})')
  fi

  if [ -z "$pending" ]; then
    echo "   already fully onboarded — not resending the onboarding email"
    continue
  fi

  echo "   sending execute-actions email (VERIFY_EMAIL, UPDATE_PASSWORD, CONFIGURE_TOTP, CONFIGURE_RECOVERY_AUTHN_CODES)"
  http_code=$(send_execute_actions_email "$uid")
  if [ "$http_code" != "204" ]; then
    echo "   !! execute-actions-email returned HTTP $http_code (expected 204) — check SMTP settings"
  fi
done

echo
echo "Done. Nobody set anyone's password. Each person got an email (dev: check http://localhost:8025) with a one-time link to set their own."
