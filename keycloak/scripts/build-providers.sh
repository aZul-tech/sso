#!/usr/bin/env bash
#
# build-providers.sh — package the "Azul Tech Email Domain Guard" script
# authenticator into a deployable Keycloak provider JAR.
#
# Source:  keycloak/providers-src/
#            META-INF/keycloak-scripts.json   (declares the authenticator)
#            domain-check.js                  (the authenticator logic)
# Output:  keycloak/providers/azul-domain-guard.jar   (mounted into the container)
#
# A JAR is just a ZIP. On Linux/macOS this uses `zip`; on Windows run the
# PowerShell one-liner in build-providers.ps1 instead.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/../providers-src"
OUT="$SCRIPT_DIR/../providers"
JAR="$OUT/azul-domain-guard.jar"

mkdir -p "$OUT"
rm -f "$JAR"
( cd "$SRC" && zip -r "$JAR" META-INF domain-check.js >/dev/null )
echo "Built $JAR"
unzip -l "$JAR"
