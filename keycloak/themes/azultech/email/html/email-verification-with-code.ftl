<#--
  Shown when Keycloak verifies an email address with a one-time CODE instead
  of a link (e.g. identity-broker first-login verification). Not exercised by
  the Phase-1 flow yet, but styled now so it matches if code verification is
  turned on later. `code` is the only guaranteed variable here — do not
  reference link/expiration variables in this template.
-->
<#import "template.ftl" as layout>
<@layout.emailLayout>
    <@layout.heading title=msg("emailVerificationCodeHeading") />
    <p style="margin:0 0 8px;">${kcSanitize(msg("emailVerificationCodeIntro"))?no_esc}</p>
    <@layout.code value=code />
    <@layout.callout>${msg("azulCodeExpiry")}</@layout.callout>
</@layout.emailLayout>
