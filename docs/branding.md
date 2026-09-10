# Branding — Azul Tech SSO

Two custom Keycloak themes, both called **`azultech`**:

- **Login theme** — the sign-in screen employees see (this doc, below).
- **Email theme** — every email Keycloak sends (onboarding, password reset,
  verification, security notices). See "Email branding" at the bottom.

Keycloak is the identity provider itself — this is the only login page staff
see, there's no upstream redirect.

## What it changes

- **Background:** deep navy → deep royal-blue gradient (`#0a1a3f` → `#1b3b93`)
  with a soft blue glow, replacing Keycloak's default light-grey PatternFly
  background.
- White login card with a royal-blue top accent and a deeper shadow so it lifts
  off the dark background.
- "Sign In" button, links and input focus rings all use the Azul Tech blue.
- The "Azul Tech" realm title is rendered white so it reads on the dark background.

The **login** and **email** themes are overridden. The account console and
admin console still use the stock Keycloak look.

## Where it lives

```
keycloak/themes/azultech/login/
├── theme.properties                 # parent=keycloak + our stylesheet
└── resources/css/azultech.css       # all the colour overrides
```

The theme directory is mounted into the container at `/opt/keycloak/themes`
(see `docker-compose.yml`), so it works for both the dev and prod stacks.

## How it's activated

The realm's **Login theme** is set to `azultech` by
`keycloak/scripts/configure-realm.sh` (idempotent — the source of truth, see
`docs/PHASE-1-REALM.md`). You can also set it by hand in the admin console:
**Realm settings → Themes → Login theme → azultech**.

`keycloak/realm-export/azul-tech-realm.json` predates the current
script-driven realm and isn't used by anything — the script builds the realm
from an empty database, not from this file.

## Editing the colours

Change the CSS custom properties at the top of
`keycloak/themes/azultech/login/resources/css/azultech.css`:

```css
--azul-navy:        #0a1a3f;   /* darkest — top of the gradient / page fill */
--azul-navy-2:      #0d2352;
--azul-royal:       #1b3b93;   /* buttons, links, card accent */
--azul-royal-hover: #24309a;
--azul-accent:      #3b6fe0;   /* focus rings / link hover */
```

- **Dev (`start-dev`):** theme cache is off — hard-refresh the login page to see
  changes.
- **Prod (`start --optimized`):** the theme cache is on. After editing the CSS,
  restart Keycloak: `docker compose -f docker-compose.yml -f docker-compose.prod.yml restart keycloak`.

## Adding a logo (optional, later)

Drop a file at `keycloak/themes/azultech/login/resources/img/logo.svg` and add to
`azultech.css`:

```css
#kc-header-wrapper {
  background: url(../img/logo.svg) no-repeat center;
  background-size: contain;
  height: 48px;
  text-indent: -9999px;   /* hide the text, keep it for screen readers */
}
```

---

# Email branding

Every email Keycloak sends now goes through the `azultech` **email** theme,
so it matches the login page (navy background, white card, royal-blue
accents) instead of stock Keycloak's unstyled `<p>` tags.

This was Rene's Phase-1 review of the onboarding emails (three screenshots):

| Screenshot | Ask | What changed |
|---|---|---|
| 1 — code in an authenticator app | The name shown should read **"Azul SSO"**, not "Azul Tech" | Realm `displayName` is now `Azul SSO`. That string is the *issuer* an authenticator app (Google Authenticator / FreeOTP / Microsoft Authenticator) shows next to the code, and the name Keycloak's emails give the account. The login page header stays "Azul Tech" — it's driven by `displayNameHtml`, which we left alone. |
| 2 — "Update Your Account" email | Should read as *setting up your single sign-on credentials*, not "your administrator wants you to update your account" | `executeActions` subject + body rewritten: **"Azul SSO: Set up your sign-in credentials"**, body explains SSO is the one login for all company apps. |
| 3 — a cleanly formatted code email | All emails should look like that | New branded HTML shell (`html/template.ftl`) with a header, a real call-to-action button, an amber "for your security, this expires in N" callout, a one-time-code block, and a support footer. |

Every subject line is now prefixed **`Azul SSO:`** and says plainly what the
mail is for, so it's recognisable in a phone notification.

## Where it lives

```
keycloak/themes/azultech/email/
├── theme.properties                      # parent=keycloak
├── html/
│   ├── template.ftl                      # the branded shell + button/code/callout macros
│   ├── executeActions.ftl                # onboarding + MFA re-enrolment
│   ├── password-reset.ftl
│   ├── email-verification.ftl
│   └── email-verification-with-code.ftl  # styled now; used only if code verification is enabled later
├── text/template.ftl                     # plain-text footer
└── messages/messages_en.properties       # every subject + all reworded body copy
```

Templates not overridden (security-event notifications, SMTP test, org
invite) inherit their text from Keycloak but still render inside the branded
shell.

## How it's activated

`keycloak/scripts/configure-realm.sh` sets the realm **Email theme** to
`azultech` (idempotent, same as the login theme). By hand:
**Realm settings → Themes → Email theme → azultech**. The sender name staff
see in their inbox is `SMTP_FROM_NAME` (`.env`), also set to `Azul SSO`.

## Editing the copy

All wording — subjects, headings, button labels, the footer, the onboarding
checklist item names — is in
`keycloak/themes/azultech/email/messages/messages_en.properties`. Colours are
inline in `html/template.ftl` (same navy/royal palette as the login CSS).

Keys passed values by Keycloak (anything with `{0}`) are run through
`java.text.MessageFormat` — keep `{0}` placeholders intact and double any
literal apostrophe (`''`).

## Previewing without sending

Dev stack catches mail in MailHog — `http://localhost:8025`. Trigger a real
one:

```bash
./keycloak/scripts/provision-users.sh keycloak/scripts/pilot-users.example.csv
# or, for one existing user, resend from Admin Console → Users → <user> →
# Credentials → Credential Reset → pick actions → Send email
```

Theme cache: off in dev (`start-dev`), on in prod — after editing, restart
Keycloak (same command as the login theme above).

## Not done here (flagged for Rene)

- **The one-time code cannot go *in* the subject line** ("Azul SSO: 623 986").
  Keycloak doesn't pass the code to the subject formatter for any built-in
  email, and Phase 1 doesn't send login codes by email at all (login is
  password + authenticator app). Putting a code in the subject needs a
  custom authenticator/SPI — a separate piece of work if email-code sign-in
  is ever wanted.
- **Swahili email copy.** The realm offers `sw`, but neither stock Keycloak
  nor this theme ships Swahili email text, so `sw` users get the English
  emails (no regression). Add `messages/messages_sw.properties` when a
  translation is available.
- **Existing authenticator-app entries** still show "Azul Tech" — the issuer
  is baked in when the user enrols. Only re-enrolment picks up "Azul SSO".
  Fine for the pilot (few users, pre-go-live).
