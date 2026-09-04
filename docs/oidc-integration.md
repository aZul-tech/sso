# OIDC Integration Guide for Azul Tech Applications

This guide covers integrating applications with Keycloak using OpenID Connect (OIDC).

## OIDC Endpoints

All applications use these Keycloak endpoints:

```
Issuer URL:               https://YOUR-KEYCLOAK-DOMAIN/realms/azultech
Authorization Endpoint:   https://YOUR-KEYCLOAK-DOMAIN/realms/azultech/protocol/openid-connect/auth
Token Endpoint:           https://YOUR-KEYCLOAK-DOMAIN/realms/azultech/protocol/openid-connect/token
UserInfo Endpoint:        https://YOUR-KEYCLOAK-DOMAIN/realms/azultech/protocol/openid-connect/userinfo
JWKS URI:                 https://YOUR-KEYCLOAK-DOMAIN/realms/azultech/protocol/openid-connect/certs
Logout Endpoint:          https://YOUR-KEYCLOAK-DOMAIN/realms/azultech/protocol/openid-connect/logout
```

## Register a New Application

### Using the Script

```bash
cd keycloak/scripts
chmod +x register-app.sh
./register-app.sh <client-id> <client-name> <redirect-uri>
```

Example:
```bash
./register-app.sh projects-mel "Projects MEL" "http://localhost:3000/*"
```

### Manual Registration

1. Login to Keycloak Admin Console
2. Navigate to Clients → Create Client
3. Configure:
   - Client Type: `OpenID Connect`
   - Client ID: Your application identifier
   - Name: Application display name
   - Enabled: ON
   - Valid Redirect URIs: Your application callback URL
   - Web Origins: Your application origin

## Integration Examples

### Node.js / Express (Passport.js)

```javascript
const express = require('express');
const passport = require('passport');
const session = require('express-session');
const { Strategy: OpenIDConnectStrategy } = require('passport-openidconnect');

const app = express();

app.use(session({
  secret: 'your-session-secret',
  resave: false,
  saveUninitialized: true
}));

app.use(passport.initialize());
app.use(passport.session());

passport.use(new OpenIDConnectStrategy({
  issuer: 'https://YOUR-KEYCLOAK-DOMAIN/realms/azultech',
  authorizationURL: 'https://YOUR-KEYCLOAK-DOMAIN/realms/azultech/protocol/openid-connect/auth',
  tokenURL: 'https://YOUR-KEYCLOAK-DOMAIN/realms/azultech/protocol/openid-connect/token',
  userInfoURL: 'https://YOUR-KEYCLOAK-DOMAIN/realms/azultech/protocol/openid-connect/userinfo',
  clientID: 'YOUR-CLIENT-ID',
  clientSecret: 'YOUR-CLIENT-SECRET',
  callbackURL: 'http://localhost:3000/callback',
  scope: ['openid', 'profile', 'email']
}, (issuer, profile, done) => {
  // Find or create user in your database
  return done(null, profile);
}));

passport.serializeUser((user, done) => done(null, user));
passport.deserializeUser((user, done) => done(null, user));

// Routes
app.get('/login', passport.authenticate('openidconnect'));

app.get('/callback',
  passport.authenticate('openidconnect', { failureRedirect: '/login' }),
  (req, res) => {
    res.redirect('/');
  }
);

app.get('/logout', (req, res) => {
  req.logout();
  res.redirect('/');
});

app.get('/', (req, res) => {
  if (req.isAuthenticated()) {
    res.send(`Hello ${req.user.displayName}!`);
  } else {
    res.send('<a href="/login">Login with SSO</a>');
  }
});

app.listen(3000);
```

### Python / Flask (Authlib)

```python
from flask import Flask, redirect, url_for, session
from authlib.integrations.flask_client import OAuth

app = Flask(__name__)
app.secret_key = 'your-secret-key'

oauth = OAuth(app)

oauth.register(
    name='keycloak',
    client_id='YOUR-CLIENT-ID',
    client_secret='YOUR-CLIENT-SECRET',
    server_metadata_url='https://YOUR-KEYCLOAK-DOMAIN/realms/azultech/.well-known/openid-configuration',
    client_kwargs={'scope': 'openid profile email'}
)

@app.route('/')
def homepage():
    user = session.get('user')
    if user:
        return f'Hello {user["name"]}!'
    return '<a href="/login">Login with SSO</a>'

@app.route('/login')
def login():
    redirect_uri = url_for('auth_callback', _external=True)
    return oauth.keycloak.authorize_redirect(redirect_uri)

@app.route('/callback')
def auth_callback():
    token = oauth.keycloak.authorize_access_token()
    user = oauth.keycloak.parse_id_token(token)
    session['user'] = user
    return redirect('/')

@app.route('/logout')
def logout():
    session.pop('user', None)
    return redirect('/')

if __name__ == '__main__':
    app.run(port=3000)
```

