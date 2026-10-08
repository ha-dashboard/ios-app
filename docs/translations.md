# Adding a translation

HA Dashboard's own UI text (Settings, alerts, buttons, placeholders) is translated
with standard iOS `.strings` files. Entity state text ("Away", "Open", "Heat") is
*not* translated here — it comes from your Home Assistant server automatically
(see `docs/plans/i18n-plan.md` §2 if you're curious why).

`en.lproj` is the source of truth. Translators never edit it — only add a new
`<lang>.lproj` next to it.

## Four steps, no Xcode required

1. Copy the English strings as your starting point:

   ```bash
   cp -R HADashboard/en.lproj HADashboard/fr.lproj   # use your language code
   ```

2. Translate the **right-hand side only** in `HADashboard/fr.lproj/Localizable.strings`.
   Leave everything else byte-identical:
   - The keys (left-hand side, before `=`).
   - Format specifiers such as `%1$@`, `%2$ld`. These are positional — you may
     reorder words around them, but never remove, add, or retype one. A
     mismatched specifier is a crash, not a typo.
   - `\n` line breaks.
   - The `/* comment */` above each entry — it tells you where the string
     appears and any length limit (many of these sit in fixed-width pills or
     badges on an iPad).

   If `HADashboard/fr.lproj/Localizable.stringsdict` exists, it needs plural
   categories too. English only needs `one` / `other`. Most languages need a
   different set — French, for example, needs `one` / `many` / `other`, and
   treats `0` as singular (`0 minute`, not `0 minutes`). Fill in whatever
   categories your language's plural rules require; leave `other` as the
   catch-all.

3. Add your language code to `CFBundleLocalizations` in `project.yml`
   (`targets.HADashboard.info.properties`), then regenerate the Xcode project:

   ```bash
   scripts/regen.sh
   ```

4. Validate before opening a PR:

   ```bash
   scripts/check-translations.sh
   ```

   This checks that your file has exactly the same keys as `en.lproj` (missing
   keys are fine — they fall back to English at runtime; extra keys are not,
   they're almost always a typo), that every format specifier matches English
   exactly, and that the file is UTF-8 with no BOM.

## Encoding

Save as **UTF-8, no BOM**. A `.strings` file saved as UTF-16, or with a BOM
added by some Windows editors, will not show an error — it will silently fall
back to English on-device, which is a confusing first-PR experience. Running
`scripts/check-translations.sh` catches this before you open the PR.

## What not to translate

- `HADashboard/Demo/HADemoDataProvider.m` — fixture data for Demo mode. Out of
  scope; a real HA server supplies real entity names in your language already.
- Anything inside `HAEntityDetailSection.m` that reads an attribute label HA
  already serves (most of them) — those come from your HA server's own
  translations, not from this app.
- The `en_US_POSIX` date/time parsers used for the HA API wire format. If you
  see one of these and think it needs localising, it doesn't — it's parsing a
  machine-readable timestamp, not displaying one. Ask before touching it.

## Review

A translation-only PR should touch nothing outside `HADashboard/<lang>.lproj/`
and `project.yml`'s `CFBundleLocalizations`. If a PR needs more than that
(e.g. a string is missing from `en.lproj`, or a layout clips at your language's
typical text length), open an issue instead so a maintainer can fix the app
side — please don't guess at an app code change in a translation PR.

Machine-translated strings are not accepted for the longer `helpText:`
paragraphs in Settings that describe the camera/RTSP security model — a
mistranslation there could mislead someone about whether their camera stream
is encrypted. Flag anything you're unsure of in the PR description rather than
guessing.
