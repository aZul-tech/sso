<#import "template.ftl" as layout>
<@layout.emailLayout>
    <@layout.heading title=msg("passwordResetHeading") />
    <p style="margin:0 0 16px;">${kcSanitize(msg("passwordResetIntro"))?no_esc}</p>
    <@layout.button href=link label=msg("passwordResetButton") />
    <@layout.callout>${msg("azulExpiryLink", linkExpirationFormatter(linkExpiration))}</@layout.callout>
    <@layout.linkFallback href=link />
    <p style="margin:16px 0 0; font-size:13px; color:#8a93a5;">${kcSanitize(msg("passwordResetIgnore"))?no_esc}</p>
</@layout.emailLayout>
