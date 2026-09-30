#!/usr/bin/env bash
#
# verify-endpoints.sh — assert the *running* Keycloak advertises the URL that
# .env says it should.
#
# preflight-prod-env.sh checks what you intended to deploy. This checks what
# actually came up, which is the question that matters: the issuer is baked into
# the OIDC discovery document, and that is literally the URL every app reads and
# every "Continue with SSO" button navigates to. If the issuer says localhost,
# users get redirected to a port on their own machine no matter how the .env was
# written.
#
# Safe to run locally as well as in production — it reads .env and verifies
# whichever instance .env describes, so a dev box legitimately reports a
# localhost issuer and passes.
#
# Usage:
#   ./keycloak/scripts/verify-endpoints.sh [expected-base-url]
#
# Resolution order for the expected URL:
#   1. the argument, 2. $KEYCLOAK_URL, 3. $KC_HOSTNAME_URL from .env
# Overrides:
#   DISCOVERY_URL=<url>   fetch the discovery document from somewhere else
#
# Exits 0 when the live issuer matches the configured hostname, 1 otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
set -a; [ -f "$ROOT_DIR/.env" ] && source "$ROOT_DIR/.env"; set +a

REALM="${KC_REALM:-azultech}"
BASE="${1:-${KEYCLOAK_URL:-${KC_HOSTNAME_URL:-}}}"

if [ -z "$BASE" ]; then
  echo "No expected URL. Pass one, or set KC_HOSTNAME_URL in .env:" >&2
  echo "  ./keycloak/scripts/verify-endpoints.sh https://sso.azultech.rw" >&2
  exit 1
fi

# Strip a trailing slash so the join below doesn't produce a double slash.
BASE="${BASE%/}"

DISCOVERY="${DISCOVERY_URL:-$BASE/realms/$REALM/.well-known/openid-configuration}"
EXPECTED="$BASE/realms/$REALM"

# Is this base URL a loopback address? Used only to word the output sensibly.
is_loopback() {
  case "$1" in
    *://localhost*|*://127.*|*://0.0.0.0*|*://\[::1\]*) return 0 ;;
    *) return 1 ;;
  esac
}

echo ">> configured base: $BASE"
echo ">> fetching $DISCOVERY"

if ! BODY="$(curl -sf --max-time 20 "$DISCOVERY")"; then
  echo "FAIL: could not reach $DISCOVERY" >&2
  if is_loopback "$BASE"; then
    echo "      Is the local stack running? docker compose ps" >&2
    echo "      If it is still starting, wait for:" >&2
    echo "        curl -sf http://127.0.0.1:8081/health/ready" >&2
  else
    echo "      nginx + DNS + TLS for $BASE all have to be up." >&2
  fi
  exit 1
fi

# Pull the issuer value out without needing jq.
ISSUER="$(printf '%s' "$BODY" | sed -n 's/.*"issuer"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

if [ -z "$ISSUER" ]; then
  echo "FAIL: could not parse an issuer out of the discovery document." >&2
  exit 1
fi

echo "   live issuer:   $ISSUER"
echo ""

if [ "$ISSUER" != "$EXPECTED" ]; then
  echo "FAIL: expected issuer $EXPECTED" >&2
  echo "      but Keycloak is serving $ISSUER" >&2
  echo ""
  if is_loopback "$ISSUER" && ! is_loopback "$BASE"; then
    echo "      This is the localhost-in-production bug: every app reading this" >&2
    echo "      document — and every 'Continue with SSO' button — will send users" >&2
    echo "      to a port on their own machine." >&2
    echo "      Fix: set KC_HOSTNAME_URL + KC_HOSTNAME_ADMIN_URL to the public" >&2
    echo "      https URL in .env, then 'docker compose -f docker-compose.yml" >&2
    echo "      -f docker-compose.prod.yml up -d' again." >&2
  elif is_loopback "$BASE" && ! is_loopback "$ISSUER"; then
    echo "      .env points at a local port but the server is serving a public" >&2
    echo "      URL — you are pointed at the wrong instance, or this IS" >&2
    echo "      production and .env was never updated for it." >&2
  fi
  echo ""
  echo "VERIFY FAILED — the running issuer does not match the configured hostname." >&2
  exit 1
fi

echo "ok: live issuer matches the configured hostname"
echo ""
if is_loopback "$EXPECTED"; then
  echo "VERIFY PASSED (local instance — a localhost issuer is expected here)."
  echo "This proves your local stack is self-consistent. It says nothing about" >&2
  echo "production, which must be re-checked with the public URL." >&2
  echo ""
  echo "Reminder: the SSO URL is BAKED INTO each app at build time. A correct" >&2
  echo "issuer here does not fix an app whose VITE_KEYCLOAK_URL was built with" >&2
  echo "http://localhost:8081 — rebuild it with the public URL."
else
  echo "VERIFY PASSED — Keycloak is advertising its public https URL."
  echo ""
  echo "Reminder: the SSO URL is BAKED INTO each app at build time. A correct" >&2
  echo "issuer here does not fix an app whose VITE_KEYCLOAK_URL was built with" >&2
  echo "http://localhost:8081 — rebuild it with the public URL."
fi