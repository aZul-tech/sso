#!/bin/bash
# Keycloak User Creation Script for Azul Tech
# Usage: ./create-user.sh <username> <email> <password> <firstname> <lastname> [group]

set -e

# Configuration
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
REALM="${REALM:-azul-tech}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"

# Check arguments
if [ $# -lt 5 ]; then
    echo "Usage: $0 <username> <email> <password> <firstname> <lastname> [group]"
    echo "Example: $0 john.doe john.doe@azul-tech.com SecurePass123! John Doe hr-department"
    exit 1
fi

USERNAME=$1
EMAIL=$2
PASSWORD=$3
FIRSTNAME=$4
LASTNAME=$5
GROUP=${6:-""}

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

echo "Creating user: ${USERNAME}"

# Create user
curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "username": "'"${USERNAME}"'",
        "email": "'"${EMAIL}"'",
        "firstName": "'"${FIRSTNAME}"'",
        "lastName": "'"${LASTNAME}"'",
        "enabled": true,
        "emailVerified": true,
        "credentials": [{
            "type": "password",
            "value": "'"${PASSWORD}"'",
            "temporary": true
        }]
    }'

echo ""
echo "User created successfully!"

# Add to group if specified
if [ -n "$GROUP" ]; then
    echo "Adding user to group: ${GROUP}"

    # Get user ID
    USER_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=${USERNAME}" \
        -H "Authorization: Bearer ${TOKEN}" | jq -r '.[0].id')

    # Get group ID
    GROUP_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/groups?search=${GROUP}" \
        -H "Authorization: Bearer ${TOKEN}" | jq -r '.[0].id')

    if [ -n "$USER_ID" ] && [ -n "$GROUP_ID" ]; then
        curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${USER_ID}/groups/${GROUP_ID}" \
            -H "Authorization: Bearer ${TOKEN}"
        echo "User added to group successfully!"
    else
        echo "Warning: Could not find user or group"
    fi
fi

echo ""
echo "Done! User will need to update password on first login."
