#!/bin/bash
# Export Keycloak Realm Configuration
# Usage: ./export-realm.sh [realm-name]

set -e

# Configuration
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
REALM="${1:-azul-tech}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
EXPORT_DIR="./realm-export"

echo "Getting admin token..."

# Get admin token
TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${ADMIN_USER}" \
    -d "password=${ADMIN_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | jq -r '.access_token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "Error: Failed to get admin token"
    exit 1
fi

echo "Exporting realm: ${REALM}"

# Create export directory
mkdir -p "${EXPORT_DIR}"

# Export realm
curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json" \
    -o "${EXPORT_DIR}/${REALM}-realm.json"

echo "Realm exported to ${EXPORT_DIR}/${REALM}-realm.json"

# Export clients
echo "Exporting clients..."
curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json" \
    -o "${EXPORT_DIR}/${REALM}-clients.json"

echo "Clients exported to ${EXPORT_DIR}/${REALM}-clients.json"

# Export users
echo "Exporting users..."
curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/users?max=10000" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json" \
    -o "${EXPORT_DIR}/${REALM}-users.json"

echo "Users exported to ${EXPORT_DIR}/${REALM}-users.json"

# Export groups
echo "Exporting groups..."
curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/groups" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json" \
    -o "${EXPORT_DIR}/${REALM}-groups.json"

echo "Groups exported to ${EXPORT_DIR}/${REALM}-groups.json"

echo ""
echo "Export complete! Files saved to ${EXPORT_DIR}/"
