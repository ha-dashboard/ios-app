# Localisation plan — release 1.3.0

Status: draft for maintainer review. Not approved, not scheduled.

Driver: [issue #19](https://github.com/ha-dashboard/ios-app/issues/19). A French user on
iPad 2 / iOS 9.3.5 (universal 1.2.6 IPA) asks for translations and offers to do the
French translation. They also report `person` showing the raw state `not_home` where
HA's own card shows "Absent", and that Mushroom / Bubble cards are "not really working".

The issue conflates two independent problems. This plan separates them:

| Problem | Owner of the text | Fix |
|---|---|---|
| App chrome: settings, alerts, buttons, placeholders | **the app** | `NSLocalizedString` + `.lproj` (§1) |
| Entity states and attribute labels: `not_home`, `Open`, `Target temperature` | **Home Assistant** | `frontend/get_translations` (§2) |

`not_home` is **not** a translation bug. It is a missing-feature bug that is visible in
English too — see §2.5. Phase 2 fixes it for every language including English, and is
independently valuable even if no translation ever ships.

### Verification status of claims in this document

- **Verified (live)** — measured against the maintainer's HA 2026.9.4 instance over a
  read-only WebSocket session on 2026-10-08. Numbers are from that one install and will
  differ elsewhere.
- **Verified (source)** — read from `home-assistant/core` @ `14b92708` and
  `home-assistant/frontend` @ `f0a6772` (both `dev`), or from this repo at the cited
  `file:line`.
- **Assumption** — explicitly flagged inline. Nothing in the phase gates depends on an
  unflagged assumption.

---

## 1. App-owned strings: inventory and mechanism

### 1.1 Current state

Verified (repo): there is no localisation whatsoever.

- `0` occurrences of `NSLocalizedString` across `HADashboard/`.
- No `.strings`, `.stringsdict`, `.xcstrings`, or `*.lproj` directory outside `Vendor/`.
- `HADashboard/Info.plist:5-6` sets `CFBundleDevelopmentRegion` to
  `$(DEVELOPMENT_LANGUAGE)`; `project.yml` never sets `DEVELOPMENT_LANGUAGE`, so it
  resolves to Xcode's default (`en`). There is no `CFBundleLocalizations` key.
- All UI is programmatic. `LaunchScreen.storyboard` is the only storyboard and contains
  no localisable text worth extracting.

### 1.2 Inventory

Counted by grepping assignment *sinks* rather than all `@"…"` literals, because the
codebase is full of non-UI literals (HTTP headers, RTSP protocol lines, MDI glyph names,
attribute keys, `HALog` messages). The sink set used:

```
.text =   setTitle:   .title =   .placeholder =   accessibilityLabel =
alertControllerWithTitle:   actionWithTitle:   initWithTitle:   insertSegmentWithTitle:
```

**239 sink hits across 38 files**, collapsing to **~123 distinct literals**, of which
**~115 are real UI strings** (the rest are hex colours, a sample URL, and MDI/emoji
glyphs such as `@"\U0001F512"`). A further **68 distinct `stringWithFormat:` literals**
carry user-visible text with format specifiers.

Top files by sink count — this is where the work is:

| File | Sinks | Character of the strings |
|---|---:|---|
| `HADashboard/Controllers/HASettingsViewController.m` | 43 (76 incl. `helpText:`/`aboutRow:`/segment arrays) | Section titles, long help paragraphs, alert titles + bodies, toasts, segmented-control items |
| `HADashboard/Views/HAEntityDetailSection.m` | 41 | Attribute/feature row labels — **most of these should come from HA instead**, see §2.4 |
| `HADashboard/Views/Cells/HACameraEntityCell.m` | 21 | `Unavailable`, `No signal`, ` LIVE `, ` REC `, bitrate format strings |
| `HADashboard/Views/HAConnectionFormView.m` | 20 | Field labels, placeholders, token-generation instructions |
| `HADashboard/Views/Cells/HAThermostatGaugeCell.m` | 9 | Mode labels, `Target: —` |
| `HADashboard/Views/Cells/HALockEntityCell.m` | 9 | `Lock`, `Unlock`, `Open`, `Confirm Open?` |
| `HADashboard/Views/Cells/HATimerEntityCell.m` | 8 | `Start`, `Pause`, `Cancel`, `Set Duration`, `--:--:--` |
| `HADashboard/Views/Cells/HAMediaPlayerEntityCell.m` | 8 | `Source`, `Sound Mode`, transport labels |
| `HADashboard/Views/Cells/HACalendarCardCell.m` | 7 | `All day`, `Today`, `No upcoming events`, `From:`, `To:` |
| `HADashboard/Controllers/HAEntityDetailViewController.m` | 6 | Nav titles, section headers |
| `HADashboard/Views/Cells/HASceneEntityCell.m` | 6 | `Activate`, `Activated` |
| `HADashboard/Views/Cells/HAAlarmEntityCell.m` | 5 | `Disarm`, `Code`, `Enter code` |
| `HADashboard/Controllers/HADashboardViewController.m` | 5 | `Settings`, `Try Demo Mode`, `Not connected` |
| remaining 25 files | 1–4 each | Mostly single labels per cell |

Non-sink surfaces that also need keys:

- **`HAEntityDisplayHelper` state text** — `HADashboard/Views/HAEntityDisplayHelper.m:100-153`:
  **37 distinct English strings** in the `binarySensorStateForDeviceClass:` tables
  (`Open`/`Closed`, `Detected`/`Clear`, `Home`/`Away`, …), plus the `On`/`Off` default at
  `:101` and `:152`. **Phase 2 deletes these tables entirely** — HA serves all of them.
- **Relative time** — `HADashboard/Views/HAEntityDisplayHelper.m:255-289`: `Just now`,
  `1 minute`/`%ld minutes`, `1 hour`/`%ld hours`, `Yesterday`, `Tomorrow`, `%ld days`,
  and the `In %@` / `%@ ago` wrappers. **9 strings, 4 of them plural-sensitive.**
- **`humanReadableState:`** — `HADashboard/Views/HAEntityDisplayHelper.m:159-179`. An
  algorithmic English fallback (underscore→space, camelCase split, `capitalizedString`)
  reached from **12 call sites**. It is *not* a string table and cannot be translated;
  Phase 2 demotes it to a last-resort fallback.
- **`HAPersonEntityCell`** — hardcoded `@"Home"` / `@"Away"` at
  `HADashboard/Views/Cells/HAPersonEntityCell.m:68,71`. Delete in Phase 2.
- **`@"Unavailable"` / `@"Unknown"` / `@"--"`** — 20 sites. These stay app-owned: HA does
  **not** serve them (§2.3).
- **`HADashboard/Demo/HADemoDataProvider.m`** — 396 capitalised literals, but **zero**
  UI sinks: it is fixture data (`friendly_name`, device classes, media titles).
  **Out of scope.** Demo mode showing English sample entity names is correct behaviour —
  a real HA server supplies real names.

Deliberately excluded from the inventory: `HALog` messages, `HARTSPServer` /
`HAAACEncoder` protocol and SDP strings, `HASensorReporter` sensor *state values* (these
are machine-readable payloads sent **to** HA — translating them would break the
integration), `HAIconMapper` glyph names, `HAEntityAttributes` key constants.

**Working estimate for Phase 1: ~200 keys** (115 sink strings + ~40 format strings with
user text + ~45 from the relative-time, camera, and detail-section surfaces), shrinking
by ~50 once Phase 2 removes the state tables.

### 1.3 Mechanism — recommendation

**Use `NSLocalizedString` with `Localizable.strings` in `en.lproj`, plus
`Localizable.stringsdict` for the handful of plural strings. Do not use String
Catalogs (`.xcstrings`).**

Reasoning:

- `.strings` / `.stringsdict` are read by `NSBundle` / `NSLocalizedString` and have been
  supported since iOS 2 / iOS 7 respectively. They are compiled to binary plists at build
  time and are architecture-independent, so the armv7 iOS 9 slice consumes them
  identically to arm64.
- String Catalogs are an **Xcode 15+ authoring** format. Xcode compiles `.xcstrings`
  down to `.strings`/`.stringsdict` in the bundle, so in principle iOS 9 could consume
  the *output*. **Recommend against anyway**, for three concrete reasons:
  1. The device build does not use a plain `xcodebuild` product. `scripts/build.sh:386-397`
     builds an arm64 bundle with `xcodebuild`, then `cp -R`s it and swaps in a `lipo`'d
     universal binary. Any build-time resource transformation that Xcode 26 performs is
     inherited, not controlled — a format that compiles differently across Xcode 26 and
     27 (both are supported toolchains per `CLAUDE.md`) is a liability on the one target
     that cannot be re-tested quickly.
  2. `.xcstrings` is a single JSON blob. A contributor PR touching it is unreviewable in
     a diff and unmergeable in parallel. psolyca is an outside contributor; per-language
     `.strings` files give them one file to own.
  3. No tooling in `scripts/` or `.github/workflows/build.yml` currently understands
     `.xcstrings`; a plain-text format can be linted with 30 lines of shell (§4.3).

**Packaging — verified it works, with one gate.**

- `project.yml:28-31` declares `- path: HADashboard, type: group`. XcodeGen 2.46.0
  (confirmed installed) walks that directory, groups `*.lproj` children into Xcode
  variant groups, and infers the build phase from the extension — `.strings` and
  `.stringsdict` land in Resources. **No `project.yml` change is required** beyond
  adding `DEVELOPMENT_LANGUAGE: en` to `settings.base` for explicitness.
  *Assumption to verify in Phase 1 step 1:* that XcodeGen 2.46 variant-group handling
  behaves as described for this layout. Gate it with the §1.5 check before writing any
  strings.
- The device build carries resources for free: `scripts/build.sh:397` `cp -R`s the whole
  `xcodebuild` bundle template (which already contains `en.lproj/Localizable.strings`)
  and only then replaces the Mach-O and re-signs. `.github/workflows/build.yml` uses the
  same pattern for `archive-release`. Only `LaunchScreen.storyboardc` is recompiled
  (`build.sh:404-408`); `.strings` need no equivalent step.
- `scripts/build.sh:412-419` patches `Info.plist` with `plutil`. It removes
  `UIRequiredDeviceCapabilities` and `UILaunchScreen` but touches nothing
  localisation-related. **Add one assertion** to CI (§5.4), not a patch.

### 1.4 Key naming convention

Dotted, lowercase, snake-cased segments: `<area>.<subject>.<role>`. Keys are opaque
identifiers, **never** the English text — English-as-key makes a copy-edit silently fork
every translation.

```
action.cancel                      action.ok                action.done
settings.section.kiosk_mode.title  settings.section.kiosk_mode.help
settings.about.version             settings.about.license
alert.reset.title                  alert.reset.message
card.calendar.no_upcoming_events   card.calendar.all_day
cell.camera.no_signal              cell.lock.confirm_open.title
cell.timer.set_duration
state.default.unavailable          state.default.unknown
attr.aux_heat.name
relative.just_now                  relative.minutes   (stringsdict)
format.state_with_unit             ("%1$@ %2$@")
```

Rules:

1. `state.default.*` deliberately mirrors HA's own frontend key
   (`src/translations/en.json` → `state.default.unavailable`). HA does not serve these
   over the WebSocket (§2.3), so the app must own them — matching the name makes that
   relationship obvious.
2. `attr.*` is reserved for the small set of attribute labels HA does **not** serve;
   see §2.4. Everything else in `HAEntityDetailSection.m` is deleted, not translated.
3. Every format string gets **positional specifiers** (`%1$@`, `%2$ld`). French and
   English often need different word order; non-positional specifiers make reordering
   impossible and are the single most common cause of `-[__NSCFString
   stringByAppendingString:]` crashes in translated apps.
4. `comment:` on every `NSLocalizedString` is mandatory and must state where the string
   appears and any length constraint, e.g.
   `/* Button in lock cell. Max ~10 chars — sits in a fixed-width pill. */`.

### 1.5 Access API

Define one macro and one lookup class rather than calling `NSLocalizedString` directly,
so the in-app override (§1.6) has somewhere to live:

```objc
// HADashboard/Localization/HAStrings.h
#define HALocalizedString(key, comment) [HAStrings localizedStringForKey:(key)]
#define HALocalizedPlural(key, count)   [HAStrings localizedPluralForKey:(key) count:(count)]
```

`HAStrings` resolves against an override `NSBundle` for the selected `.lproj` when one is
set, else `[NSBundle mainBundle]`, via
`-localizedStringForKey:value:table:`. On a miss it returns the key itself in `DEBUG`
(loud) and the `en` value in Release (quiet). The macro keeps the
`(key, comment)` shape so `genstrings -s HALocalizedString` still extracts.

**Phase 1 step 1 gate — do this before writing ~200 keys.** Add exactly one key
(`action.ok`), wire `HAStrings`, build all four targets, and confirm:

```bash
scripts/build.sh sim && scripts/build.sh device
unzip -l <ipa>  | grep -E 'lproj|Localizable'      # .strings present in the device IPA
plutil -p "<app>/en.lproj/Localizable.strings"      # compiled, readable
scripts/build.sh mac                                 # Catalyst: Contents/Resources/en.lproj
```

If the device IPA is missing `en.lproj`, stop and add an explicit
`- path: HADashboard/en.lproj, buildPhase: resources` entry to `project.yml` (mirroring
the existing `Vendor/MDI/*` entries at `project.yml:37-40`) before continuing.

### 1.6 How the user picks a language — recommendation

There are **two independent language axes**, and conflating them is the main design trap
here.

| Axis | Content | Source |
|---|---|---|
| **App chrome** | Settings, alerts, buttons, `Unavailable` | **iOS system language**, with an in-app override |
| **HA content** | Entity names, states, attribute labels | **HA's language**, resolved per §2.6 |

**Recommendation: follow iOS for app chrome; follow HA for HA content; offer one in-app
override that sets both.**

Why not follow HA's profile language for app chrome:

- The app chrome is iOS chrome. A French user with an English iPad expects iOS-shaped
  behaviour, and `NSLocalizedString` gives correct `preferredLocalizations` negotiation
  (region fallback, `fr-CA` → `fr`) for free.
- HA's `frontend.user_data` language is per-HA-user and arrives **after** WebSocket auth.
  Chrome localised from it would visibly flip language a second after launch, and would
  be wrong on the login and settings screens, which render before any connection exists.
- The login screen must be translated *before* there is a server to ask.

Why offer an in-app override anyway:

- Kiosk iPads. A wall-mounted iPad 2 is frequently left at the factory English while the
  household is French, and the device language picker is several taps deep in iOS 9
  Settings and triggers a full respring.
- It lets the HA-content language be forced too, which matters for the exact comparison
  psolyca is making (app card vs HA card side by side).

**Fallback chain for app chrome:**

1. In-app override, if set (`HAAuthManager`, alongside the existing `kioskMode` /
   `autoReloadDashboard` booleans at `HADashboard/Auth/HAAuthManager.h:30-43`).
2. `[NSBundle mainBundle].preferredLocalizations.firstObject` — iOS's own negotiation
   against `CFBundleLocalizations`.
3. `en`.

Implement the override as a bundle swap in `HAStrings`, **not** by writing
`AppleLanguages` into `NSUserDefaults`. The `AppleLanguages` trick needs a relaunch to
take effect, is undocumented, and interacts badly with `UIApplicationSceneManifest`
(`project.yml:56-62`). A bundle swap takes effect on the next view reload.

Settings UI: one row in `HASettingsViewController`, rendered with the existing
`createToggleSection:`-style helpers — a picker listing *System*, *English*, and each
`CFBundleLocalizations` entry by its own endonym (`Français`, not `French`). Hide the row
entirely while only one language ships, so Phase 1 has **zero visible change**.

---

## 2. HA-provided translations for states and attributes

### 2.1 The mechanism — verified

`frontend/get_translations` is a WebSocket command. Schema, verified in source at
`homeassistant/components/frontend/__init__.py:1022-1044` (registered `:479`):

```json
{"id": N, "type": "frontend/get_translations",
 "language": "fr", "category": "entity_component",
 "integration": ["person", "cover"], "config_flow": false}
```

- `language` and `category` are **required** strings. `integration` is optional and
  accepts a string *or* a list (core coerces via `EnsureList`). `config_flow` is optional.
- Response: `{"id":N,"type":"result","success":true,"result":{"resources":{…}}}`.
- **Keys are flat dotted strings**, built by `recursive_flatten` in
  `homeassistant/helpers/translation.py:33-43`, applied at `:328-330` with prefix
  `component.{component}.{category}.`. Not nested JSON. Verified live.
- `category` is typed as a bare `str` in core — it is **not** validated against an enum,
  and an unknown category returns `{}` rather than an error (verified live: a bogus
  category returned `success: true` with 0 keys). The authoritative list is the
  frontend's union type at `frontend/src/data/translation.ts:60-79`: `title`, `state`,
  `entity`, `entity_component`, `exceptions`, `config`, `config_subentries`,
  `config_panel`, `options`, `device_automation`, `mfa_setup`, `system_health`,
  `application_credentials`, `issues`, `preview_features`, `selector`, `services`,
  `triggers`, `conditions`.

Measured on the maintainer's HA 2026.9.4, unfiltered (verified live):

| Category | en keys | en bytes | fr keys | fr bytes |
|---|---:|---:|---:|---:|
| `entity_component` | **805** | **61,551** | 805 | 63,600 |
| `entity` | 3,664 | 343,083 | 3,664 | 356,064 |
| `services` | 3,150 | 330,920 | 2,402 | 266,124 |
| `config` | 1,617 | 190,135 | — | — |
| `title` | 184 | 7,765 | 184 | 7,921 |
| `state` | **0** | 2 | 0 | 2 |

The `state` category is **empty and must not be used**. It is the pre-0.109 legacy path,
still fetched only by `getHassTranslationsPre109` in
`frontend/src/state/translations-mixin.ts:312-326`. Any design built on `state.person.not_home`
is dead on arrival.

`integration` filtering works and is dramatic (verified live, `fr`,
`entity_component`): `integration: "person"` → 8 keys / 618 bytes; the 29 core domains
this app renders → 687 keys / 54,518 bytes; unfiltered → 805 keys / 63,600 bytes.

### 2.2 Lookup order — verified

The frontend's single source of truth is `computeStateToPartsFromEntityAttributes` in
`frontend/src/common/entity/compute_state_display.ts:275-293`. Order:

1. `component.{platform}.entity.{domain}.{translation_key}.state.{state}` — category
   `entity`, only when the entity registry entry has a `translation_key`.
   `{platform}` is the **integration** that created the entity (`hue`, `sonos`), not the
   domain.
2. `component.{domain}.entity_component.{device_class}.state.{state}` — category
   `entity_component`, only when the entity has a `device_class`.
3. `component.{domain}.entity_component._.state.{state}` — `_` is the literal
   no-device-class bucket.
4. The raw state string.

Core mirrors this exactly in `homeassistant/helpers/translation.py:462-493`
(`async_translate_state`), which is good evidence the templates are stable API rather
than frontend-internal.

Confirmed live against the maintainer's instance:

| Key | en | fr |
|---|---|---|
| `component.person.entity_component._.state.not_home` | **Away** | **Absent** |
| `component.person.entity_component._.state.home` | Home | Maison |
| `component.binary_sensor.entity_component.door.state.on` | Open | Ouvert |
| `component.binary_sensor.entity_component.motion.state.on` | Detected | Détecté |
| `component.cover.entity_component._.state.open` | Open | Ouvert |
| `component.lock.entity_component._.state.locked` | Locked | Verrouillé |
| `component.climate.entity_component._.state.heat` | Heat | Chauffage |
| `component.media_player.entity_component._.state.playing` | Playing | Lecture en cours |

That is psolyca's exact report, reproduced and explained.

Coverage of `entity_component` `.state.*` keys per domain, measured live — this is
precisely the set of English tables Phase 2 deletes:

```
binary_sensor 58   climate 40   media_player 34   light 23   water_heater 16
alarm_control_panel 15   humidifier 15   weather 15   timer 10   device_tracker 8
vacuum 8   lock 7   event 7   fan 6   sensor 6   switch 6   script 6   automation 6
update 6   cover 5   valve 5   lawn_mower 5   calendar 4   input_boolean 4   number 3
person 2   remote 2   counter 2   sun 2   scene 0   select 0   button 0   todo 0
```

### 2.3 What HA does *not* serve

`unavailable` and `unknown` are special-cased **before** the chain above, at
`frontend/src/common/entity/compute_state_display.ts:94-101`, and resolve against
`state.default.*` in the frontend's own **static bundle** — not over the WebSocket.
Verified live: `component.sensor.entity_component._.state.unavailable` does not exist
(the only `.state.unknown` hits came from a custom integration).

**Consequence:** the app's 20 `@"Unavailable"` sites stay app-owned keys
(`state.default.unavailable`, `state.default.unknown`). This is a correctness point, not
a nicety — a design that routes everything through HA will render a bare `unavailable`
to the user in every language.

There is also **no HTTP alternative.** No `/api/translations` endpoint exists in core
(verified by source search, and live: `404`). `/static/translations/<lang>-<hash>.json`
exists but carries only the frontend's own UI strings, and the hash comes from
`translations-metadata.ts` inside the JS bundle, so the URL is not constructible by an
external client (verified live: `404` for the unhashed path). **WebSocket is the only
option.**

### 2.4 Attribute labels — a second, unexpected win

`entity_component` also carries `…_.state_attributes.{attr}.name` (382 of the 805 keys
measured). Probing the labels hardcoded in `HADashboard/Views/HAEntityDetailSection.m`:

| App literal (file:line) | HA key suffix | en | fr |
|---|---|---|---|
| `@"Color Temp"` (`:141`) | `light…color_temp_kelvin.name` | Color temperature (Kelvin) | Température de couleur (Kelvin) |
| `@"Effect"` (`HAEntityDetailSection` features) | `light…effect.name` | Effect | Effet |
| `@"Fan"` (`:628`) | `climate…fan_mode.name` | Fan mode | Mode de ventilation |
| `@"Tilt"` (`:869`) | `cover…current_tilt_position.name` | Tilt position | Inclinaison |
| `@"Oscillation"` (`:1495`) | `fan…oscillating.name` | Oscillating | Oscillant |
| `@"Direction"` (`:1553`) | `fan…direction.name` | Direction | Direction |
| `@"Sound Mode"` | `media_player…sound_mode.name` | Sound mode | Mode sonore |
| `@"Source"` | `media_player…source.name` | Source | Source |
| `@"Target: —"` (`:710`, `:3457`) | `climate…temperature.name` | Target temperature | Température cible |
| `@"Aux Heat"` (`:658`) | — | **absent** (deprecated in core) | — |

**11 of 12 probed labels come free from HA**; only `Aux Heat` needs an app key
(`attr.aux_heat.name`). This meaningfully shrinks Phase 1's surface and should be folded
into Phase 2 rather than translated in Phase 1 — see §6.1 note.

Attribute *values* follow `…state_attributes.{attr}.state.{value}` (core:
`async_translate_state_attr`, `homeassistant/helpers/translation.py:496-533`), which
covers e.g. `climate` fan modes (`auto` → `Auto`, `high` → `Élevée`). Worth wiring for
`HAModeFeatureView` / `HAThermostatGaugeCell`.

### 2.5 What the app shows today, and why

For `person.psolyca` = `not_home`, the path is:

1. `HAEntityDisplayHelper formattedStateForEntity:decimals:`
   (`HADashboard/Views/HAEntityDisplayHelper.m:36-75`). `person` is not
   `input_datetime` (`:41`) and not `binary_sensor` (`:47`), so the device-class table is
   skipped.
2. `[state doubleValue]` is `0.0` and the string is neither `"0"` nor `0.`-prefixed, so
   `isNumeric` is `NO` (`:56-57`).
3. Not a timestamp. Falls through to `return state;` at `:74` — **the raw
   `not_home`.**

Whether the user ever sees the cosmetically-nicer `Not Home` depends on which cell
renders it: `humanReadableState:` (`:159`) is applied by `HAEntityCardCell.m:109`,
`HATileEntityCell.m:276`, and `HAGlanceItemView.m:132`, but **not** by
`HAPersonEntityCell`, which instead hardcodes `@"Home"` / `@"Away"` at
`HADashboard/Views/Cells/HAPersonEntityCell.m:68,71`. So the raw `not_home` psolyca is
seeing is being rendered by a non-person cell — most likely a Mushroom or Bubble card
coerced onto `HAEntityCardCell` or `HATileEntityCell` by the fallback path documented in
§7. **That is the link between their two complaints.** Worth confirming with them which
card type it was.

Note the related latent bug: `binary_sensor` `presence` already maps to `Home`/`Away` at
`HADashboard/Views/HAEntityDisplayHelper.m:126,147`, so the app has *two* independent
hardcoded Home/Away implementations with no shared source. Phase 2 collapses both.

### 2.6 Resolving HA's language — verified

The frontend uses two sources; `auth/current_user` is **not** one of them (core
`homeassistant/components/auth/__init__.py:567-600` returns no language field —
confirmed live: the response carried only `id`, `name`, `is_owner`, `is_admin`,
`credentials`, `mfa_modules`).

1. **Per-user frontend preference** — `{"type":"frontend/get_user_data","key":"language"}`
   (core `homeassistant/components/frontend/storage.py:218-231`). Verified live, returns:
   ```json
   {"value": {"language": "en-GB", "number_format": "language",
              "time_format": "language", "date_format": "language",
              "time_zone": "local", "first_weekday": "language"}}
   ```
   `value` is `null` when the user has never set a preference. The frontend *subscribes*
   rather than polls: `frontend/subscribe_user_data` with `key: "language"`
   (`storage.py:236-239`, used via `subscribeTranslationPreferences` in
   `frontend/src/state/translations-mixin.ts:141-161`). **Use the subscription** — the
   app already has `subscribeWithCommand:` at
   `HADashboard/Networking/HAConnectionManager.h:140`, so language changes refresh for
   free.
2. **Server default** — `get_config` → `language` (and `country`, `time_zone`). Verified
   live: `{"language":"en","country":"GB","time_zone":"Europe/London"}`. The app already
   issues `get_config` for the REST config fetch.

Enum values for the format preferences, from
`frontend/src/data/translation.ts:4-43`:
`NumberFormat` ∈ {`language`, `system`, `comma_decimal`, `decimal_comma`,
`space_comma`, `quote_decimal`, `none`}; `TimeFormat` ∈ {`language`, `system`, `"12"`,
`"24"`} (string digits, not integers); `DateFormat` ∈ {`language`, `system`, `DMY`,
`MDY`, `YMD`}; `TimeZone` ∈ {`local`, `server`}.

**Resolution chain for HA content:**

1. In-app override (§1.6), if set.
2. `frontend/get_user_data` key `language` → `.value.language`, if non-null.
3. `get_config` → `language`.
4. App chrome language.

Then normalise: HA ships `fr` but not `fr-CA`, and `en-GB` but the *backend* resources
are keyed `en`. The frontend handles this in `findAvailableLanguage`
(`frontend/src/util/common-translation.ts:37-66`) — lowercase, apply a `LOCALE_LOOKUP`
remap table (`zh-cn` → `zh-Hans`), then fall back `xx-YY` → `xx`. **The app should
implement the `xx-YY` → `xx` fallback and skip the remap table** (it only matters for
Chinese variants); on a miss, retry once with the bare language, then give up to `en`.
*Assumption:* that `get_translations` with an unavailable language returns the `en`
resources rather than empty — **verify** this in Phase 2 by requesting
`language: "fr-CA"` and `language: "zz"`.

### 2.7 Design: fetch, cache, and consume

**New class: `HAStateLocalizer`** (`HADashboard/Localization/HAStateLocalizer.{h,m}`),
a singleton holding one flat `NSDictionary<NSString *, NSString *>`.

**Fetch.** Insert into the existing connect sequence at
`HADashboard/Networking/HAConnectionManager.m:1063-1068`, immediately after the floor
registry — same shape as the existing optional fetch:

```objc
// after: self.floorRegistryMessageId = [self.wsClient sendCommand:...]
[self.stateLocalizer refreshForLanguage:resolvedLanguage];
```

Use the existing `-sendCommand:completion:`
(`HADashboard/Networking/HAConnectionManager.h:75`), which already routes replies through
`_pendingCompletions` (`HAConnectionManager.m:82`) — no new message-ID plumbing.

**Which categories, and the memory decision.** This is the one place where the iPad 2's
512 MB forces a real trade-off. Measured live, `fr`:

| Strategy | Keys | JSON bytes | Covers |
|---|---:|---:|---|
| `entity_component`, unfiltered | 805 | 63,600 | **All domain + device_class states, all attribute labels** |
| `entity_component`, filtered to the 29 domains the app renders | 687 | 54,518 | same, minus unused domains |
| `entity`, unfiltered | 3,664 | 356,064 | `translation_key` states **and** every per-entity name |
| `entity`, filtered to the 36 in-use platforms | 3,362 | 330,445 | same |
| `entity`, filtered, pruned to `.state.` keys only | 2,145 | 224,586 | `translation_key` states only |

**Recommendation: fetch `entity_component` unfiltered, and do _not_ fetch `entity` in
Phase 2.**

- `entity_component` at 62 KB of JSON is cheap. As an `NSDictionary` of `NSString`s it
  costs roughly 150–250 KB resident (805 key objects + 805 value objects + hash table) —
  immaterial even on an iPad 2. Fetch it unfiltered: the filtered saving is 9 KB, and
  hardcoding a domain allowlist means every new HA domain silently regresses.
- `entity` is 5× larger and buys very little. It only matters for entities that have a
  `translation_key` **and** a non-numeric state. Verified live: 1,033 of the registry
  entries carry a `translation_key`, across 36 platforms — but these are overwhelmingly
  `sensor`/`number`/`switch` entities whose displayed value is numeric and never goes
  through the state-translation path at all. Paying 330 KB of JSON (≈1 MB resident) on a
  512 MB device to translate a handful of `select` and enum-`sensor` states is the wrong
  trade.
- **Defer `entity` to a Phase 2b**, gated on a user actually reporting an untranslated
  enum state. If it ships: request it with `integration:` set to only the platforms of
  entities **present on the currently loaded dashboard** (not the whole registry), and
  prune to keys containing `.state.` before caching. Both filters are already proven to
  work live.

**`translation_key` is already available — no new fetch.** The app calls
`config/entity_registry/list` (`HADashboard/Networking/HAWebSocketClient.h:49`, issued at
`HAConnectionManager.m:1064`) and retains the raw result
(`HAConnectionManager.m:963-966`, exposed as `entityRegistryEntries`). Verified live that
this response includes both `platform` and `translation_key` per entry. The frontend uses
the abbreviated `list_for_display` variant (`tk`/`pl` keys) for bandwidth, but the app's
unabbreviated call is already correct and should **not** be changed.

**Cache.** Reuse `HACacheManager` — it is exactly right for this: per-server directories
keyed by `SHA256(serverURL)`, async and sync JSON writes, and `clearAllCaches` already
wired to the Settings "Clear Cache & Reload" action.

- Filename: `ha-translations-<lang>.json`, matching the existing kebab-case convention
  (`entity-states.json` at `HADashboard/Cache/HAEntityStateCache.m:6`;
  `dashboard-config-%@.json` at `HADashboard/Cache/HADashboardConfigCache.m:36`).
- Persistent dir (`-persistentCacheDirectory`), not expendable — translations should
  survive a cache purge so an offline kiosk keeps rendering French.
- Load from disk **synchronously at launch** before the first dashboard render, then
  refresh over WebSocket. This is what makes offline and cold-start correct, and mirrors
  the existing `-loadCachedStateIfAvailable` pattern
  (`HAConnectionManager.h:42`).
- Cap: keep **at most 2 languages** on disk (current + previous) and hard-cap any single
  cached payload at **512 KB**, discarding and falling back to raw states beyond that.
  This bounds the worst case if Phase 2b lands or a user has an unusual install.
- Refresh triggers: WebSocket (re)auth; the `frontend/subscribe_user_data` language push;
  the in-app override changing. Debounce — do not refetch on every reconnect if the
  cached payload is under ~24h old and the language is unchanged.

**Consume.** One new method, called from `HAEntityDisplayHelper`:

```objc
- (NSString *)localizedStateForDomain:(NSString *)domain
                          deviceClass:(NSString *)deviceClass
                             platform:(NSString *)platform
                       translationKey:(NSString *)translationKey
                                state:(NSString *)state;
```

Implementing the §2.2 chain, then these app-side fallbacks:

5. `state.default.unavailable` / `state.default.unknown` for those two states —
   **checked first**, before the chain, matching
   `compute_state_display.ts:94-101`.
6. `humanReadableState:` (`HAEntityDisplayHelper.m:159`) — the existing algorithmic
   English prettifier, demoted to last resort.
7. The raw state.

Then in `HAEntityDisplayHelper`:

- **Delete** the 37-entry `onStates`/`offStates` tables at
  `HAEntityDisplayHelper.m:100-153` and reroute `binarySensorStateForDeviceClass:` through
  the localizer. Keep the method signature so the 12 existing call sites and the
  `binary_sensor` branch at `:47-49` are untouched.
- **Delete** the hardcoded `Home`/`Away` at `HAPersonEntityCell.m:68-71`.
- Keep `humanReadableState:` — it is the only thing standing between a cache miss and a
  raw `not_home`.

**Behaviour when the localizer is empty** (first launch, offline, pre-auth) must be
*identical to today*. That makes Phase 2 safe to ship behind no flag: worst case it is
the current behaviour plus `Not Home` instead of `not_home`.

---

## 3. Formatting: dates, times, numbers, units on iOS 9

### 3.1 Numbers — already correct

`HAEntityDisplayHelper.m:181-205` uses a `dispatch_once` `NSNumberFormatter` with
`NSNumberFormatterDecimalStyle` and no explicit locale, so it inherits
`[NSLocale currentLocale]` and already renders `1 234,5` in French. **No change needed**
for the default path.

Two gaps:

- **HA's `number_format` preference is ignored.** A user who set `comma_decimal`
  explicitly in HA while running a French iPad will see `1 234,5` in the app and
  `1,234.5` in HA. Map the enum (§2.6) to an explicit `NSLocale` on that formatter;
  `language` and `system` both mean "use `currentLocale`", and `none` means no grouping.
  Low priority, but it is the difference between "localised" and "matches HA".
- **The static formatter is mutated per call** (`:191-201` sets
  `minimumFractionDigits` / `maximumFractionDigits` on the shared instance). That is
  already a latent data race off the main thread; adding a locale setter makes it worse.
  Give the formatter a lock or key a small `NSCache` of formatters by
  `(locale, decimals)`.

### 3.2 Dates and times — the real problem

`dateStyle`/`timeStyle` formatters are locale-correct and need no change:
`HAEntityDisplayHelper.m:279-330`, `HAEntity.m:296-305`,
`HAEntityDetailViewController.m:718,790`, `HACalendarCardCell.m:80-81`.

**Hardcoded `dateFormat` patterns on display paths are not.** A fixed pattern localises
month and day *names* but freezes field *order* and separators:

| File:line | Pattern | Problem |
|---|---|---|
| `HADashboard/Views/Cells/HACalendarCardCell.m:625` | `d MMMM yyyy` | Correct for `fr`, **wrong for `en-US`** (should be `MMMM d, yyyy`) |
| `HADashboard/Views/Cells/HACalendarCardCell.m:306` | `MMMM yyyy` | Order differs in CJK locales |
| `HADashboard/Views/HAGraphView.m:1158` | `d/M HH:mm` | `d/M` is wrong for `en-US` (`M/d`); `HH` forces 24h |
| `HADashboard/Views/HAGraphView.m:1164,1365` | `HH:mm`, `HH:mm:ss` | Forces 24h in 12h locales |
| `HADashboard/Views/HAGraphView.m:1161,1367` | `MMM d`, `MMM d, HH:mm` | US order + forced 24h |
| `HADashboard/Views/HAEntityDetailSection.m:3688,3692` | `yyyy-MM-dd HH:mm:ss` | Display path with an ISO-shaped pattern |

**Fix: `+[NSDateFormatter dateFormatFromTemplate:options:locale:]`** — available since
iOS 4, so safe on iOS 9. Pass the *template* (field set, order-agnostic) and let ICU
produce the locale's ordering:

```objc
fmt.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"jmm"   // not @"HH:mm"
                                                 options:0
                                                  locale:locale];
```

`j` is the locale-appropriate hour field — it resolves to `h` + AM/PM or `H`
automatically, which is exactly the 12h/24h fix. Templates to use: `jmm` for `HH:mm`,
`jmmss` for `HH:mm:ss`, `Mdjmm` for `d/M HH:mm`, `MMMd` for `MMM d`, `yMMMM` for
`MMMM yyyy`, `yMMMMd` for `d MMMM yyyy`.

Then honour HA's `time_format` / `date_format` preferences on top: `"12"` / `"24"`
replaces `j` with `h` / `H`; `DMY`/`MDY`/`YMD` overrides the template result. `language`
and `system` mean "take the ICU answer".

**Leave the ISO parsers alone.** `HADateUtils.m:12-44`, `HAEntity.m:265-274`,
`HALogbookManager.m:49-51,221-223`, `HAHistoryManager.m:172-174`,
`HAEntityDetailSection.m:3653,3676`, `HACalendarCardCell.m:379-381,442-443` and
`HAPerfMonitor.m:185` all correctly pin `en_US_POSIX` for wire-format parsing. Touching
any of these breaks HA API parsing. **Make this an explicit review rule** — it is the
most likely way a well-intentioned i18n PR breaks the app.

`HADashboard/Views/Cells/HAClockWeatherCell.m:195-200,397-401` already honours a
card-level `locale:` config key and falls back to `[NSLocale currentLocale]`. Keep that
precedence and slot the HA/app language between them.

### 3.3 Weekday names and first weekday

`HAWeatherEntityCell.m:216` and `HAClockWeatherCell.m:392` use `EEE`, which is
locale-correct for names. But `HACalendarCardCell` builds a month grid; HA's
`first_weekday` preference (§2.6) and the locale's own
`NSCalendar.firstWeekday` both need honouring or the French user gets a Sunday-first
calendar. Prefer HA's `first_weekday` when it is not `language`, else
`[NSCalendar currentCalendar].firstWeekday`.

### 3.4 Units

Units come from the entity's `unit_of_measurement` and are appended verbatim at
`HAEntityDisplayHelper.m:92-94`. **Do not convert or localise them** — HA already
resolves the unit system server-side (verified live: `get_config.unit_system` reported
`°C`/`km`/`L` for this install). The one gap: the duration-unit special case at
`HAEntityDisplayHelper.m:58-62` and `:207+` hardcodes `h`/`min`/`s`/`d` and emits English
`%ldh %ldm` forms. Those need app keys (`format.duration.hm`, `format.duration.ms`,
`format.duration.dh`) with positional specifiers.

---

## 4. Contributor workflow

### 4.1 File layout

```
HADashboard/
  Localization/
    HAStrings.{h,m}            # macro + bundle resolution (§1.5)
    HAStateLocalizer.{h,m}     # HA-sourced states (§2.7)
  en.lproj/
    Localizable.strings        # source of truth, maintainer-owned
    Localizable.stringsdict    # plurals, maintainer-owned
  fr.lproj/
    Localizable.strings        # psolyca-owned
    Localizable.stringsdict
docs/
  CONTRIBUTING-translations.md # the one doc a translator reads
scripts/
  i18n-lint.sh                 # §4.3
```

`en.lproj` is the source of truth. Translators never edit it.

### 4.2 Adding a language

Document as four steps, no Xcode required:

1. `cp -R HADashboard/en.lproj HADashboard/fr.lproj`
2. Translate the **right-hand side only** in `fr.lproj/Localizable.strings`. Keep keys,
   `%1$@`-style specifiers, and `\n` byte-identical. Leave the `/* comment */` blocks —
   they carry the length constraints.
3. Add `fr` to `CFBundleLocalizations` in `project.yml` (`targets.HADashboard.info.properties`)
   and run `scripts/regen.sh`.
4. `scripts/i18n-lint.sh` must pass.

Encoding: **UTF-8, no BOM.** Xcode accepts UTF-8 `.strings` and converts to binary plist
at build time. Call this out explicitly — a UTF-16 or BOM'd file from a Windows editor is
the classic first-PR failure, and the symptom (silently falling back to English on
device) is baffling to a contributor.

`.stringsdict` plural categories differ: English needs `one` / `other`; **French needs
`one` / `many` / `other`, and French treats `0` as singular** (`0 minute`, not
`0 minutes`). The template must ship with the French categories pre-stubbed so the
translator does not have to know this.

### 4.3 Validation — yes, add a script

Add `scripts/i18n-lint.sh`, consistent with the existing `scripts/` convention (and
with `CLAUDE.md`'s instruction to prefer `scripts/` entry points). It should:

1. **Extract** keys from source and diff against `en.lproj`. Fail on a
   `HALocalizedString` call whose key is absent from `en.lproj` (would render as the raw
   key), and warn on an `en.lproj` key no longer referenced (dead string).
   Prefer a self-contained extractor (a ~30-line `grep`/`awk` or Python pass over
   `HALocalizedString(@"…"`) over `genstrings -s HALocalizedString`: `genstrings` is
   deprecated in favour of `xcstringstool` and the repo must build on both Xcode 26 and
   27. *Assumption: `genstrings` still ships in Xcode 26/27 — do not depend on it either
   way.*
2. **Key-set parity.** Every non-`en` `.strings` must have exactly `en`'s key set. Report
   missing and extra keys separately; missing is a warning in Phase 3 (partial
   translations are fine and fall back to English), extra is an error (a typo'd key is
   dead weight that masks a missing one).
3. **Format-specifier parity — the one check that prevents crashes.** For each key,
   extract the multiset of specifiers (`%@`, `%ld`, `%1$@`, `%.1f`, …) from `en` and from
   each translation and require they match. A French string with `%@` where English has
   `%ld` is a hard crash, not a cosmetic bug. Also **fail any string with 2+ specifiers
   that does not use positional form** (§1.4 rule 3).
4. **Parse check.** `plutil -lint` every `.strings` and `.stringsdict`, catching unescaped
   quotes and missing semicolons, which are otherwise silent.
5. **Encoding check.** Reject UTF-16 and BOMs.
6. **Pseudo-localisation generation** — `scripts/i18n-lint.sh --pseudo` writes
   `HADashboard/en-XA.lproj/Localizable.strings` with every value accented and padded
   ~40% (`[Ṡéţţîñĝš ———]`). Git-ignored; used for the manual length sweep (§5.3).

Wire into CI as a step in `build-and-test` (`.github/workflows/build.yml`). It needs no
Xcode and runs in seconds, so it can gate every PR. Keep it out of
`verify-ios9-slices` and `archive-release`, which are the expensive jobs.

### 4.4 Review guidance for the maintainer

- A translation-only PR should touch **nothing** outside `HADashboard/<lang>.lproj/` and
  `project.yml`'s `CFBundleLocalizations`. Anything else warrants a closer look.
- Do not accept machine translation for the long `helpText:` paragraphs in
  `HASettingsViewController` — the camera/RTSP security wording (e.g.
  `HASettingsViewController.m:705,780`) carries real security meaning, and a mistranslation
  there misleads a user about whether their camera stream is encrypted. Ask psolyca to
  flag anything they are unsure of rather than guess.
- **Hard rule:** no PR may change the `en_US_POSIX` formatters listed in §3.2.

---

## 5. Testing

### 5.1 Do not depend on the snapshot suite

`HADashboardTests/` holds 190 committed reference images across ~40 test files, and the
suite is currently environment-broken. **No phase gate in this plan depends on it.**
Re-recording 190 references for a translation change would also be the wrong move: it
would bake English into the references and make the suite hostile to future languages.

Recommended posture: snapshot tests keep running under the **default `en` locale only**,
and should be *unaffected* by Phase 1 (which is behaviour-preserving) and by Phase 2
*provided the localizer is empty in tests*. Make that explicit — `HAStateLocalizer` must
start empty and must not perform I/O or network access when instantiated under XCTest,
or every state-rendering snapshot shifts the moment Phase 2 lands. If any reference does
change in Phase 2 it is a real behavioural diff (e.g. `not_home` → `Not Home`) and should
be reviewed image-by-image, not bulk re-recorded.

### 5.2 Unit tests — where the real coverage goes

There are already 21 non-snapshot XCTest files (`HAOAuthClientTests.m`,
`HAEntityNameResolverTests.m`, `HARegistryLoadingTests.m`, …) on a 15.0 arm64 simulator
target, so this needs no new infrastructure.

**`HAStringsTests.m`**

- Every key referenced by `HALocalizedString` in source resolves in `en` to something
  other than the key itself. (Mirrors the lint, but fails the build if someone bypasses
  CI.)
- Key-set parity between `en` and every shipped language.
- Format-specifier multiset parity per key.
- Fallback: an unknown key returns the key in `DEBUG`; a key present in `en` but missing
  from `fr` returns the `en` value when the `fr` bundle is selected.
- **Pseudo-localisation:** with `en-XA` selected, assert every key returns a value
  distinct from, and longer than, the `en` value. This catches a string that was
  hardcoded and therefore *cannot* be localised — the main thing Phase 1 can get wrong
  while still looking finished.

**`HAStateLocalizerTests.m`** — the important one. Drive it from a **committed JSON
fixture** captured from a real instance (the live probes behind §2.1–§2.4 are exactly
this data; commit a trimmed `en` + `fr` pair under
`HADashboardTests/Fixtures/ha-translations-{en,fr}.json`). Assert:

- Lookup order, with a case for each rung: a `translation_key` hit beats a `device_class`
  hit beats `_` beats raw.
- `person` / `not_home` → `Away` (en) and `Absent` (fr). The regression test for issue #19.
- `binary_sensor` + `device_class: door` + `on` → `Open` / `Ouvert`.
- `unavailable` and `unknown` resolve from app strings and **never** reach the HA chain.
- Empty localizer ⇒ byte-identical output to the pre-Phase-2 implementation. Pin this by
  table-driven comparison against the 37 values currently at
  `HAEntityDisplayHelper.m:100-153`, captured before deletion.
- Language normalisation: `fr-CA` → `fr`, `en-GB` → `en`, `zz` → `en`.
- The 512 KB payload cap discards and degrades gracefully rather than throwing.

**`HADateFormattingTests.m`**

- For `en-US`, `en-GB`, `fr-FR`: `dateFormatFromTemplate:` output has the expected field
  order, and `jmm` yields a 12h pattern for `en-US` and 24h for `fr-FR`.
- Every `en_US_POSIX` parser in §3.2 still round-trips its wire format. **Add this test
  in Phase 1**, before any formatting work — it is the guardrail for §4.4's hard rule.

### 5.3 Pseudo-localisation sweep

Before accepting any translation, run the app under `en-XA` on the narrowest layout
(iPhone SE-class width, single-column flow layout) and the iPad 2 columnar layout, and
screenshot the settings screen, entity detail sheets, and a tile/badge-heavy view. This
finds truncation without needing a translator. Concrete known-fragile spots in §6.3.

### 5.4 Device checks

**iPad 2, iOS 9.3.5, armv7 — the gate that matters.** The universal build is the one
path where resource packaging could silently differ.

```bash
scripts/build.sh device
unzip -l <ipa> | grep -E 'lproj'                       # en.lproj + fr.lproj present
plutil -p "<app>/fr.lproj/Localizable.strings" | head   # compiled, UTF-8 intact
scripts/deploy.sh ipad2
```

Then on-device: French accented characters render in the app font and in the MDI-mixed
labels; the settings screen does not clip; memory after a dashboard load is within the
usual envelope (enable Performance Monitor from Settings and compare `/tmp/perf.log`
against a 1.2.7 baseline — the `HAStateLocalizer` dictionary is the only new resident
allocation and should be well under 1 MB).

Capture evidence with the existing file-trigger mechanism (`touch /tmp/take_screenshot`
over SSH, per `CLAUDE.md`), which works on the jailbroken iPad 2/3/4.

**Add one CI assertion** in `archive-release`, alongside the existing
`test -f "$APP/PrivacyInfo.xcprivacy"` at `.github/workflows/build.yml:472`:

```bash
test -f "$APP/en.lproj/Localizable.strings"
plutil -lint "$APP/en.lproj/Localizable.strings"
```

This is cheap and catches the exact failure mode — a bundle-template change dropping
`.lproj` on the universal path — that would otherwise ship a fully-English IPA with no
error.

**Modern device:** iPad Mini 5 (iOS 26) and iPhone 16 for the in-app override picker,
live language switching without relaunch, and the iPhone flow-layout truncation pass.
Also exercise the `frontend/subscribe_user_data` push by changing the HA profile language
in the HA UI and confirming the app follows without a reconnect.

---

## 6. Phasing and effort

Estimates are maintainer-days of focused work, excluding review and contributor
turnaround.

### 6.1 Phase 1 — English extraction, zero visible change (3–5 days)

Ship `en.lproj` with every app-owned string, and **no second language**. The app looks
and behaves identically; the language picker is hidden while only one language exists.

1. Packaging gate (§1.5) — one key, four targets, verify the device IPA. **Do this
   first**; everything else is wasted if it fails. (0.5 day)
2. `HAStrings` + macros + `HADateFormattingTests` parser guardrail. (0.5 day)
3. `scripts/i18n-lint.sh` + CI wiring. Write the lint **before** bulk extraction so it
   guides the work rather than auditing it. (1 day)
4. Extract ~200 keys, file by file, largest first:
   `HASettingsViewController` → `HAConnectionFormView` → camera/lock/timer/calendar/
   scene/alarm cells → `HADashboardViewController` → the rest. Add `comment:` with
   length constraints as you go. (1.5–2.5 days)
5. `HAStringsTests` incl. pseudo-localisation. (0.5 day)

**Skip `HAEntityDetailSection.m` in Phase 1.** 11 of its 12 labels come free from HA in
Phase 2 (§2.4); translating them now is ~40 keys of throwaway work.

Exit criteria: lint and tests green; `scripts/build.sh device` IPA contains
`en.lproj`; iPad 2 screenshot identical to 1.2.7; **zero** user-visible diff.

### 6.2 Phase 2 — HA state translations (3–4 days)

Independently valuable: **this is the phase that fixes issue #19's `not_home`, in English
as well as French.** It could ship in 1.3.0 even if no translation lands.

1. `HAStateLocalizer`: fetch `entity_component`, flat-map store, `HACacheManager`
   persistence with the 2-language / 512 KB caps, synchronous cold-start load. (1 day)
2. Language resolution (§2.6) incl. `frontend/subscribe_user_data` and the `xx-YY` → `xx`
   normalisation; verify the unavailable-language behaviour flagged as an assumption in
   §2.6. (0.5 day)
3. Rewire `HAEntityDisplayHelper`: delete the 37-entry tables
   (`HAEntityDisplayHelper.m:100-153`) and `HAPersonEntityCell.m:68-71`; add the
   `state.default.*` app keys; keep `humanReadableState:` as last resort. (0.5 day)
4. Attribute labels: route `HAEntityDetailSection` through
   `…state_attributes.{attr}.name`, keep `attr.aux_heat.name` app-owned. (1 day)
5. `HAStateLocalizerTests` with committed en/fr fixtures. (0.5 day)
6. Decide on `entity`-category (Phase 2b) — **recommend deferring**, see §2.7.

Exit criteria: `person` shows `Away` on an English HA and `Absent` on a French HA, with
no app translation involved; empty-localizer output byte-identical to Phase 1; iPad 2
memory within baseline.

### 6.3 Phase 3 — French (1–2 days maintainer + contributor time)

1. Publish `docs/CONTRIBUTING-translations.md` and open a tracking issue for psolyca,
   linking the exact file to copy.
2. Pre-stub `fr.lproj` with French plural categories (§4.2) so the contributor is not
   fighting `.stringsdict` syntax.
3. Review per §4.4; reject machine translation on the security help text.
4. Unhide the language picker (`System` / `English` / `Français`).
5. Device pass: iPad 2 + iPhone truncation sweep.

### 6.4 Risks

**String length on small layouts — the highest-probability regression.** French runs
15–25% longer than English. The iPhone path is a single-column flow layout with
full-width cards and absorbs this reasonably; the dangerous spots are fixed-width and
estimated-width elements:

- `HADashboard/Views/Cells/HABadgeRowCell.m:52-57` computes pill widths from an
  *estimate*. Longer text will overflow or clip, and it is also the Mushroom chips
  renderer (§7), so a French Mushroom user hits it first.
- `HAColumnarLayout` fixed cell heights on iPad: a two-line French label where English
  took one line will clip rather than reflow.
- Button titles inside pills: `Lock`/`Unlock` → `Verrouiller`/`Déverrouiller` is more
  than double. `HALockEntityCell` and `HATimerEntityCell` need the pseudo-localisation
  sweep specifically.
- `Target: —` (`HAEntityDetailSection.m:710,3457`) becomes `Température cible` from HA in
  Phase 2 — a 3× growth in a label that currently fits a short English word.

Mitigation: pseudo-localisation before accepting the translation (§5.3), plus length
constraints in every `comment:` so the translator knows where to abbreviate.

**RTL is out of scope.** No Arabic/Hebrew. The codebase uses explicit `leading`/`trailing`
anchors in some places and `left`/`right` in others; auditing that is a separate piece of
work and should not block 1.3.0. State this in the contributing doc so nobody submits
an RTL language and is disappointed.

**App Store metadata localisation is separate and manual.** Adding `fr` to
`CFBundleLocalizations` makes the App Store show the app as French-localised. If the
listing itself is not translated in App Store Connect, a French user sees a "French app"
with an English description. Either add French metadata (name, subtitle, description,
keywords, screenshots) in App Store Connect for the 1.3.0 submission, or hold the
`CFBundleLocalizations` addition until it is ready. **This is a release-gate decision, not
a code one** — record it in `docs/releases/v1.3.0.md`.

**Secondary risks.** Toolchain drift on `.strings` compilation between Xcode 26 and 27
(mitigated by the CI assertion in §5.4). HA changing the `entity_component` key templates
(unlikely — core mirrors them in `helpers/translation.py:462-493`, so they are effectively
public API — and the app degrades to raw states, not a crash). A contributor's editor
writing UTF-16 (caught by lint). The shared-mutable-`NSNumberFormatter` race in §3.1
becoming a real crash once a locale setter is added to it.

---

## 7. Mushroom / Bubble — triage reference

Not the subject of this plan. Captured so the maintainer can triage psolyca's promised
list quickly, and because §2.5 suggests the two reports are connected.

**There is no custom-card registry.** `custom:` is never stripped or normalised; the full
string is carried in `item.cardType` (`HADashboard/Models/HALovelaceParser.m:1117`) and
matched only by a few ad-hoc `containsString:` tests.

| Family | Recognised | Mapping |
|---|---|---|
| `custom:mushroom-chips-card` | yes, deliberately | `HALovelaceParser.m:1371` (exact match, chip entity extraction) and `:879-883` (→ composite `"badges"` + `chipStyle`) → `HAEntityCellFactory.m:257-259` → `HABadgeRowCell` pill row |
| `custom:mushroom-vacuum-card` | yes, **accidentally** | `HALovelaceParser.m:1221` `containsString:@"vacuum"`; no factory entry, so it falls through to domain routing → `HAVacuumEntityCell`. `HAVacuumEntityCell.m:159-167` happens to mirror Mushroom's `commands` semantics |
| every other `custom:mushroom-*` | **no** | generic path below |
| **all** `custom:bubble-*` | **no** | `bubble` does not appear anywhere in `HADashboard/`, `HADashboardTests/`, or `docs/` |

**Generic path for an unrecognised `custom:` card — two outcomes, and the first is a
silent drop:**

```objc
// HADashboard/Models/HALovelaceParser.m:691-692
NSArray<NSDictionary *> *extracted = [self extractEntitiesFromCard:card];
if (extracted.count == 0) return;
```

No entity ⇒ no item, no placeholder, **no log**. Entity extraction for an unknown
`custom:` card only inspects `entities[]` (`:1320-1333`) and a scalar `entity`
(`:1336-1343`). If an entity *is* found, the card is coerced to that entity's native
domain cell (`HAEntityCellFactory.m:307-308`, falling back to `kBaseCellId` at `:248-249`).
Never an error cell.

Read for any card type, custom included (`HALovelaceParser.m:1140-1285`): `icon`,
`color`, `show_name`, `show_state`, `show_icon`, `hide_state`, `vertical`,
`state_content`, `attribute`, `state_color`, `unit`, `features`, `tap_action` /
`hold_action` / `double_tap_action`, `aspect_ratio`, `grid_options` / `layout_options`
spans. **Absent from the codebase entirely** (silently ignored): `primary_info`,
`icon_type`, `content_info`, `icon_color`, `multiline_secondary`, `fill_container`,
`collapsible`, `sub_button`, `card_layout`, `button_type`, `card_mod`, and Mushroom's
`primary` / `secondary` templates. `secondary_info` is read **only** inside the
`entities` card branch (`:995-996`).

Expect these five from psolyca's list:

1. **Mushroom chips degrade to a plain pill row.** Chip types with no `entity` —
   `template`, `action`, `conditional`, `menu`, `weather`, `back`, `spacer` — are skipped
   at `HALovelaceParser.m:1375-1383`. A chips card built *entirely* of template/action
   chips extracts zero entities and the whole card vanishes at `:692`.
2. **`custom:mushroom-template-card` is effectively unsupported.** Jinja in
   `primary`/`secondary`/`icon` is never read; template rendering exists only for markdown
   cards (`HALovelaceParser.m:304-312`, `HAMarkdownCardCell.m:129`). With an `entity` it
   renders as that entity's native cell with the wrong labels — **this is the most likely
   source of psolyca's raw `not_home`** (§2.5). With no `entity` it disappears.
3. **Bubble pop-ups and layout types vanish.** `card_type: pop-up` / `separator` /
   `empty-column` / `horizontal-buttons-stack` carry no `entity` ⇒ dropped at `:692`.
   `card_type: button` survives but loses `button_type`, so a `slider` button becomes
   whatever the domain cell is.
4. **Bubble sub-buttons are invisible and unsubscribed.** `sub_button` appears nowhere and
   `extractEntitiesFromCard` does not walk it (`:1320-1410`), so those entities are not
   even in the live-state subscription set.
5. **No diagnostics on the drop path.** A Mushroom/Bubble-heavy dashboard renders as
   silently *shorter* views with no explanation — the hardest possible thing for a user to
   report from an iPad 2 in French.

**Cheapest high-value fix, independent of this plan:** add an `HALog` warning and a
visible "unsupported card: `<type>`" placeholder on the `HALovelaceParser.m:692` drop
path. It converts every future report of this class from "some cards are missing" into a
precise list, which is worth more than any individual card implementation.

Also noted while surveying: the chips snapshot fixtures set
`@{@"chipStyle": @"badge"}` (`HADashboardTests/HASnapshotTestHelpers.m:1789,1803`), and
`[@"badge" boolValue]` is `NO`, whereas the parser sets `@YES`
(`HALovelaceParser.m:883`). The `hideNames` chip path at `HABadgeRowCell.m:194` is
therefore **not** covered by those tests. Small, separate bug.
