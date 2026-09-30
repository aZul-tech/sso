#!/usr/bin/env bash
#
# preflight-prod-env.sh — refuse to deploy a Keycloak that advertises a
# localhost/loopback issuer.
#
# Why this exists
# ---------------
# Keycloak's hostname configuration is what it tells the *browser*: the issuer
# in the discovery document, the post-login redirect, the admin console link,
# and every one-time action link in an onboarding email. If that hostname is a
# loopback address, those URLs are unusable to a real user — clicking "Continue
# with Azul Tech SSO" on the deployed app lands the browser on
# http://localhost:8081, i.e. a port on the *user's own laptop*, which of course
# has nothing listening on it.
#
# Two things made that failure easy to ship:
#   1. `.env` is git-ignored, so a freshly cloned server has none.
#   2. docker-compose.yml defaults KC_HOSTNAME to http://localhost:8081 so that
#      `docker compose up -d` works on a laptop with no .env at all.
# docker-compose.prod.yml now aborts when the variables are missing (`:?`), but
# that check cannot tell a good value from a bad one — someone who copies the
# dev block out of .env.example gets past it. That is what this script is for.
#
# It validates the values themselves. Run it BEFORE `docker compose ... up -d`.
#
# Usage:
#   ./keycloak/scripts/preflight-prod-env.sh
#
# Exits 0 if the deployment config looks safe, 1 (with reasons) if not.
# Local dev intentionally does NOT pass this — localhost is correct there.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "FAIL: no .env at $ENV_FILE" >&2
  echo "      cp .env.example .env and fill in the PRODUCTION block." >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a; source "$ENV_FILE"; set +a

fail=0

# Reads one variable and rejects it if it is unset, empty, a loopback
# address, or not https. Arg 1 = variable name.
check_public_url() {
  local var="$1" value="${!1-}" label="$2"

  if [ -z "$value" ]; then
    echo "FAIL: $var is unset or empty in .env ($label)." >&2
    fail=1
    return
  fi

  local host="${value#*://}"   # strip scheme
  host="${host%%/*}"           # strip path
  host="${host%%:*}"           # strip port

  case "$host" in
    localhost|127.*|0.0.0.0|::1|\[::1\]|"")
      echo "FAIL: $var='$value' points at loopback ($label)." >&2
      echo "      Keycloak would mint links like '$value/realms/...'" >&2
      echo "      that send users to a port on their own machine." >&2
      fail=1
      return
      ;;
  esac

  case "$value" in
    https://*) ;;
    http://*)
      echo "FAIL: $var='$value' is plain http ($label)." >&2
      echo "      Production is TLS-terminated at nginx — use the https URL." >&2
      fail=1
      return
      ;;
    *)
      echo "FAIL: $var='$value' has no http(s) scheme ($label)." >&2
      fail=1
      return
      ;;
  esac

  echo "ok: $var=$value"
}

check_public_url KC_HOSTNAME_URL "public SSO URL"
check_public_url KC_HOSTNAME_ADMIN_URL "public admin console URL"

if [ "${KC_HOSTNAME_STRICT:-false}" != "true" ]; then
  echo "FAIL: KC_HOSTNAME_STRICT must be 'true' in production." >&2
  echo "      Without it Keycloak derives its hostname per-request and can" >&2
  echo "      advertise whichever address the request arrived on." >&2
  fail=1
fi

# A copied dev .env can also leave the dev-only SMTP catcher in place, which
# silently swallows every onboarding email instead of sending it.
if [ "${SMTP_HOST:-}" = "mailhog" ]; then
  echo "FAIL: SMTP_HOST=mailhog is the dev mail catcher." >&2
  echo "      It discards every onboarding email. Point SMTP_HOST at real SMTP." >&2
  fail=1
fi

echo ""
if [ "$fail" -ne 0 ]; then
  echo "PREFLIGHT FAILED — do not deploy. Fix .env and re-run." >&2
  exit 1
fi

echo "PREFLIGHT PASSED — hostname config looks production-safe."
echo "After 'up -d', run: ./keycloak/scripts/verify-endpoints.sh"