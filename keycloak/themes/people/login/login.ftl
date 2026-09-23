<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('username','password') displayInfo=false; section>
  <#if section = "header">
  <#elseif section = "form">
    <div id="kc-form">
      <div id="kc-form-wrapper">
        <div class="client-branding">
          <img class="client-brand-logo" src="${url.resourcesPath}/img/logo.png" alt="People" />
          <div class="client-brand-subtitle">Secure access to <a href="#" class="client-brand-link" onclick="document.getElementById('people-info-modal').style.display='flex';return false;">People</a></div>
        </div>
        <div id="people-info-modal" class="app-info-modal">
          <div class="app-info-card">
            <button type="button" class="app-info-close" onclick="document.getElementById('people-info-modal').style.display='none';" aria-label="Close">&times;</button>
            <div class="app-info-heading">Developer Information</div>
            <div class="app-info-body">
              <div class="app-info-row"><span class="app-info-label">App name:</span><span class="app-info-value">People</span></div>
              <div class="app-info-row"><span class="app-info-label">Access:</span><span class="app-info-value">Human Resource management system</span></div>
              <div class="app-info-row"><span class="app-info-label">Support email:</span><span class="app-info-value">support@azultech.rw</span></div>
              <div class="app-info-row"><span class="app-info-label">Support:</span><span class="app-info-value">IT Service Desk — Mon-Fri, 9:00 - 17:00 (CAT)</span></div>
            </div>
          </div>
        </div>
        <#if realm.password>
          <form id="kc-form-login" onsubmit="login.disabled = true; return true;" action="${url.loginAction}" method="post">
            <div class="form-group">
              <label for="username" class="pf-c-form-label">${msg("username")}</label>
              <input tabindex="1" id="username" class="pf-c-form-control" name="username" value="${(login.username!'')}" type="text" autocomplete="username" />
            </div>
            <div class="form-group">
              <label for="password" class="pf-c-form-label">${msg("password")}</label>
              <input tabindex="2" id="password" class="pf-c-form-control" name="password" type="password" autocomplete="current-password" />
            </div>
            <input type="hidden" id="credentialId" name="credentialId" value="${(auth.selectedCredential!'')}"/>
            <div id="kc-form-options" class="form-options">
              <#if realm.resetPasswordAllowed>
                <div class="forgot-password">
                  <a href="${url.loginResetCredentialsUrl}">${msg("doForgotPassword")}</a>
                </div>
              </#if>
            </div>
            <div id="kc-form-buttons">
              <input tabindex="4" class="btn btn-primary btn-lg" name="login" id="kc-login" type="submit" value="${msg("doLogIn")}" />
            </div>
          </form>
        </#if>
      </div>
    </div>
  </#if>
</@layout.registrationLayout>
