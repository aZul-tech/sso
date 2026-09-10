<#ftl output_format="plainText">
<#--
  Azul Tech SSO — plain-text email shell. Same footer as the HTML shell so
  the two versions of a message stay consistent.
-->
<#macro emailLayout>
<#nested>

--
${msg("azulFooterHelp")}
${msg("azulFooterAutomated")}
</#macro>
