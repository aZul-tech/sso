<#import "template.ftl" as layout>
<#outputformat "plainText">
<#assign requiredActionsText><#if requiredActions??><#list requiredActions><#items as reqActionItem>${msg("requiredAction.${reqActionItem}")}<#sep>, </#items></#list></#if></#assign>
</#outputformat>
<@layout.emailLayout>
    <@layout.heading title=msg("executeActionsHeading") />
    <p style="margin:0 0 16px;">${kcSanitize(msg("executeActionsIntro"))?no_esc}</p>
    <#if requiredActionsText?has_content>
    <p style="margin:0 0 4px; font-size:13px; color:#5b6472;">${msg("executeActionsList", requiredActionsText)}</p>
    </#if>
    <@layout.button href=link label=msg("executeActionsButton") />
    <@layout.callout>${msg("azulExpiryLink", linkExpirationFormatter(linkExpiration))}</@layout.callout>
    <@layout.linkFallback href=link />
    <p style="margin:16px 0 0; font-size:13px; color:#8a93a5;">${kcSanitize(msg("executeActionsIgnore"))?no_esc}</p>
</@layout.emailLayout>
