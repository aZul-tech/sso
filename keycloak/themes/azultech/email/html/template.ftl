<#--
  Azul Tech SSO — branded HTML email shell.

  `emailLayout` is the outer chrome used by every HTML email. The helper
  macros (button / code / callout / heading / linkFallback) give the
  individual templates a consistent look without repeating inline styles.

  Email-client constraints this file works around:
   - layout is table-based (Outlook ignores <div> widths and fl/grid)
   - every style is inline (no <style>, no external CSS)
   - the navy gradient is progressive-enhancement only; bgcolor="#0a1a3f"
     is the fallback every client honours
-->
<#macro emailLayout>
<!DOCTYPE html>
<html lang="${locale.language}" dir="${(ltr)?then('ltr','rtl')}" xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <meta http-equiv="X-UA-Compatible" content="IE=edge"/>
  <meta name="color-scheme" content="light"/>
  <meta name="supported-color-schemes" content="light"/>
  <title>${msg("azulBrand")}</title>
</head>
<body style="margin:0; padding:0; width:100%; background-color:#0a1a3f; -webkit-text-size-adjust:100%; -ms-text-size-adjust:100%;">
  <span style="display:none !important; visibility:hidden; mso-hide:all; font-size:0; line-height:0; max-height:0; max-width:0; opacity:0; overflow:hidden;">${msg("azulBrand")}</span>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#0a1a3f" style="background-color:#0a1a3f; background-image:linear-gradient(160deg,#0a1a3f 0%,#0d2352 45%,#1b3b93 100%);">
    <tr>
      <td align="center" style="padding:32px 16px;">

        <table role="presentation" width="480" cellpadding="0" cellspacing="0" border="0" style="width:480px; max-width:480px; background-color:#ffffff; border-radius:12px; overflow:hidden;">
          <tr>
            <td bgcolor="#1b3b93" style="background-color:#1b3b93; padding:22px 32px; font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:18px; font-weight:700; letter-spacing:0.4px; color:#ffffff;">
              ${msg("azulBrand")}
            </td>
          </tr>
          <tr>
            <td style="padding:32px; font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:15px; line-height:1.6; color:#1f2733;">
              <#nested>
            </td>
          </tr>
          <tr>
            <td style="padding:20px 32px 28px; border-top:1px solid #e6e9f0; font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:12px; line-height:1.6; color:#8a93a5;">
              ${msg("azulFooterHelp")}<br/>
              ${msg("azulFooterAutomated")}
            </td>
          </tr>
        </table>

        <table role="presentation" width="480" cellpadding="0" cellspacing="0" border="0" style="width:480px; max-width:480px;">
          <tr>
            <td style="padding:16px 8px 0; font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:11px; line-height:1.5; color:#9fb0d6;">
              Azul Tech &middot; Single Sign-On
            </td>
          </tr>
        </table>

      </td>
    </tr>
  </table>
</body>
</html>
</#macro>

<#--  Section heading inside the card.  -->
<#macro heading title>
<h1 style="margin:0 0 16px; font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:20px; font-weight:700; line-height:1.3; color:#0a1a3f;">${title}</h1>
</#macro>

<#--  Primary call-to-action button.  -->
<#macro button href label>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:24px 0;">
  <tr>
    <td align="center" bgcolor="#1b3b93" style="background-color:#1b3b93; border-radius:8px;">
      <a href="${href?html}" target="_blank" style="display:inline-block; padding:13px 30px; font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:15px; font-weight:600; color:#ffffff; text-decoration:none; border-radius:8px;">${label}</a>
    </td>
  </tr>
</table>
</#macro>

<#--  Plain-text link fallback for clients that drop the button.  -->
<#macro linkFallback href>
<p style="margin:0 0 6px; font-size:12px; color:#8a93a5;">${msg("azulButtonFallback")}</p>
<p style="margin:0 0 4px; font-size:12px; line-height:1.5; word-break:break-all;"><a href="${href?html}" target="_blank" style="color:#1b3b93;">${href?html}</a></p>
</#macro>

<#--  Big, spaced one-time code.  -->
<#macro code value>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:24px 0;">
  <tr>
    <td align="center" bgcolor="#f4f6fb" style="background-color:#f4f6fb; border:1px solid #e6e9f0; border-radius:10px; padding:20px 12px; font-family:'SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace; font-size:30px; font-weight:700; letter-spacing:8px; color:#0a1a3f;">${value}</td>
  </tr>
</table>
</#macro>

<#--  Amber "for your security" callout.  -->
<#macro callout>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:24px 0;">
  <tr>
    <td bgcolor="#fff8e6" style="background-color:#fff8e6; border:1px solid #f0e0b0; border-radius:8px; padding:12px 16px; font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:13px; line-height:1.55; color:#7a5c15;"><#nested></td>
  </tr>
</table>
</#macro>
