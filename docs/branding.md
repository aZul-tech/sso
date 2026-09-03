# Login page branding — Azul Tech SSO

The Keycloak login screen (the page employees see when they sign in through
Zoho / into Lunchify) uses a custom theme called **`azultech`** instead of the
stock Keycloak look.

## What it changes

- **Background:** deep navy → deep royal-blue gradient (`#0a1a3f` → `#1b3b93`)
  with a soft blue glow, replacing Keycloak's default light-grey PatternFly
  background.
- White login card with a royal-blue top accent and a deeper shadow so it lifts
  off the dark background.
- "Sign In" button, links, input focus rings and the Zoho button all use the
  Azul Tech blue.
- The "Azul Tech" realm title is rendered white so it reads on the dark background.

Only the **login** theme is overridden. Account console, admin console and email
themes are untouched.

## Where it lives

```
keycloak/themes/azultech/login/
├── theme.properties                 # parent=keycloak + our stylesheet
└── resources/css/azultech.css       # all the colour overrides
```

The theme directory is mounted into the container at `/opt/keycloak/themes`
(see `docker-compose.yml`), so it works for both the dev and prod stacks.

## How it's activated

The realm's **Login theme** is set to `azultech`:

- Fresh imports: `"loginTheme": "azultech"` in
  `keycloak/realm-export/azul-tech-realm.json`.
- Existing realms: `keycloak/scripts/configure-realm.sh` sets it (idempotent).
  You can also set it by hand in the admin console:
  **Realm settings → Themes → Login theme → azultech**.

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
