# Application Integration Checklist

Use this checklist for each application you integrate with Azul Tech SSO.

## Pre-Integration

- [ ] Keycloak is running and accessible
- [ ] Realm "azul-tech" is configured
- [ ] Admin credentials are secure
- [ ] Backup strategy is in place

## Per-Application Setup

### 1. Zoho Mail (Pilot - Do First)

**Status:** [ ] Not Started [ ] In Progress [ ] Complete

- [ ] Create SAML client in Keycloak
- [ ] Configure assertion consumer URL
- [ ] Map user attributes (email, firstName, lastName)
- [ ] Download IdP metadata
- [ ] Configure Zoho with IdP metadata
- [ ] Test SSO login
- [ ] Enable for pilot group
- [ ] Enable for all users
- [ ] Configure MFA in Keycloak

### 2. HRM System

**Status:** [ ] Not Started [ ] In Progress [ ] Complete

- [ ] Determine protocol (OIDC or SAML)
- [ ] Create client in Keycloak
- [ ] Configure redirect URIs
- [ ] Set up role mappings
- [ ] Configure user attributes
- [ ] Test SSO login
- [ ] Map HR-specific groups/roles
- [ ] Enable for HR department
- [ ] Enable for all users

### 3. Finance System

**Status:** [ ] Not Started [ ] In Progress [ ] Complete

- [ ] Determine protocol (OIDC or SAML)
- [ ] Create client in Keycloak
- [ ] Configure redirect URIs
- [ ] Set up role mappings
- [ ] Configure user attributes
- [ ] Test SSO login
- [ ] Map Finance-specific groups/roles
- [ ] Enable for Finance department
- [ ] Enable for all users
- [ ] Configure session timeout

### 4. Projects MEL

**Status:** [ ] Not Started [ ] In Progress [ ] Complete

- [ ] Determine protocol (OIDC or SAML)
- [ ] Create client in Keycloak
- [ ] Configure redirect URIs
- [ ] Set up role mappings
- [ ] Configure user attributes
- [ ] Test SSO login
- [ ] Map Projects-specific groups/roles
- [ ] Enable for Projects team
- [ ] Enable for all users

## User Provisioning

- [ ] Decide on provisioning method:
  - [ ] Manual (Keycloak Admin Console)
  - [ ] LDAP/AD Federation
  - [ ] SCIM (if supported)
- [ ] Create user groups in Keycloak
- [ ] Map groups to application roles
- [ ] Set up joiner/mover/leaver process

## Security Configuration

- [ ] Enable MFA for admin accounts
- [ ] Enable MFA for all users (optional)
- [ ] Configure password policy
- [ ] Set session timeouts
- [ ] Enable brute force protection
- [ ] Configure audit logging
- [ ] Set up monitoring

## Documentation

- [ ] Document integration steps
- [ ] Record configuration values
- [ ] Create user guide
- [ ] Document troubleshooting steps
- [ ] Update IT support procedures

## Testing

- [ ] Test login flow
- [ ] Test logout flow
- [ ] Test session timeout
- [ ] Test password reset
- [ ] Test MFA enrollment
- [ ] Test role-based access
- [ ] Test user deprovisioning

## Production Deployment

- [ ] SSL/TLS certificates configured
- [ ] DNS configured
- [ ] Load balancer configured (if applicable)
- [ ] Backup verified
- [ ] Monitoring in place
- [ ] Runbook created
- [ ] Support team trained

## Sign-off

| Application | Integration Lead | Date | Status |
|-------------|------------------|------|--------|
| Zoho Mail | | | |
| HRM System | | | |
| Finance System | | | |
| Projects MEL | | | |
