# Keycloak patching cadence (proposal for the ISMS)

Rene asked for a proposed patching cadence for Keycloak as part of the ISMS.
This is a starting proposal, not yet ratified — intended as input to that
process, not a replacement for it.

## Cadence

| Update type | Cadence | Trigger |
|---|---|---|
| **Security patch** (CVE affecting the running version) | Within 7 days of disclosure, sooner if actively exploited | Keycloak security advisory / CVE feed |
| **Minor version** (e.g. 26.7.x → 26.8.x) | Quarterly, next maintenance window | Scheduled |
| **Major version** (e.g. 26.x → 27.x) | Annually, planned separately with its own test cycle | Scheduled, not bundled with routine patching |

Keycloak's own release cadence (quarterly minors, LTS-style support windows)
is the natural pacing to track against, rather than inventing a stricter one
that fights upstream's own schedule.

## Process for every update, regardless of type

1. Apply to a non-production Keycloak instance running from the same
   `docker-compose.yml` / realm-as-code (`configure-realm.sh`) as
   production.
2. Re-run the exit test (`docker compose down -v && up -d`, then
   `configure-realm.sh`, then `provision-users.sh` against a test CSV) to
   confirm the realm still reconstructs cleanly on the new version.
3. Re-run the onboarding + login smoke test (password set, MFA enrolment,
   MFA challenge, correct role-based landing) for at least one test user.
4. Check the release notes for deprecations affecting anything this realm
   uses (client scopes, mappers, admin API endpoints called by the scripts).
5. Promote to production during the maintenance window; keep the previous
   image tag available for rollback.

## Ownership

Platform-admin group (`/Platform-Admins`) owns triggering and executing
this — not an app owner's responsibility, since it's IdP infrastructure
shared across every app on the realm.

## Not yet decided (needs Rene / ISMS input)

- Formal CVE feed subscription mechanism (Keycloak security mailing list,
  GitHub security advisories, or a vulnerability-scanning tool already in
  use elsewhere at Azul Tech).
- Whether the maintenance window needs to be a published, client-facing
  schedule once this is serving more than the pilot.
- Rollback SLA if a patch breaks something in production.
