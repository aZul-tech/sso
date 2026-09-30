<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('username','password') displayInfo=false; section>
  <#if section = "header">
  <#elseif section = "form">
    <div id="kc-form">
      <div id="kc-form-wrapper">
        <div class="client-branding">
          <img class="client-brand-logo" src="${url.resourcesPath}/img/logo.svg" alt="People" />
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
              <label for="username" class="pf-c-form -label">${msg("username")}</label>
              <input tabindex="1" id="username" class="pf-c-form-control" name="username" value="${(login.username!'')}" type="text" autocomplete="username" />
            </div>
            <div class="form-group">
              <label for="password" class="pf-c-form-label">${msg("password")}</label>
              <div class="password-field">
                <input tabindex="2" id="password" class="pf-c-form-control" name="password" type="password" autocomplete="current-password" />
                <button type="button" class="password-toggle" data-password-toggle aria-controls="password" aria-label="${msg('showPassword')}" data-label-show="${msg('showPassword')}" data-label-hide="${msg('hidePassword')}">
                  <svg class="password-toggle-icon" data-icon="show" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"/><circle cx="12" cy="12" r="3"/></svg>
                  <svg class="password-toggle-icon" data-icon="hide" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><path d="M10.733 5.076a10.744 10.744 0 0 1 11.205 6.575 1 1 0 0 1 0 .696 10.747 10.747 0 0 1-1.444 2.49"/><path d="M14.084 14.158a3 3 0 0 1-4.242-4.242"/><path d="M17.479 17.499a10.75 10.75 0 0 1-15.417-5.151 1 1 0 0 1 0-.696 10.75 10.75 0 0 1 4.446-5.143"/><path d="m2 2 20 20"/></svg>
                </button>
              </div>
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
        <script src="${url.resourcesPath}/js/password-toggle.js"></script>
      </div>
    </div>
  </#if>
</@layout.registrationLayout>
