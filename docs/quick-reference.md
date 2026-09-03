# Azul Tech SSO - Quick Reference Card

## Keycloak Access

| Item | Value |
|------|-------|
| Admin Console | `http://localhost:8080` |
| Admin Username | `admin` |
| Admin Password | See `.env` file |
| Realm | `azul-tech` |

## OIDC Endpoints

| Endpoint | URL |
|----------|-----|
| Issuer | `http://localhost:8080/realms/azul-tech` |
| Authorization | `http://localhost:8080/realms/azul-tech/protocol/openid-connect/auth` |
| Token | `http://localhost:8080/realms/azul-tech/protocol/openid-connect/token` |
| UserInfo | `http://localhost:8080/realms/azul-tech/protocol/openid-connect/userinfo` |
| JWKS | `http://localhost:8080/realms/azul-tech/protocol/openid-connect/certs` |
| Logout | `http://localhost:8080/realms/azul-tech/protocol/openid-connect/logout` |

## SAML Endpoints

| Endpoint | URL |
|----------|-----|
| IdP Metadata | `http://localhost:8080/realms/azul-tech/protocol/saml/descriptor` |
| SSO URL | `http://localhost:8080/realms/azul-tech/protocol/saml` |

## Default Groups

| Group | Purpose | Default Roles |
|-------|---------|---------------|
| Azul Tech Admins | System administrators | admin |
| HR Department | Human Resources | hr-staff, user |
| Finance Department | Finance Team | finance-staff, user |
| Projects Team | Project Management | project-manager, user |
| Development Team | IT/Development | developer, user |

## Common Commands

### Start Keycloak
```bash
docker-compose up -d
```

### Stop Keycloak
```bash
docker-compose down
```

### View Logs
```bash
docker-compose logs -f keycloak
```

### Create User
```bash
cd keycloak/scripts
./create-user.sh username user@azul-tech.com Password123! John Doe hr-department
```

### Register App (OIDC)
```bash
cd keycloak/scripts
./register-app.sh app-id "App Name" "http://localhost:3000/*"
```

### Export Realm
```bash
cd keycloak/scripts
./export-realm.sh azul-tech
```

## Application Configuration

### OIDC Apps
```javascript
{
  "issuer": "http://localhost:8080/realms/azul-tech",
  "clientId": "your-client-id",
  "clientSecret": "your-client-secret",
  "redirectUri": "http://your-app.com/callback",
  "scope": ["openid", "profile", "email"]
}
```

### SAML Apps
- Download metadata: `http://localhost:8080/realms/azul-tech/protocol/saml/descriptor`
- SSO URL: `http://localhost:8080/realms/azul-tech/protocol/saml`
- Entity ID: `http://localhost:8080/realms/azul-tech`

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Can't access admin console | Check if Keycloak is running: `docker-compose ps` |
| Login fails | Verify username/email and password |
| SSO redirect error | Check redirect URIs in client config |
| Token validation fails | Verify issuer URL matches exactly |
| User not found | Ensure user exists in Keycloak realm |

## File Locations

| File | Purpose |
|------|---------|
| `.env` | Environment variables (passwords) |
| `docker-compose.yml` | Docker configuration |
| `keycloak/realm-export/` | Realm backup |
| `keycloak/scripts/` | Management scripts |
| `docs/` | Documentation |

## Support

- Keycloak Docs: https://www.keycloak.org/documentation
- This repo: See `docs/` folder
