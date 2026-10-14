# librewolf

[Design](../../docs/design/README.md) › [Themes](../../docs/design/themes/README.md) › Browser and mail

The Letterpress chrome for LibreWolf and Thunderbird: toolbars, tabs and panes as paper, ink and one accent.
Two static `userChrome.css` sheets hold the rules, and each theme's generated `browser.css` holds the colors, so a theme switch changes the colors and leaves the rules alone.
`librewolf.overrides.cfg` also sets LibreWolf's page fonts and changes five of its privacy and session defaults.

| | |
|---|---|
| Needs | LibreWolf 157.0.1 and Thunderbird 157.0.1, tested 2026-10; Literata and Monaspace Xenon; one theme's `browser.css` |
| Copy alone | yes: two files in each profile's `chrome` folder, and one pref |
| License | MIT |

## What it needs

- LibreWolf 157.0.1 and Thunderbird 157.0.1 from Arch's `extra` repo, tested 2026-10.
  The LibreWolf sheet is written against Firefox 157's Nova chrome and its design tokens, and the Thunderbird sheet against Thunderbird 156's `--layout-*` scale.
  The LibreWolf sheet also sets the pre-Nova names of its variables (`--toolbar-bgcolor`, `--tab-selected-bgcolor`, `--arrowpanel-*`, `--lwt-*`), so an ESR 140 build gets the same page.
  An app ignores a variable it does not know.
- One theme's `browser.css` from `dotfiles/.config/themes/<id>/`, which sets `color-scheme` and the `--lp-*` colors the sheets use ([The palette](#the-palette)).
- Literata for the chrome and for page text, and Monaspace Xenon for code in pages ([Typography](../../docs/design/typography/README.md)).
- The pref `toolkit.legacyUserProfileCustomizations.stylesheets` set to `true`: without it, both apps ignore `userChrome.css`.
- Not needed: Nix, Home Manager or `dram`.

## Copy it alone

1. Find the app's profile folder.
   In LibreWolf, open `about:support` and use Open Directory beside Profile Directory.
   In Thunderbird, open Help › Troubleshooting Information and use Open Folder beside Profile Folder.
2. Make a `chrome` folder in it, and copy the app's sheet there as `userChrome.css`: `dotfiles/.librewolf/chrome/userChrome.css` for LibreWolf, `dotfiles/.thunderbird-chrome/userChrome.css` for Thunderbird.
3. Copy one theme's `browser.css` beside it as `letterpress-colors.css`, for example `dotfiles/.config/themes/washi/browser.css`.
   Each sheet starts with `@import url("letterpress-colors.css")`.
