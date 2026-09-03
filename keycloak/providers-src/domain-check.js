/*
 * Azul Tech Email Domain Guard
 * ----------------------------
 * Runs as the FIRST step of the "first broker login" flow.
 * Rejects any Zoho account whose email is not on an allowed company domain,
 * BEFORE a local Keycloak user is created.
 *
 * Allowed domains are read from the realm attribute "allowedEmailDomains"
 * (comma-separated). Falls back to "azultech.rw" if the attribute is absent.
 */

var AuthenticationFlowError = Java.type('org.keycloak.authentication.AuthenticationFlowError');
var AbstractIdpAuthenticator = Java.type('org.keycloak.authentication.authenticators.broker.AbstractIdpAuthenticator');
var SerializedBrokeredIdentityContext = Java.type('org.keycloak.authentication.authenticators.broker.util.SerializedBrokeredIdentityContext');
var Response = Java.type('javax.ws.rs.core.Response');
var LOG = Java.type('org.jboss.logging.Logger').getLogger('azul-domain-guard');

function allowedDomains(context) {
  var raw = null;
  try {
    raw = context.getRealm().getAttribute('allowedEmailDomains');
  } catch (e) {
    raw = null;
  }
  if (!raw || raw.trim().length === 0) {
    raw = 'azultech.rw';
  }
  return raw.toLowerCase().split(',').map(function (d) { return d.trim(); })
    .filter(function (d) { return d.length > 0; });
}

function emailFromBrokerContext(context) {
  try {
    var authSession = context.getAuthenticationSession();
    var serialized = SerializedBrokeredIdentityContext.readFromAuthenticationSession(
      authSession, AbstractIdpAuthenticator.BROKERED_CONTEXT_NOTE);
    return serialized != null ? serialized.getEmail() : null;
  } catch (e) {
    LOG.warn('Could not read brokered identity email: ' + e);
    return null;
  }
}

function authenticate(context) {
  var email = emailFromBrokerContext(context);
  if (email == null && context.getUser() != null) {
    email = context.getUser().getEmail();
  }
  email = email == null ? '' : email.toLowerCase().trim();

  var domains = allowedDomains(context);
  var permitted = false;
  for (var i = 0; i < domains.length; i++) {
    if (email.length > 0 && email.endsWith('@' + domains[i])) {
      permitted = true;
      break;
    }
  }

  if (permitted) {
    LOG.info('Domain guard: allowing ' + email);
    context.success();
    return;
  }

  LOG.warn('Domain guard: denying "' + email + '" (allowed: ' + domains.join(', ') + ')');
  var challenge = context.form()
    .setError('Your account (' + (email || 'unknown') + ') is not part of Azul Tech and cannot use this sign-in.')
    .createErrorPage(Response.Status.FORBIDDEN);
  context.failure(AuthenticationFlowError.ACCESS_DENIED, challenge);
}

function action(context) {
  authenticate(context);
}
