# MFA lost-device recovery procedure

Rene's prerequisite before mandating MFA for everyone: a documented,
identity-verified recovery procedure for a lost/replaced authenticator
device, so mandatory MFA doesn't lock a real person out of their own
account. This is that procedure.

## What a user has, going in

Every account is provisioned with `CONFIGURE_TOTP` and
`CONFIGURE_RECOVERY_AUTHN_CODES` as required actions (see
`docs/PHASE-1-REALM.md`), so at enrolment each person receives **12
single-use recovery codes**, shown once, which they're told to save
(print/download/password manager).

## Path 1 — the user still has a recovery code

They use it in place of a TOTP code at the MFA challenge. No admin
involvement needed. This is the expected self-service path and should cover
the large majority of lost-device cases, which is why recovery codes are
mandatory at enrolment rather than optional.

## Path 2 — the user has no recovery code left (lost both device and codes)

This is the case that needs an identity-verified, admin-assisted reset.

1. **User reports it** to a `/Platform-Admins` member through a channel that
   is not itself the compromised account (e.g. in person, phone call, or a
   message from a known-good secondary channel — not an email that could
   itself be compromised alongside the device).
2. **Identity verification** — the admin confirms the requester is who they
   claim to be via a method independent of the Keycloak account itself:
   video call with a known colleague present, in-person with a company ID,
   or a manager/Yvonne vouching directly. This step is the entire point of
   the procedure — skipping it turns "I lost my phone" into a social-
   engineering bypass of MFA.
3. **Admin removes the user's TOTP credential(s) and resets recovery codes**
   in the Keycloak Admin Console (Users → the user → Credentials → remove
   the OTP credential; Users → the user → Credentials → reset actions →
   `CONFIGURE_TOTP` + `CONFIGURE_RECOVERY_AUTHN_CODES`), then sends a fresh
   `execute-actions-email` (same no-admin-set-password mechanism as normal
   onboarding — the admin never sees or sets a credential, only triggers the
   re-enrolment link).
4. **User re-enrols** via the emailed link: new TOTP device, new recovery
   codes.
5. **Audit**: the admin action (credential removal + required-action reset)
   lands in Keycloak's admin event log automatically. Log the identity
   verification method used (step 2) somewhere reviewable — for now, a note
   in the admin's own record of the request; a formal append-only log is
   listed as Finance/HR-migration-time work in `docs/PHASE-1-REALM.md`.

## What this procedure explicitly does not allow

- An admin resetting MFA on a self-serve/automated basis, with no human
  verification step.
- An admin ever setting or seeing a user's password or TOTP secret — the
  reset is always "clear the old credential, send a fresh self-service
  enrolment link," never "hand them a new one directly."

## Open item

Who besides Yvonne and Ronald counts as an acceptable identity-verifier for
step 2, once the platform-admin group grows beyond two people — needs a
named list, not "any platform-admin," so this isn't gameable by compromising
the least-careful admin.