4. Set `toolkit.legacyUserProfileCustomizations.stylesheets` to `true`: in LibreWolf in `about:config`, in Thunderbird in Settings › General › Config Editor.
   Or copy `librewolf.overrides.cfg` to `~/.librewolf/`, and `user.js.default` into the Thunderbird profile as `user.js`.
   Both files set more than this pref ([Prefs set and left alone](#prefs-set-and-left-alone)), so read them first.
5. Restart the app, which reads the sheets at startup.
6. It worked when the tab strip is flat paper with a 2 px accent rule under the selected tab's title, and the URL bar takes a 1 px accent border when focused.
   In Thunderbird the selected tab's own tab line is in the accent, and a selected message sits on a paper shade.

On Windows the same files work: the profiles are under `%APPDATA%\librewolf\Profiles\` and `%APPDATA%\Thunderbird\Profiles\`, and LibreWolf reads `%USERPROFILE%\.librewolf\librewolf.overrides.cfg`.
To change themes, copy another theme's `browser.css` over `letterpress-colors.css` and restart.

## How it is wired here

`modules/desktop.nix` links `librewolf.overrides.cfg` to `~/.librewolf/`, the `chrome` folder to `~/.librewolf/chrome/` and the whole of `dotfiles/.thunderbird-chrome/` to `~/.thunderbird-chrome/`, on hosts with the desktop role.
A profile folder has a random name and is machine state, so `dram-theme` links the chrome into each profile on each switch.
It finds the profiles under `~/.librewolf/` and `~/.thunderbird/`, from the `Path=` lines of `profiles.ini` and a `*.default*` glob.
Each profile's `chrome/` gets two links: `userChrome.css` to the tracked sheet, and `letterpress-colors.css` to `~/.config/themes/current/browser.css`.
The colors link goes through the `current` symlink, so the next switch changes the colors without touching the profile.
`ln -sfn` runs on each switch, so a profile made since the last one gets its links at the next.
`dram-theme` copies `user.js.default` into a Thunderbird profile as `user.js` only when the profile has none.
Both apps read the sheets at startup, and the notification after a switch says to restart them.

A new host has no profiles until each app has run once.
Run `dram switch`, start LibreWolf and Thunderbird once, run `dram theme <id>`, and restart both.
The profile folder that LibreWolf's `about:support` opens then holds the two links in `chrome/`, and `about:config` shows `toolkit.legacyUserProfileCustomizations.stylesheets` as `true`.

LibreWolf reads `librewolf.overrides.cfg` at each start, on top of its own `librewolf.cfg`, so the prefs outlast upgrades.
They are `defaultPref` lines: each sets a default, and a value chosen in Settings or `about:config` wins over it.
Thunderbird has no autoconfig here, and it applies `user.js` at each start over `prefs.js`.
A pref listed in `user.js` cannot be changed in Settings, because the next start puts it back: edit the profile's `user.js`, or `user.js.default` for profiles seeded later.

On Windows, `windows/roles/desktop.nix` stages the two sheets, `librewolf.overrides.cfg`, `user.js.default` and the `browser.css` of washi, the theme the Windows look is rendered from.
`install/windows/dram-windows/look.ps1` copies them into each LibreWolf and Thunderbird profile, and the cfg to `%USERPROFILE%\.librewolf\`.
It rewrites a file when it differs, and seeds a Thunderbird `user.js` only where the profile has none.
The five files are inputs of the Windows build (`windows/build/cabin-win/inputs.json`), so after a change `bin/check.sh` §19 fails until `bin/render-windows.sh` has rendered the build again.

After a palette change, run the generator and commit what it writes:

```sh
python3 bin/gen-browser-css.py           # each theme
python3 bin/gen-browser-css.py washi     # one theme
```

`bin/check.sh` does not compare the committed `browser.css` files with a fresh run (2026-10).

## What the chrome looks like

| Part | Ink |
|---|---|
| window, toolbars, tab strip | `base`, with Nova's gradient over the toolbox turned off |
| URL bar, search field, sidebar | `mantle`, one step down from the paper |
| Thunderbird's message list and reading pane | `view` ([The palette](#the-palette)) |
| Thunderbird's folder pane and spaces rail | `mantle` and `crust` |
| popovers, menus, panels | `raised`, with a hairline edge; LibreWolf adds a soft shadow |
| lines between the strips | 1 px of `rule`, the ink at 18 % |
| corners | 3 px; 2 px on LibreWolf's menu items and small controls |
| tab titles | `subtext`, and the selected tab's title in the ink |
| the selected tab | a 2 px accent rule under its title, at the leading edge with vertical tabs; in Thunderbird its own tab line in the accent |
| focus | a 1 px accent border on the URL bar and the fields; focus rings and switches in the accent |
| links | the theme's `blue` |
| Thunderbird's selected rows | `surface0` or `surface1` under the ink, with no accent fill |
| Thunderbird's accent fills | the primary button and the badge for new unread mail |

The rule under the selected tab is an inset shadow, so the tab keeps its size.
The chrome face is Literata at 13 px on `:root`, because Firefox's own `font: message-box` would take the GTK font, Literata 11 pt, which is 14.7 px.
Thunderbird gets the same size from `mail.uifontsize`, and its sheet holds it if the pref is lost.
On Linux, Thunderbird paints its toolbox in GTK's header-bar color, and the sheet sets it back to the paper.
Both sheets hide the GTK window buttons in the tab strip on Linux, where Hyprland draws no server-side decorations and closes windows by key.
That rule sits in `@media (-moz-platform: linux)`, because on Windows the same box holds minimize, maximize and close.
Each declaration carries `!important`: `userChrome.css` is a user sheet, and the app's own skin is an author sheet that would win otherwise.

## The palette

`bin/gen-browser-css.py` writes each theme's `browser.css` from its `waybar.css`, the `accent` and `accent_dim` of its `palette.lua`, and the `COLOR_SCHEME` of its `meta.sh`.
The file sets `color-scheme` on `:root` and defines `--lp-*` names only, and the two sheets map those onto each app's own variables.
Its light and dark derivations are the ones the GTK stylesheets use ([Generators](../../docs/design/themes/generators.md)).

| Name | Value |
|---|---|
| `--lp-base`, `mantle`, `crust`, `surface0`, `surface1`, `text`, `subtext`, `overlay`, `red`, `green`, `yellow`, `blue` | the theme's colors of those names |
| `--lp-accent`, `accent-dim` | `accent` and `accent_dim` from `palette.lua` |
| `--lp-accent-fg` | white, `crust` or `text`, whichever contrasts most with the accent: the text on an accent fill |
| `--lp-view` | the reading surface: `mantle` on a dark theme, `base` mixed 45 % toward white on a light one |
| `--lp-raised` | popovers and menus: `surface0` on a dark theme, `view` on a light one |
| `--lp-rule`, `shade`, `hover`, `active`, `faint` | the ink at 18, 10, 8, 14 and 55 % |

A theme is light when its `COLOR_SCHEME` is `prefer-light`: washi-day, catppuccin-latte and solarized-paper (2026-10).

## Dark and light under resistFingerprinting

The chrome follows the theme in both apps.
Firefox takes the chrome's scheme from `browser.theme.toolbar-theme` (0 dark, 1 light, 2 system, in Firefox 157's `layout/style/PreferenceSheet.cpp`), and the active Firefox theme sets that pref.
The default theme, "System theme — auto", keeps it at 2, so the toolbars follow the portal's color scheme, which `dram-theme` sets from the theme's `COLOR_SCHEME`.
LibreWolf's resistFingerprinting is not consulted for the chrome.
`browser.css` also pins `color-scheme` on `:root`, so each `light-dark()` value the sheets leave alone resolves to the theme's side.

Pages stay light.
Under resistFingerprinting, Firefox's `Document::PreferredColorScheme` answers light before it reads `layout.css.prefers-color-scheme.content-override` or `browser.theme.content-theme` (`dom/base/Document.cpp`).
So no pref can darken pages while resistFingerprinting is on.
LibreWolf's [FAQ](https://librewolf.net/docs/faq/) calls this "one of the privacy measures that come with RFP".
The FAQ's way out trades resistFingerprinting for fingerprinting protection minus that one target:

```js
defaultPref("privacy.resistFingerprinting", false);
defaultPref("privacy.fingerprintingProtection", true);
defaultPref("privacy.fingerprintingProtection.overrides", "+AllTargets,-CSSPrefersColorScheme");
```

`librewolf.overrides.cfg` quotes these lines as a comment and leaves them off: giving up resistFingerprinting is a choice for the person using the profile.

## Prefs set and left alone

| Pref | Value | App | Why |
|---|---|---|---|
| `toolkit.legacyUserProfileCustomizations.stylesheets` | `true` | both | loads `userChrome.css` |
| `font.default.x-western`, `font.default.x-cyrillic` | `serif` | both | text that names no font gets the serif |
| `font.name.serif.x-western`, `font.name.serif.x-cyrillic` | `Literata` | both | the house text face |
| `font.name.monospace.x-western`, `font.name.monospace.x-cyrillic` | `Monaspace Xenon` | both | code |
| `font.size.variable.x-western`, `font.size.monospace.x-western`, `font.minimum-size.x-western` | `16`, `13`, `11` | both | the text sizes in px |
| `browser.uidensity` | `1` | LibreWolf | the compact chrome; a choice in Settings wins, since the pref is sticky |
| `browser.compactmode.show` | `true` | LibreWolf | keeps compact density among the choices |
| `privacy.clearOnShutdown_v2.cookiesAndStorage` | `false` | LibreWolf | logins survive a restart, and the Proton Pass extension keeps its session cookie |
| `privacy.clearOnShutdown_v2.historyFormDataAndDownloads` | `false` | LibreWolf | history, form data and the downloads list survive too |
| `privacy.resistFingerprinting.letterboxing` | `false` | LibreWolf | no gray bars around the page at 1440p |
| `webgl.disabled` | `false` | LibreWolf | maps and browser games need WebGL |
| `browser.startup.page` | `3` | LibreWolf | the last windows and tabs come back at start |
| `mail.uidensity` | `0` | Thunderbird | the compact chrome |
| `mail.uifontsize` | `13` | Thunderbird | the chrome's size in px, set as an inline style on its root |

LibreWolf's prefs are in `librewolf.overrides.cfg`, and Thunderbird's in `user.js.default`.
Left as they are in LibreWolf:

| Pref | Why |
|---|---|
| `browser.tabs.inTitlebar` | stays 2, so GTK decides; `userChrome.css` hides the window buttons instead |
| `browser.toolbars.bookmarks.visibility` | LibreWolf's `always` guards resistFingerprinting's window rounding |
| `widget.gtk.overlay-scrollbars.enabled` | `true` by default |
| `browser.theme.*` | the active Firefox theme owns them |
| `font.name.sans-serif.*` | a page that asks for sans-serif gets Noto Sans from fontconfig |

In Thunderbird, the pane layout and the list style are left to the profile: `mail.pane_config.dynamic` and `mail.threadpane.listview`.

## Files

| File | What it does |
|---|---|
| `chrome/userChrome.css` | LibreWolf's rules: its chrome variables mapped to the `--lp-*` colors, the selected-tab rule, the hairlines, the window buttons hidden on Linux |
| `librewolf.overrides.cfg` | LibreWolf's prefs, read at each start |
| `dotfiles/.thunderbird-chrome/userChrome.css` | Thunderbird's rules on its `--layout-*` scale ([thunderbird-chrome](../.thunderbird-chrome/README.md)) |
| `dotfiles/.thunderbird-chrome/user.js.default` | the seed of a Thunderbird profile's `user.js` |
| `dotfiles/.config/themes/<id>/browser.css` | one theme's colors; generated |
| `bin/gen-browser-css.py` | writes each theme's `browser.css` |
| `dotfiles/.local/bin/dram-theme` | links the sheets and the colors into each profile, and seeds `user.js` |

## License

MIT, Patrick Jordan.
