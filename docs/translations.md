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
   scripts/check-translations.sh --strict
   ```

   **A language can't be merged partially.** `--strict` is what CI actually
   runs (`.github/workflows/translations.yml`, the `Translations /
   check-translations` check), and it fails your PR if your `.lproj` is
   incomplete in any of these ways:

   - Any key present in `en.lproj` but missing from yours. (Without
     `--strict` this is only a warning — a partial file still falls back to
     English at runtime — but CI does not accept a partial merge, so get it
     to zero before opening a PR, not just before it's convenient.)
   - Any key in yours that isn't in `en.lproj` at all (almost always a typo
     in the key name — compare against `en.lproj`).
   - Any value that's empty or whitespace-only.
   - A mismatched `%@`/`%ld`/etc. format specifier against the English
     value — this is a crash, not a cosmetic bug, and fails in **every**
     mode, strict or not.
   - If `Localizable.stringsdict` exists: yours must exist too, and provide
     every plural category your language needs (§2 above — `one`/`other`
     for English, `one`/`many`/`other` for French, and so on).
   - A `.strings` file that isn't valid UTF-8, or doesn't parse (an
     unescaped quote, a missing semicolon, etc.) — fails in every mode too.

   Run the plain (non-`--strict`) check any time while you're still working;
   it reports the same things but only fails your local run on the
   always-fatal issues (extra keys, bad specifiers, invalid syntax/encoding),
   so you can see your remaining-keys count without it exiting non-zero.
   Switch to `--strict` before you call a PR ready.

   **A value identical to English is never a failure**, in either mode — some
   strings legitimately don't change (`"OK"`, `"HA"`, a brand name). The
   checker still lists them, as an informational summary, so you can sanity
   check nothing was accidentally left untranslated by copy-paste. If you
   have a string you know should stay identical and want to silence it from
   that summary, list its key in an optional allowlist file:

   ```bash
   # HADashboard/fr.lproj/.i18n-identical-allowlist
   # One key per line, # comments allowed.
   action.ok
   settings.live_stream.camera.front   # "Front" is also correct in French
   ```

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
and `project.yml`'s `CFBundleLocalizations`. The `Translations /
check-translations` GitHub check runs `scripts/check-translations.sh
--strict` automatically on your PR (no Xcode needed, it finishes in
seconds) — a red check means your `.lproj` is incomplete or has an error;
the log tells you exactly which keys and what to fix. A PR with a partial
translation will not be merged, by design — finish the keys first, or open
it as a draft while you work through them. If a PR needs more than that
(e.g. a string is missing from `en.lproj`, or a layout clips at your language's
typical text length), open an issue instead so a maintainer can fix the app
side — please don't guess at an app code change in a translation PR.

Machine-translated strings are not accepted for the longer `helpText:`
paragraphs in Settings that describe the camera/RTSP security model — a
mistranslation there could mislead someone about whether their camera stream
is encrypted. Flag anything you're unsure of in the PR description rather than
guessing.
