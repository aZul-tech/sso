<#import "template.ftl" as layout>
<@layout.emailLayout>
    <@layout.heading title=msg("emailVerificationHeading") />
    <p style="margin:0 0 16px;">${kcSanitize(msg("emailVerificationIntro"))?no_esc}</p>
    <@layout.button href=link label=msg("emailVerificationButton") />
    <@layout.callout>${msg("azulExpiryLink", linkExpirationFormatter(linkExpiration))}</@layout.callout>
    <@layout.linkFallback href=link />
    <p style="margin:16px 0 0; font-size:13px; color:#8a93a5;">${kcSanitize(msg("emailVerificationIgnore"))?no_esc}</p>
</@layout.emailLayout>