### React / Next.js

```javascript
// Using next-auth
import NextAuth from 'next-auth';
import KeycloakProvider from 'next-auth/providers/keycloak';

export const authOptions = {
  providers: [
    KeycloakProvider({
      clientId: process.env.KEYCLOAK_CLIENT_ID,
      clientSecret: process.env.KEYCLOAK_CLIENT_SECRET,
      issuer: process.env.KEYCLOAK_ISSUER,
    })
  ],
  callbacks: {
    async jwt({ token, account }) {
      if (account) {
        token.accessToken = account.access_token;
      }
      return token;
    },
    async session({ session, token }) {
      session.accessToken = token.accessToken;
      return session;
    }
  }
};

export default NextAuth(authOptions);
```

Environment variables (.env.local):
```
KEYCLOAK_CLIENT_ID=YOUR-CLIENT-ID
KEYCLOAK_CLIENT_SECRET=YOUR-CLIENT-SECRET
KEYCLOAK_ISSUER=https://YOUR-KEYCLOAK-DOMAIN/realms/azultech
```

## User Claims in Tokens

Keycloak includes these claims in the ID token:

```json
{
  "sub": "user-uuid",
  "email": "user@azultech.rw",
  "email_verified": true,
  "name": "John Doe",
  "given_name": "John",
  "family_name": "Doe",
  "preferred_username": "john.doe",
  "groups": ["/Departments/Engineering"],
  "department": "Engineering",
  "realm_access": { "roles": ["staff"] },
  "resource_access": { "<your-client-id>": { "roles": ["<your-app-role>"] } }
}
```

## Role-Based Access Control

Groups (`/Departments/*`) model the **organisation**, not app permissions —
don't authorize on group membership. Authorize on **your own client's
role claim** (`resource_access.<your-client-id>.roles`), assigned in
Keycloak to the `/App-Access/<YourApp>/<Tier>` group that grants it. See
`docs/PHASE-1-REALM.md` for the full model.

```javascript
// Example middleware — checks YOUR app's own client role, not a group
function requireClientRole(role) {
  return (req, res, next) => {
    const roles = req.user.resource_access?.['<your-client-id>']?.roles || [];
    if (roles.includes(role)) return next();
    return res.status(403).send('Access denied');
  };
}

app.get('/admin', requireClientRole('super-admin'), (req, res) => {
  res.send('Admin Panel');
});
```

Realm roles (`realm_access.roles`) exist only for genuinely cross-cutting
concerns (`staff`, `contractor`, `platform-admin`) — not app-tier
permissions:

```javascript
function requireRealmRole(role) {
  return (req, res, next) => {
    const userRoles = req.user.realm_access?.roles || [];
    if (userRoles.includes(role)) return next();
    return res.status(403).send('Access denied');
  };
}
```

## Security Best Practices

1. **Key your user records off the token's `sub` claim, never off email or
   username** — people's names/emails change, `sub` doesn't.
2. **Always validate tokens** on the server side.
3. **Use HTTPS** in production.
4. **Store secrets securely** (environment variables, secrets manager).
5. **Implement logout** that terminates the Keycloak session.
6. **Handle token refresh** properly.
7. **Validate redirect URIs** to prevent open redirect attacks.

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| CORS errors | Check Web Origins in Keycloak client config |
| Invalid redirect_uri | Ensure exact match in Valid Redirect URIs |
| Token validation failed | Verify issuer URL and JWKS URI |
| User not found | Check user exists in Keycloak realm |

### Enable Debug Logging

Add to your application:
```javascript
// For Node.js
process.env.DEBUG = 'passport:*';
```

## Next Steps

1. Configure each application using the appropriate guide
2. Set up role mappings for each application
3. Test SSO flow end-to-end
4. Enable MFA for enhanced security
