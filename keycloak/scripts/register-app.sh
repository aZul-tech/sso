#!/bin/bash
# Register an OIDC Client Application in Keycloak
# Usage: ./register-app.sh <client-id> <client-name> <redirect-uri>

set -e

# Configuration
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8081}"
REALM="${REALM:-azul-tech}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"

# Check arguments
if [ $# -lt 3 ]; then
    echo "Usage: $0 <client-id> <client-name> <redirect-uri>"
    echo "Example: $0 hrm-app 'HRM System' 'http://localhost:3000/*'"
    exit 1
fi

CLIENT_ID=$1
CLIENT_NAME=$2
REDIRECT_URI=$3

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

echo "Creating client: ${CLIENT_ID}"

# Create client
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "clientId": "'"${CLIENT_ID}"'",
        "name": "'"${CLIENT_NAME}"'",
        "enabled": true,
        "protocol": "openid-connect",
        "publicClient": false,
        "secret": "'"$(openssl rand -hex 32)"'",
        "directAccessGrantsEnabled": true,
        "serviceAccountsEnabled": true,
        "redirectUris": ["'"${REDIRECT_URI}"'"],
        "webOrigins": ["'"${REDIRECT_URI}"'"],
        "standardFlowEnabled": true,
        "implicitFlowEnabled": false
    }')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "201" ]; then
    echo "Client created successfully!"

    # Get client secret
    CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=${CLIENT_ID}" \
        -H "Authorization: Bearer ${TOKEN}" | jq -r '.[0].id')

    SECRET=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${CLIENT_UUID}/client-secret" \
        -H "Authorization: Bearer ${TOKEN}" | jq -r '.value')

    echo ""
    echo "========================================"
    echo "Client Configuration:"
    echo "========================================"
    echo "Client ID:      ${CLIENT_ID}"
    echo "Client Secret:  ${SECRET}"
    echo ""
    echo "OIDC Endpoints:"
    echo "Issuer:         ${KEYCLOAK_URL}/realms/${REALM}"
    echo "Auth URL:       ${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth"
    echo "Token URL:      ${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token"
    echo "UserInfo URL:   ${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/userinfo"
    echo ""
    echo "Scopes: openid profile email"
    echo "========================================"
else
    echo "Error creating client (HTTP ${HTTP_CODE})"
    echo "$BODY"
    exit 1
fi
