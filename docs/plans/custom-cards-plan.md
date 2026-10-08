# Native HACS Custom Cards — Mushroom & Bubble Card

**Status:** PARKED (2026-10-08). The maintainer reviewed this plan and paused it to focus
on the 1.3.0 soak; it may be picked up later. No decision has been formally approved yet.
Recommended positions as walked through with the maintainer:
- **D1 scope:** start with Phase 0–1 (registry + Mushroom base, chips, vacuum, light,
  title, ~19–25 d); decide Phase 2–3 when psolyca's card list arrives; Bubble only on demand.
- **D2 template card:** legacy Mushroom anatomy natively; v5 `mushroom-template-card` on
  the existing `HATileEntityCell`.
- **D3 templates:** WebSocket `render_template` (supports `variables`) when templates are
  in scope; block entity-dependent templates in Phase 1 rather than render them wrong.
- **D4 Bubble pop-ups:** option (b) — bottom sheet + centred, header-as-card, hash
  toggle/back semantics, slide-to-close, background blur.
- **D5 appearance:** match anatomy/options/colours/behaviour, keep the app's radius and
  spacing, except Mushroom's 36pt round icon and Bubble's pill, which stay exact.
- **D6 parity:** in-app demo-mode dashboards for development, demo-server views later.
Since this plan was written, 1.3.0 shipped the unsupported-card placeholder and a
`custom:xyz` label on generic fallbacks (so Phase 0 is partly done), and the chips
fixture bug in §2.5 was fixed on `fix/snapshot-test-runner`.
Read-only investigation; no code changed by this document.
**Date:** 2026-10-08. **Repo state:** branch `main`, clean.
**Scope:** native Objective-C implementations of popular HACS custom cards matching the
original JavaScript cards' **appearance and options**, starting with Mushroom
(`piitaya/lovelace-mushroom`) and Bubble Card (`Clooos/Bubble-Card`).
**Trigger:** GitHub issue #19 (psolyca).

Every claim below is either cited to upstream source, cited to `file:line` in this repo,
or explicitly marked **[ASSUMPTION]**. `docs/*` is gitignored
(`.gitignore:74`), so this file is untracked by default.

---

## 0. Executive summary

1. **Issue #19 contains no card list.** It is titled "Translation". psolyca's only
   card remark is: *"I have tested with `Mushroom`, `Bubble` and `normal` cards for some
   entities. `Mushroom` and `Bubble` are not really working but sould be ok. The entity
   `Person` show a `not_home` so the RAW value and my HA card `Absent`. I will try other
   cards to make a list."* (verified via `gh issue view 19 --comments`, comment dated
   2026-10-08T09:01:39Z). **The promised list has not been posted.** No other issue in
   `ha-dashboard/ios-app` mentions mushroom, bubble or custom cards
   (verified: `gh issue list --state all`).

2. **The maintainer's own Home Assistant barely uses these cards.** A live read-only
   census of all 17 storage-mode dashboards (§3) finds **88 `custom:*` card nodes out of
   509 total (17.3%)**, but of those: Mushroom = **6 cards** (4 × `mushroom-vacuum-card`,
   2 × `mushroom-chips-card` containing 8 `entity` chips) and Bubble Card = **zero**.
   The dominant custom card is `advanced-camera-card` (68 nodes incl. its menu elements).
   **Real local usage cannot drive the Mushroom/Bubble priority order** — it must come
   from upstream popularity plus the bug report.

3. **The root cause of "not really working" is already diagnosed and partly fixed.**
   There is no custom-card registry: an unrecognised `custom:*` card either (a) silently
   vanishes when it has no top-level `entity`/`entities`
   (`HADashboard/Models/HALovelaceParser.m:691-692`), or (b) is coerced into the plain
   domain cell with every Mushroom/Bubble option discarded
   (`HADashboard/Views/HAEntityCellFactory.m:252-309`). Two in-flight branches already
   attack this: `feature/unsupported-card-placeholder` (adds `HAUnsupportedCardCell` +
   a "Show Unsupported Cards" toggle) and `fix/custom-card-fallback-label` (the v1.3.0
   integration line, which also carries `HAStateLocalizer`). **Phase 0 of this plan is to
   land those, not to re-do them.**

4. **psolyca's `not_home` vs `Absent` complaint is an i18n bug, not a Mushroom bug.**
   `HAStateLocalizer` (HA-provided localized state names) exists only on
   `feature/i18n` / `fix/custom-card-fallback-label` / `docs/release-v1.3.0`, **not on
   `main`** (verified per-branch with `git ls-tree`). On `main` the only state-humanising
   path is `+[HAEntityDisplayHelper humanReadableState:]`
   (`HADashboard/Views/HAEntityDisplayHelper.m:159`), which is English-only. Any native
   Mushroom cell must route state text through `HAEntityDisplayHelper` /
   `HAStateLocalizer` rather than formatting states itself.

5. **The codebase is unusually well-prepared.** Actions (`tap_action`, `hold_action`,
   `double_tap_action`, `icon_tap_action`) are already parsed for *every* card type
   including `custom:*` (`HALovelaceParser.m:1281-1288`) and dispatched end-to-end
   (`HADashboardViewController.m:2102-2124` → `HAActionDispatcher`). `grid_options`
   spans are type-agnostic (`HALovelaceParser.m:620-665`). MDI covers 7448 glyphs
   (`Vendor/MDI/mdi-codepoints.tsv`). `HATheme colorFromString:` already parses
   Mushroom's named colours and hex (`HADashboard/Theme/HATheme.h:65`). A bottom-sheet
   presentation controller already exists for Bubble pop-ups
   (`HADashboard/Views/HABottomSheetPresentationController.h`). **The missing piece is
   a Mushroom-style base cell and a card-type registry — not infrastructure.**

6. **One upstream finding changes the design.** As of Mushroom v5, `mushroom-template-card`
   was **rewritten on top of HA's own Tile primitives** (`ha-tile-icon` / `ha-tile-info` /
   `hui-card-features`) and no longer looks Mushroom-shaped; the Mushroom-looking template
   card is now a separate type, `custom:mushroom-legacy-template-card`. Matching
   "Mushroom appearance" for templates means implementing the **legacy** card's anatomy and
   mapping the v5 card onto the existing `HATileEntityCell` instead. This is **Open
   decision D2**.

### Top-priority card list

Ranked by (live usage) → (upstream prevalence) → (cost to implement). Usage counts are
from the live census in §3; "upstream" is a qualitative judgement **[ASSUMPTION]** based on
each card being the documented default entry point of its project.

| # | Card | Live usage | Why | Est. |
|---|---|---|---|---|
| 1 | Mushroom shared base (`mushroom-entity-card`) | 0 direct, but every mushroom card inherits it | Unlocks 15 card types at once; the single highest-leverage item | 5–7 d |
| 2 | `mushroom-chips-card` + `entity` chip | **2 cards / 8 chips** | Already half-mapped (degrades to a pill row); highest real usage of any Mushroom card | 3–4 d |
| 3 | `mushroom-vacuum-card` | **4** | Highest-count Mushroom card locally; already accidentally works (`containsString:@"vacuum"`), needs `commands` + layout + icon animation | 1–2 d |
| 4 | `mushroom-light-card` | 0 | The most-used Mushroom card in the wild **[ASSUMPTION]**; brightness/colour-temp/colour controls | 4–5 d |
| 5 | `mushroom-template-card` (legacy anatomy) | 0 | The second-most-used Mushroom card **[ASSUMPTION]**, and the predicted source of psolyca's wrong labels | 4–6 d (incl. template plumbing) |
| 6 | `mushroom-title-card` | 0 | Trivial (two labels), appears on nearly every Mushroom dashboard **[ASSUMPTION]** | 0.5 d |
| 7 | `mushroom-climate-card` | 0 | Common; needs hvac-mode buttons + target-temp steppers | 3–4 d |
| 8 | `mushroom-cover-card` / `-fan-card` | 0 | Share the control-cycling pattern with light/climate | 2–3 d each |
| 9 | Bubble shared pill + `button` (switch / slider / state / name) | **0** | One 50pt pill view covers **9 of Bubble's 11 card types** and the pop-up header (§1.B.0); nothing Bubble works without it | 4–6 d |
| 10 | Bubble `separator` | 0 | Trivial (40px row, icon, 6px line) and ubiquitous in Bubble dashboards | 0.5 d |
| 11 | Bubble `sub_button` | 0 | Currently invisible *and* unsubscribed — a correctness bug, not just cosmetic | 2–3 d |
| 12 | Bubble `pop-up` | 0 | Highest-value Bubble feature, highest risk; needs hash routing + sheet | 5–8 d |

### Decisions needed (detail in §7)

D1 scope commitment · D2 which template card · D3 template transport & budget ·
D4 pop-up fidelity · D5 option-fidelity bar · D6 parity-harness hosting.

---

## 1. Upstream inventory

### 1.A Mushroom

**Provenance:** `piitaya/lovelace-mushroom`, default branch `main`, commit **`ceefff0`**,
`package.json:3` → version **5.2.3**; 5196 stars / 445 forks, last pushed 2026-10-05
(`gh api repos/piitaya/lovelace-mushroom`). Apache-2.0.

#### 1.A.1 Card registry

`src/mushroom.ts:3-23` registers 19 cards + 1 badge, named `mushroom-<x>-card` via
`PREFIX_NAME = "mushroom"` (`src/const.ts:1`):

`entity`, `light`, `fan`, `cover`, `climate`, `alarm-control-panel`, `lock`,
`media-player`, `person`, `template`, `legacy-template`, `title`, `chips`, `select`,
`number`, `humidifier`, `vacuum`, `update`, `empty`, plus `mushroom-template-badge`.

#### 1.A.2 Shared enums and the appearance algorithm — the heart of the port

`src/utils/info.ts:7-17`:
```
INFOS      = ["name", "state", "last-changed", "last-updated", "none"]
ICON_TYPES = ["icon", "entity-picture", "none"]
```
`src/utils/layout.ts:3`: `LAYOUTS = ["default", "horizontal", "vertical"]`.

`src/utils/appearance.ts:10-51` — **this exact algorithm must be reproduced**:
```
layout         = config.layout         ?? (config.vertical ? "vertical" : "default")
fill_container = config.fill_container ?? false
primary_info   = config.primary_info   || (config.hide_name  ? "none" : "name")
secondary_info = config.secondary_info || (config.hide_state ? "none" : "state")
icon_type      = config.icon_type      || (config.hide_icon  ? "none"
                                        : (config.use_entity_picture || config.use_media_artwork)
                                            ? "entity-picture" : "icon")
```
Note the legacy keys `vertical`, `hide_name`, `hide_state`, `hide_icon`,
`use_entity_picture`, `use_media_artwork` are honoured at runtime but are **absent from**
`appearanceSharedConfigStruct` (`src/shared/config/appearance-config.ts:7-13`) — they work
in YAML, not in the GUI editor. A native port should accept both forms.

Shared structs: `src/shared/config/entity-config.ts:24-28` (`entity`, `name`, `icon`);
`src/shared/config/actions-config.ts:6-10` (the three actions);
`src/shared/config/lovelace-card-config.ts:3-11` (`grid_options`, `layout_options`,
`visibility`, …).

`name` may also be an object/array under the HA ≥ 2026.4 entity-name system
(`entity-config.ts:13-22`, `src/utils/compute-entity-name.ts:9-16`):
`{type: "entity"|"device"|"area"|"floor"}` or `{type:"text", text:"…"}`. **The parser
already notes this shape** (`HALovelaceParser.m:1540` comment "string or name-config
object/array; resolved downstream").

#### 1.A.3 Visual anatomy

DOM (`src/cards/entity-card/entity-card.ts:84-106`):
```
ha-card[.fill-container]
└ mushroom-card                    (src/shared/card.ts)
  ├ mushroom-state-item            (src/shared/state-item.ts)
  │ ├ mushroom-shape-icon  slot=icon   (src/shared/shape-icon.ts)  ← or shape-avatar
  │ ├ mushroom-badge-icon  slot=badge  (src/shared/badge-icon.ts)  ← conditional
  │ └ mushroom-state-info  slot=info   (primary / secondary lines)
  └ div.actions                    ← controls row, conditional
```
`state-item.ts:26-41`: the icon div is omitted when `icon_type == "none"`; the info div is
omitted when both infos are `"none"`. `card.ts:13-23` sets `.horizontal`, `.no-info`,
`.no-content` classes.

Layout variants:
| value | effect |
|---|---|
| `default` | card container column (`card.ts:38-46`), state-item row (`state-item.ts:52-61`) → icon left, text right, controls **below** |
| `horizontal` | `card.ts:47-60` container row; state-item and actions side by side, each `flex:1`; actions lose padding and shrink to `--control-height: var(--icon-size)` (36px). Cards pass `.fill = (layout !== "horizontal")` to their button groups (e.g. `lock-card.ts:117`, `climate-card.ts:301,310`, `vacuum-card.ts:132`) |
| `vertical` | `state-item.ts:80-85` column + `text-align:center` → icon above centred text |

`fill_container`: adds `.fill-container` whose only rule is `height:100%`
(`src/utils/card-styles.ts:13-15`).

**Metrics — all from `src/utils/theme.ts:3-92`** (defaults; `--mush-*` are user overrides):
```
--spacing 10px                       (state-item padding AND gap)
--icon-size 36px   --icon-border-radius 50%   --icon-symbol-size 0.667em (24px)
--badge-size 16px  --badge-border-radius 50%  --badge-icon-size 0.75em (12px)
--control-height 42px  --control-border-radius 12px  --control-spacing 12px
--control-button-ratio 1  --control-icon-size 0.5em (21px)
primary   14px / 500 / 20px / 0.1px   secondary 12px / 400 / 16px / 0.4px
          both default to var(--primary-text-color)
title padding 24px 12px 8px; title 24px/32px; subtitle 16px/24px, secondary colour
chips: --chip-spacing 8px  --chip-height 36px  --chip-border-radius 19px
       --chip-padding 0 0.25em  --chip-font-size 0.3em (10.8px) bold
       --chip-icon-size 0.5em (18px)  --chip-avatar-border-radius 50%
```
Badge position: `state-item.ts:65-73` absolute `top:-3px; right:-3px`.
Actions row: `card-styles.ts:19-36` `padding: var(--control-spacing); padding-top: 0`.

**Icon tint formula** — `src/shared/shape-icon.ts:28-52`:
```
--icon-color  default var(--primary-text-color)
--shape-color default rgba(var(--rgb-primary-text-color), 0.05)   ← inactive
disabled  → --icon-color-disabled rgb(var(--rgb-disabled)),
             --shape-color-disabled rgba(var(--rgb-disabled), 0.2)
active    → --icon-color: rgb(C);  --shape-color: rgba(C, 0.2)
```
**Alpha constants: `0.05` inactive/neutral, `0.2` active and all `-disabled`, `0.25` only
for the light card's own colour** (`light-card.ts:253`). Transition 280ms ease-out.

`computeRgbColor` (`src/utils/colors.ts:33-52`): `"primary"`/`"accent"` → the matching
`--rgb-*`; one of the 26 `COLORS` names (`colors.ts:4-31`) → `var(--rgb-<name>)`;
`#hex` → `"r, g, b"`; otherwise verbatim. Palette RGB defaults at `colors.ts:65-93`
(e.g. red `244,67,54`, blue `33,150,243`, orange `255,152,0`, green `76,175,80`,
teal `0,150,136`, purple `146,107,199`, indigo `63,81,181`, disabled `189,189,189`).

Per-domain state colours (`theme.ts:128-223`): `state-entity`=blue, `state-light`=orange,
`state-fan`=green, `state-vacuum`=teal, `state-media-player`=indigo, `state-lock`=blue,
`state-number`=blue, `state-humidifier`=purple; plus state maps for alarm
(disarmed=info/armed=success/triggered=danger), person (home=success/not-home=danger/
zone=info/unknown=grey), update (on=orange/off=green/installing=blue), lock
(locked=green/unlocked=red/pending=orange), cover (open=blue/closed=disabled), and climate
(auto=green, cool=blue, dry=orange, fan-only=teal, heat=deep-orange, heat-cool=green,
idle/off=disabled).

`isActive`/`isAvailable` (`src/ha/data/entity.ts:12-45`): off-states are
`unavailable|unknown|off`; `button`/`input_button`/`scene` active unless unavailable;
`cover`/`valve` inactive when `closed|closing`; `device_tracker`/`person` inactive when
`not_home`; `media_player` inactive when `standby`; `vacuum` inactive when
`idle|docked|paused`.

Unavailable/not-found: `renderBadge` (`src/utils/base-card.ts:276-287`) shows an
`mdi:help` badge in warning colour; `renderNotFound` (`:232-261`) shows a disabled help
icon + `mdi:exclamation-thick` danger badge, primary = entity_id.

Controls (`src/shared/`): `button.ts` (height `--control-height`, bg
`rgba(var(--rgb-primary-text-color),0.05)`), `button-group.ts` (row, right-justified,
`.fill` → `flex-grow:1`), `slider.ts` (height `--control-height`, active track
`scale3d(var(--value),1,1)`, 180ms, `--slider-threshold` default 10),
`input-number.ts` (−/value/+, width = height × ratio × 3, debounce default 2000ms).

Animations (`src/utils/entity-styles.ts`): `pulse` on alarm
(arming/triggered/pending/unavailable) and update (installing); `spin` on fan;
`cleaning`/`returning` on vacuum.

#### 1.A.4 Per-card options

Shorthand: **SE** = `entity`, `name`, `icon`; **SA** = `layout`(default),
`fill_container`(false), `primary_info`(name), `secondary_info`(state), `icon_type`(icon);
**ACT** = the three action keys.

| Card | Options beyond SE+SA+ACT, with defaults | tap / hold |
|---|---|---|
| `entity` | `icon_color` (unset → `--rgb-state-entity` blue) | more-info / more-info |
| `light` | `icon_color`; `show_brightness_control` F; `show_color_temp_control` F; `show_color_control` F; `collapsible_controls` F; `use_light_color` F | **toggle** / more-info |
| `fan` | `icon_animation` F; `show_percentage_control` F; `show_oscillate_control` F; `show_direction_control` F; `collapsible_controls` F. **No `icon_color`** | **toggle** / more-info |
| `cover` | `show_buttons_control` F; `show_position_control` F; `show_tilt_position_control` F. No `icon_color`, no `collapsible_controls` | **toggle** / more-info |
| `climate` | `hvac_modes` `[]`; `show_temperature_control` F; `collapsible_controls` F. No `icon_color` | **toggle** / more-info |
| `alarm-control-panel` | `states` (struct is `optional(array())`, **unvalidated**; stub config uses `["armed_home","armed_away"]`, `alarm-control-panel-card.ts:90-95`) | more-info / more-info |
| `lock` | none. **Controls row always rendered** (`lock-card.ts:67-69,113-120`) | more-info / more-info |
| `media-player` | `use_media_info` F; `show_volume_level` F; `volume_controls` `[]` ⊂ {volume_mute, volume_set, volume_buttons}; `media_controls` `[]` ⊂ {on_off, shuffle, previous, play_pause_stop, next, repeat}; `collapsible_controls` F | more-info / more-info |
| `person` | none. Icon has **no colour override** (neutral); only the zone badge is coloured (`person-card.ts:115-140`) | more-info / more-info |
| `select` | `icon_color`. Controls always rendered | more-info / more-info |
| `number` | `icon_color`; `display_mode` `"slider"`\|`"buttons"` (unset ⇒ slider). Controls always rendered | more-info / more-info |
| `humidifier` | `show_target_humidity_control`; `collapsible_controls` F | **toggle** / more-info (docs say more-info; **source wins**, `humidifier-card.ts:74-84`) |
| `vacuum` | `icon_animation` F; `commands` `[]` ⊂ {on_off, start_pause, stop, locate, clean_spot, return_home} (struct `optional(array(string()))`, unvalidated) | more-info / more-info |
| `update` | `show_buttons_control` F; `collapsible_controls` F | more-info / more-info |
| `title` | `title`, `subtitle` (both templatable); `alignment` start\|center\|end\|justify; `title_tap_action` **none**; `subtitle_tap_action` **none**; `entity_id` (read at `title-card.ts:253` but **absent from the struct**). No SE/SA/ACT | — |
| `legacy-template` | `entity`; templatable `icon`, `icon_color`, `primary`, `secondary`, `badge_icon`, `badge_color`, `picture`; `multiline_secondary` F; `layout`, `fill_container`; `entity_id` | **toggle** / more-info (docs say none/none; **source wins**, `legacy-template-card.ts:156-165`) |
| `template` (v5) | `entity`, `area`; templatable `primary`, `secondary`, `color`, `icon`, `picture`, `badge_icon`, `badge_text`, `badge_color`; `vertical` F; `multiline_secondary` F; `features`; `features_position` `bottom`; `icon_tap_action`/`icon_hold_action`/`icon_double_tap_action`; migrates `icon_color`→`color`, `layout`→`vertical` | none, or more-info when `entity` set (`template-card.ts:244-257`) |
| `empty` | none | — |

Control-stack behaviour worth copying exactly:
- **light** (`light-card.ts:99-120`): ordered brightness → colour-temp → colour; each needs
  the flag **and** the capability (`light-card/utils.ts:39-53`). One is active; the others
  become toggle buttons (`mdi:brightness-4`, `mdi:thermometer`, `mdi:palette`).
  `collapsible_controls` hides the whole row while inactive (`:208-210`). Brightness
  replaces the state text (`:196-204`). `use_light_color` runs
  `improveColorContrast` (HSV: if `s<0.4` then `s<0.1 ? v=225 : s=0.4`,
  `light-card/utils.ts:27-37`).
- **cover** (`cover-card.ts:101-114,277-286`): a **single** "next control" button cycles,
  unlike light/climate/media-player which render one button per inactive control.
- **fan**: all three controls can show simultaneously; no active switching.
- **climate** (`climate-card.ts:246-273`): badge shows `hvac_action` — cooling
  `mdi:snowflake`, drying `mdi:water-percent`, heating `mdi:fire`, idle
  `mdi:clock-outline`, off `mdi:power`; skipped when the action is missing or `off`.
- State-text suffixes joined with `" ⸱ "`: cover position (`cover-card.ts:210-218`),
  climate current temp + humidity (`:170-184`), fan percentage (`fan-card.ts:146-154`),
  media volume (`media-player-card.ts:185-192`), humidifier current humidity
  (`humidifier-card.ts:107-113`).

#### 1.A.5 Chips

`src/cards/chips-card/`: options `chips` and `alignment` (`end`|`center`|`justify`, unset
⇒ start). The `ha-card` is fully stripped (no background/shadow/radius/border); the
container is a wrapping flex row with `gap: var(--chip-spacing)` (8px).

Chip shell (`src/shared/chip.ts`): `height`/`min-width` `--chip-height` (36px), radius
19px, `--chip-background` = card background, optional leading circular `<img class=avatar>`,
`.content` with `--chip-padding`, slotted icon at `--chip-icon-size` in `--icon-color`,
slotted `<span>` at `--chip-font-size` **bold** in `--text-color`, `0.15em` gap between
slotted children; `avatarOnly` drops the text block.

`CHIP_LIST` (`src/utils/lovelace/chip/types.ts:127-139`) — **11 types**, note `quickbar`
in addition to the ten in the brief:

| chip | options (defaults) | notes |
|---|---|---|
| `action` | `icon` (`mdi:flash`), `icon_color`, 3 actions (all unset) | `icon_color` applied **unconditionally** |
| `entity` | `entity`, `name`, `content_info` (→ `"state"` at render, `entity-chip.ts:92`), `icon`, `icon_color`, `use_entity_picture` F, 3 actions | `icon_color` applied **only when active**. **This is the only chip type in live use (8 instances)** |
| `light` | `entity`, `name`, `content_info`, `icon`, `use_light_color` F | defaults `tap: toggle`, `hold: more-info` (`light-chip.ts:52-62`). **No `icon_color`** |
| `alarm-control-panel` | `entity`, `name`, `content_info`, `icon`, `icon_color` (**declared but ignored** — overwritten at `alarm-control-panel-chip.ts:82`) | pulse animation |
| `back` | `icon` (`mdi:arrow-left`) | `window.history.back()` |
| `menu` | `icon` (`mdi:menu`) | fires `hass-toggle-menu` |
| `quickbar` | `icon` (`mdi:magnify`), `mode` `entity`\|`device`\|`command` (default **entity**) | dispatches a synthetic keydown |
| `spacer` | none | renders nothing; `flex-grow: 1` |
| `conditional` | `chip` (**required**), `conditions[]` | extends HA's `hui-conditional-base` |
| `template` | `entity`, templatable `content`, `icon`, `icon_color`, `picture`, `entity_id`, 3 actions | defaults `tap: toggle`, `hold: more-info` (`template-chip.ts:84-92`) |
| `weather` | `entity`, `show_temperature` F, `show_conditions` F, 3 actions | labels joined `" ⸱ "` |

**Chips have no `layout`/`fill_container`/`primary_info`/`secondary_info`/`icon_type`** —
their only info selector is `content_info`, from the same `INFOS` enum, defaulting to
`"state"`.

#### 1.A.6 Templating (Mushroom)

Template detection: v5 template card uses `/{%|{{/`
(`src/ha/common/string/has-template.ts:1-4`); legacy card, template chip and title card use
the looser `value?.includes("{")`.

| element | templatable keys | source |
|---|---|---|
| `template` (v5) | `icon, color, primary, secondary, picture, badge_icon, badge_color, badge_text` | `template-card.ts:58-67` |
| `legacy-template` | `icon, icon_color, badge_color, badge_icon, primary, secondary, picture` | `legacy-template-card.ts:51-59` |
| `template` chip | `content, icon, icon_color, picture` | `template-chip.ts:44` |
| `title` | `title, subtitle` | `title-card.ts:40` |

`multiline_secondary` is **not** templatable; it only sets `white-space: pre-wrap`
(`state-info.ts:63-65`).

Mechanism (`template-card.ts:164-242`, identical in all four): one
`subscribeRenderTemplate` (HA's `render_template` WebSocket command,
`src/ha/data/ws-templates.ts`) per templatable key, payload
`{template, entity_ids: config.entity_id, variables: {config, user, entity, area}, strict: true}`.
`entity_id` is therefore the explicit backend hint. On subscription failure the literal
string is displayed. Results are cached across reconnects in a module-level
`CacheManager<TemplateResults>(1000)` keyed by an `object-hash` of the config.

#### 1.A.7 Upstream bugs not to copy

- `vacuum-card.ts:177-182` defines `.cleaning ha-state-icon` **twice**; the second wins, so
  the `returning` animation never applies. Implement the *intended* behaviour.
- `humidifier-card.ts:107` guards current humidity with `!== null`, so it also fires for
  `undefined`.
- Every card template emits a stray `;` after `renderStateInfo(...)` (invisible).
- Dead code: `alarm-control-panel-card/const.ts:16-23`, `utils.ts:16-18,32-37`.
- Doc/source default mismatches (source wins): humidifier tap, legacy-template tap/hold,
  light `icon_color` (docs "blue", CSS default orange).

### 1.B Bubble Card

**Provenance:** `Clooos/Bubble-Card`, default branch `main`, commit **`061ed83`**,
`src/var/version.js:1` → **v3.4.1**; 4633 stars / 191 forks, last pushed 2026-09-25
(`gh api repos/Clooos/Bubble-Card`). MIT.

#### 1.B.0 Architecture — why this ports well

Bubble Card is **not** a Lit component tree. It is a single `HTMLElement` subclass
(`src/bubble-card.js:616`) that imperatively builds DOM once and then only mutates
properties, with per-card-type CSS produced by literal string substitution of `card-type`
in one shared stylesheet (`src/components/base-card/create.js:86`). Every handler is
idempotent — `if (context.cardType !== '<type>') createStructure(context)` followed by
`change*()` mutators (`src/cards/button/index.js:11-27`). **That is exactly the shape of a
UIKit cell: build subviews once in `setupSubviews`, mutate in
`configureWithEntity:configItem:`.**

A single `card_type` dispatch table (`src/bubble-card.js:79-91`) covers:
`pop-up`, `button`, `sub-buttons`, `separator`, `cover`, `empty-column`,
`horizontal-buttons-stack`, `calendar`, `media-player`, `select`, `climate`.

**Nine of the eleven card types are the same pill** (§1.B.1) with a different trailing
control cluster. One native `HABubbleCardCell` with pluggable trailing controls therefore
covers `button`, `cover`, `climate`, `select`, `media-player`, `calendar`,
`sub-buttons`, and the pop-up header — a materially smaller job than eleven cells.

Config validation worth mirroring in the parser (`src/bubble-card.js:491-542`):
`card_type` required; `button`/`cover`/`climate`/`select`/`media-player` require `entity`
unless `button_type: name`; `calendar` requires `entities`;
`horizontal-buttons-stack` requires an `N_link` for every `N_icon` and rejects duplicate
links; `grid_options.rows` is copied onto `config.rows` (`:503-505`); unquoted-YAML
template objects in `name`/`icon`/`N_name`/`N_icon`/sub-button `name`/`icon` are
**rejected** (`hasUnquotedTemplate`, `:65-77`).

Sizing: `getCardSize()` = 1 for most, **2 for `cover`**, 0/−100000 for `pop-up`
(`:544-558`). `getGridOptions()` = `columns: config.columns * 3` (default **12**),
`rows: config.rows ?? 'auto'`; HBS forces `rows: 1.3`; separator forces `0.8`
(`:560-573`). Renders are coalesced: a card that rendered < 50 ms ago defers
(`hassRenderWindowMs = 50`, `:102`).

#### 1.B.1 The shared pill

DOM (`src/components/base-card/create.js:31-109`):
```
div.bubble-<type>-container.bubble-container        ← the pill, height 50px
└ div.bubble-<type>.bubble-wrapper                  ← absolute, flex, space-between
  ├ div.bubble-background                           ← absolute, full size, tinted
  ├ div.bubble-content-container                    (display: contents)
  │ ├ div.bubble-main-icon-container                ← the icon circle
  │ │ ├ ha-icon.bubble-main-icon
  │ │ └ div.bubble-entity-picture                   ← background-image, absolute
  │ └ div.bubble-name-container
  │   ├ div.bubble-name
  │   └ div.bubble-state
  ├ div.bubble-buttons-container                    ← card-specific controls
  └ [div.bubble-sub-button-container] / [...-bottom-container]
└ [div.bubble-range-slider]                         ← inserted BEFORE the wrapper
```
`defaultOptions` (`src/components/base-card/index.js:5-23`):
`withMainContainer`/`withBaseElements`/`withFeedback`/`withImage`/`withCustomStyle`/
`withState`/`withBackground` = true; `withSlider`/`holdToSlide`/`readOnlySlider`/
`withSubButtons` = false; `iconActions` = true; `buttonActions` = false.

**Exact geometry** (`src/components/base-card/styles.css`):

| Element | Rule | Lines |
|---|---|---|
| `.bubble-container` | **`height: 50px`**, `width:100%`, `position:relative`, `overflow: clip` | 81-101 |
| radius | `--bubble-<type>-border-radius ?? --bubble-border-radius ?? calc(var(--row-height,56px)/2)` → **28px** | 86 |
| `.bubble-wrapper` | absolute, 100%×100%, flex, space-between, centred; `transition: all 1.5s` | 117-128 |
| `.bubble-background` | absolute, 100%×100%, `transition: background-color 1.5s` | 196-204 |
| `.bubble-icon-container` | **`min-width/height: 38px; margin: 6px`**; radius default **50%** (a circle); bg `--bubble-icon-background-color ?? --bubble-secondary-background-color ?? card background` | 206-218 |
| icon opacity | `.is-off` → **0.6**, `.is-on` → 1; `transition: opacity .3s, color .3s` | 220-231 |
| `.bubble-name-container` | column, centred, `flex-grow:1`, `line-height:18px`, `margin-inline: 4px 16px`, `pointer-events:none`, overflow hidden | 248-259 |
| `.bubble-name` | **13px / weight 600** | 261-264 |
| `.bubble-state` | **12px / normal / opacity 0.7** | 266-270 |
| state with no name | `.state-without-name` → **opacity 1, 14px** | 288-291 |
| name with no icon | `margin-inline-start: 16px` | 293-295 |
| `.bubble-buttons-container` | flex, `margin-inline-end: 8px`, `gap: 4px` | 153-158 |
| unavailable | `.is-unavailable` → **opacity 0.5**, buttons hidden, `cursor: not-allowed` | 272-282 |
| `large` layout | height `calc(row-height × row-size + row-gap × (row-size − 1))`; icon container **42×42**, `--mdc-icon-size: 24px`, `margin-inline-start: 8px` | 305-315 |
| bottom-pinned buttons | `.bubble-wrapper.fixed-top` → `align-items: baseline`; content `min-height: 54px`; buttons `position:absolute; bottom:8px; padding: 0 8px` | 130-194 |
| scrolling text | `.scrolling-container` with an 8px edge `mask-image`; inner span animates `bubble-scroll` `translateX(0 → −50%)`; separator span `opacity .3` | 31-78 |

**Shared state/name/icon logic** (`src/components/base-card/changes.js`):
- `changeState` (`:57-172`) builds the line from `resolveStateContent(config,'card',entity)`
  and joins parts with **`' • '`** (`:126`); toggles `.hidden`, `.name-without-icon`,
  `.state-without-name`, `.display-state`; adds `.is-on`/`.is-off` **unless the unit
  contains `°`** (`:144`). Relative times re-render on a self-scheduling interval; running
  `timer` entities tick.
- `changeIcon` (`:174-250`): icon colour is `inherit` when off, when `button_type: name`,
  or for a pop-up with no `button_type` (`:190-192`). When on:
  `var(--bubble-icon-color, <getIconColor()>)`, except `climate`/`humidifier`/
  `water_heater` which use `getClimateColor`. `entity_picture` wins over `icon` unless
  `force_icon` or an explicit `icon` is set.
- `changeName` (`:252-270`): `button_type: name` renders `config.name` as a template;
  otherwise `getName()` — live template result → templated `config.name`
  (**an empty template result shows empty, never the friendly name**) → literal
  `config.name` → `friendly_name` → `""` (`src/tools/utils.js:365-379`).

**The colour model is computed, not static** — this is the single biggest fidelity trap:
- `--bubble-default-color` = **70% of `rgb(0,145,255)` mixed with 30% of
  `--primary-background-color`** (`src/tools/style.js:117-137`), recomputed on every theme
  change (`src/bubble-card.js:374-382`).
- `getIconColor` (`src/tools/icon.js:362-402`): `var(--bubble-icon-color)` for temperature
  units or any state containing a digit; accent/default for non-lights or
  `use_accent_color`; for lights, the `rgb_color` brightness-adjusted (−0.2 on light
  themes), collapsing to `rgb(225,225,210)` when within 40/255 of white
  (`isColorCloseToWhite`, `src/tools/style.js:41-53`).
- `getStateSurfaceColor` (`src/tools/utils.js:304-360`): darkens ×0.84 (light text) or
  lightens ×1.16, then a **second ×0.92/×1.08 step only if it would otherwise blend into
  the surface behind it**.
- Text flips to `rgba(0,0,0,0.65)` above luminance **0.67**
  (`BRIGHT_BACKGROUND_LUMINANCE`, `src/components/sub-button/utils.js:140`).

#### 1.B.2 `card_type: button`

| Option | Default | Source |
|---|---|---|
| `entity` | required unless `button_type: name` | `bubble-card.js:528-531` |
| `button_type` | **`switch`** if `entity` set, else **`name`**; `custom` removed with a console error | `button/helpers.js:3-16` |
| `name`, `icon` | friendly_name / registry → attribute → domain icon | `utils.js:365`, `icon.js:307-338` |
| `force_icon`, `use_accent_color` | `false`, `false` | `icon.js:407,363` |
| `state_content` | `null`; for `button_type: state` the HA domain default table | `state-content.js:14-23,112-115` |
| `show_name`, `show_icon`, `scrolling_effect` | `true`, `true`, `true` | `base-card/changes.js:64-66` |
| legacy `show_state`/`show_attribute`/`attribute`/`show_last_changed`/`show_last_updated` | mapped into `state_content`; the first two default `true` only for `button_type: state` | `state-content.js:85-107` |
| `card_layout` | **`large` in sections views, `normal` in masonry**; auto-upgraded to `large` when bottom sub-buttons exist | `utils.js:1026-1090` |
| `rows`, `columns` | 1 (0.8 separator), 4 (×3 → 12 grid columns) | `utils.js:1117-1138`, `bubble-card.js:560-573` |
| `main_buttons_position` / `_alignment` / `_full_width` | `default` / `end` / `true` when position is `bottom` | `utils.js:972-975` |
| `sub_button`, `styles` | — | §1.B.7, §1.B.8 |

**Default actions, icon vs card** (`src/cards/button/create.js:12-54`) — note these are two
separate action sets: taps on the icon circle, and taps on the card background
(`button_action.*`):

| `button_type` | icon tap / dbl / hold | card tap / dbl / hold |
|---|---|---|
| `switch` (default) | more-info / none / none | **toggle** / none / more-info |
| `slider` | more-info / none / none | more-info if sensor else **toggle** / none / none |
| `state` | more-info / none / none | more-info / none / more-info |
| `name` | none / none / none | none / none / none |

The base icon default when `iconActions: true` is `{tap: more-info, double_tap: none,
hold: none}` (`base-card/create.js:17-21`). For `button_type: slider` without
`read_only_slider`, any configured `button_action.hold_action` is **forced to `none`** so
the hold gesture belongs to the slider (`create.js:56-63`). `tap_to_slide` disables
`withFeedback` and `buttonActions` entirely (`:72-78`).

**Background tint** (`src/cards/button/changes.js:29-72`) — `--bubble-button-background-color`
plus `.bubble-background` opacity:

| Condition | Colour | Opacity |
|---|---|---|
| `switch` + on + `isStateRequiringAttention` | `var(--red-color, var(--error-color))` | 1 |
| `switch` + on + light colour available + not `use_accent_color` | `getStateSurfaceColor(…)` | **0.7** |
| `switch` + on otherwise | accent / `--bubble-default-color` | 1 |
| anything else (`state`, `name`, off) | `rgba(0,0,0,0)` | **0.5** |

**The slider is a transform, not a width.** `.bubble-range-fill` is a full-size block
parked off-canvas (`left:-100%`) and slid in with `translateX(pct%)` / `translateY(±pct%)`
depending on `slider_fill_orientation` (`src/components/slider/helpers.js:82-105`,
`styles.css:1-11`). Icon and text sit **on top** because the fill lives inside
`.bubble-range-slider` at `z-index:0` while the wrapper is a later sibling. With
hold-to-slide, during a drag everything except the slider fades to `opacity:0` over 0.3 s
(`slider/styles.css:159-166`). Fill colour: light-brightness sliders without
`use_accent_color` take the light colour at `opacity .7`, everything else the accent at
`opacity 1` (`slider/changes.js:243-277`). Value readout `.bubble-range-value` is
absolutely positioned, `inset-inline-end: 14px`, position `left`/`right`/`center`,
defaulting to `right` in LTR (`helpers.js:70-80`). Appear animation
`scale(0.96) → scale(1)` over 0.2 s.

**Slider gesture constants** (`src/components/slider/create.js:289-295,808-810`):
long-press **200 ms**, immediate-drag threshold **6 px**, scroll threshold **10 px**,
primary-axis intent **4 px**, cancel grace **150 ms**. Drag starts early if the primary-axis
delta ≥ 2 px while the secondary ≤ 4 px (iOS); it aborts to "scroll intent" if the secondary
> 10 px and dominates by > 4 px (`:860-887`). `pointerdown` bails inside a
`.bubble-sub-button[no-slide]` or a `.bubble-action` with a real hold action (`:841-846`).
A drag swallows the trailing click (`slider/drag-click.js`).

**Slider ranges** (`src/components/slider/helpers.js:131-301`): min/max from
`config.min_value`/`max_value` → media `min_volume`/`max_volume` → climate
`min_temp`/`max_temp` → `attributes.min`/`max` → 0/100; step from `config.step` →
`attributes.step` / `percentage_step` / `target_temp_step` (0.5 °C, 1 °F) / 0.01
(media) / 1. Per-domain percent mapping: light brightness `100×b/255`; hue `hue/360×100`;
**`white_temp` inverted** `((maxK − K)/range)×100`; cover `current_position` or
`current_tilt_position`; fan `percentage` (0 when off); climate `temperature` clamped.
Read-only when `read_only_slider`, any `sensor.*`, or a domain outside
`[light, media_player, cover, input_number, number, fan, climate]` (`:176-182`);
auto-trips for `sensor.*` with `%` units (`button/helpers.js:18-24`). External state syncs
jump instantly when the delta > 5 %, animate otherwise, and are skipped while dragging
(`slider/changes.js:286-354`).

#### 1.B.3 `card_type: pop-up`

| Option | Default | Verified at |
|---|---|---|
| `hash` `'#name'` | **required** | registry keyed by hash, `pop-up/helpers.js:2833` |
| `popup_style` | **`bubble`** (\|`classic`\|`home-assistant`) | `pop-up/style.js:11-15` |
| `popup_mode` | **`default`** (\|`fit-content`\|`centered`\|`adaptive-dialog`) | `helpers.js:71-74,527` |
| `with_bottom_offset`, `full_width_on_mobile` | false, false | `helpers.js:547,552` |
| `performance_mode` | `default` | `helpers.js:77-78` |
| `auto_close` | unset (ms) | `helpers.js:1327-1331` |
| `close_on_click` | false | `helpers.js:2335-2375` |
| `close_by_clicking_outside` | **true** | `helpers.js:1288` |
| `slide_to_close` | **true** (\|`header`\|false) | `slide-to-close.js` |
| `width_desktop` | **540px** (bubble) / `var(--ha-dialog-width-md, 580px)` (HA style) | `style.js:43-63` |
| `margin` | **7px**, applied as `--custom-margin: -<margin>` | `create.js:101` |
| `margin_top_mobile` / `_desktop` | 0px / 0px | `create.js:99-100` |
| `bg_color` | theme background | `create.js:345` |
| `bg_opacity` | **88** (bubble) / 100 (HA) | `style.js:44,55` |
| `bg_blur` | **10** (bubble) / 0 (HA) | `style.js:45,56` |
| `bg_lightness` (internal) | **1.02** / 1 | `style.js:46,57` |
| `shadow_opacity` | **0** (bubble) / 100 (HA) | `style.js:49,62` |
| `hide_backdrop`, `background_update` | false, false | `create.js:103,157` |
| `trigger` / `trigger_entity` + `trigger_state` | — | `pop-up/changes.js:156-232` |
| `trigger_close` | **true** with `trigger`, **false** with the legacy pair | `changes.js:206` vs `:226` |
| `open_action` / `close_action` | — | `helpers.js:2828-2830` |
| `show_header`, `show_close_button` | true, true | `changes.js:11,13` |
| `show_previous_button` | false | `changes.js:12` |
| `buttons_position` | `right`; forced `left` by the `home-assistant` style | `changes.js:16` |
| `cards` | standalone format, v3.2.0+ | `pop-up/cards/create.js`, `migration.js` |
| + every button option, for the header | | `create.js:182-223` |

**Attachment.** Standalone (`cards:` present): the shell is created at shadow-root level,
the `ha-card` is **detached** (`create.js:489-491`), and DOM attachment is **deferred to
first open** outside the editor (`:503-515`). Legacy: the pop-up hijacks its enclosing
`vertical-stack` root (`prepareStructure`, `:388-435`), which is removed from the DOM
100 ms after creation unless open.

**Hash routing** (`helpers.js:3033-3107`): one global listener for `location-changed`,
`bubble-card-location-changed`, `popstate`, `hashchange`. On any of them: close every
active pop-up whose hash ≠ `location.hash`, sweep abandoned shells, then look up
`popupRegistry.get(location.hash)` — a `Map<hash, WeakRef<context>>` (`:2833`) — and open
it. **Navigating to the hash that is already open closes it** (`:3073-3081`). The previous
hash is remembered for the back button (`:3066`). `addHash` does `history.pushState` +
dispatches `location-changed` (`:1367-1392`); `removeHash` does a `replaceState` to the
fragment-less URL, debounced 50 ms (`:1333-1365`).

**Dismissal** is close button, Escape when `config.hash === location.hash`
(`create.js:89-93`), slide-to-close, click-outside, `auto_close`, `close_on_click`, hash
removal, or `trigger_close`. `clickOutside` (`:1281-1325`) is guarded by
`close_by_clicking_outside`, the open having settled, a 150 ms fallback delay, a
recently-closed-dialog window, and **the press must not have started inside the pop-up**
(drag-out does not close). `animationDuration = 300 ms` (`:42`), quick-open 140 ms (`:61`).

**Shell geometry** (`src/cards/pop-up/styles.css`): `position: fixed`, column flex,
`width:100%`, `z-index: 5 !important`, `transition: transform 0.3s ease`; top radii
`--bubble-pop-up-border-radius ?? --bubble-border-radius ?? **42px**`;
`inset-inline-start: 7px` (`:128-152`). Mobile placement `top: calc(56px + safe-area-top +
offset); bottom: 0` (`:186-192`). Closed = `translate3d(0,100%,0)` + `pointer-events:none`
(`:194-198`); open = `translate3d(0,0,0)` (`:595-598`); shadow when open
`0 0 50px rgba(0,0,0,var(--custom-shadow-opacity))` (`:591-593`). Surface
`.bubble-pop-up-background` is absolute with the same top radii (`:568-585`); blur is a
`::before` with `backdrop-filter` and a 0.4 s opacity transition (`:154-179`).
Desktop ≥ 600px: `min/max-width: var(--desktop-width, 540px)`, centred (`:629-642`);
≥ 768px re-centred by the sidebar inset (`:646-657`). `centered` mode: `margin:auto;
inset:0; width: calc(100vw − 32px); max-height: calc(100vh − 112px − 2×offset)`; closed
`scale(0.85) opacity 0`, open `scale(1)`, closing `scale(0.9)`; transition
`transform .35s cubic-bezier(.16,1,.3,1), opacity .25s` (`:211-249`). `fit-content`:
`top:auto; bottom:0` (`:200-209`).

**Header is itself a full button card** (`create.js:248-304`, `styles.css:703-825`):
```
div#header-container.bubble-header-container   flex, min-height 50px, padding 18px 18px 22px, z-index 3
├ div.bubble-header                            flex-grow 1, margin-inline-end 14px
│ └ (handleButton(context, header) builds a complete pill here)
└ div.bubble-header-actions                    flex, gap 14px
  ├ div.bubble-previous-button                 50×50, hidden unless .show-previous-button
  └ div.bubble-close-button                    50×50
```
Action buttons are **50×50**, fully round, background
`--bubble-pop-up-main-background-color ?? --bubble-secondary-background-color`, 0.3 s
colour transitions (`:751-768`); their icons are inline MDI SVG path data embedded at
`create.js:16-17`. The classic/HA style forces the header's `button_type` to `switch` and
all three actions to `none` (`style.js:32-37`).

**Content container** (`styles.css:1-99`): column flex, `overflow:auto`,
`padding: 18px`, `gap: var(--bubble-pop-up-gap, 14px)` (also exported as `--grid-gap`,
`--vertical-stack-card-gap`, …), radius 42px, **`margin-top: -50px`** (the
`--bubble-pop-up-header-overlap`, reduced to 20px by the classic/HA header, `:557`), and
`overscroll-behavior: contain`. Top/bottom scroll fade masks appear only when
`.is-scrollable`.

**Backdrop** (`src/cards/pop-up/backdrop.css`): a singleton `.bubble-backdrop`,
`position:fixed; inset:0;` **`z-index: 4`**, opacity 0 → 1 over 0.3 s, with an optional
`backdrop-filter`.

#### 1.B.4 `card_type: cover`

Base pill + `iconActions`/`buttonActions`/`withSubButtons` all true
(`cover/create.js:8-14`); `getCardSize()` = 2. Three buttons
`.bubble-{open,stop,close}` with default icons `mdi:arrow-up`, `mdi:stop`,
`mdi:arrow-down`, plus a tilt row (`mdi:arrow-top-right`, `mdi:arrow-bottom-left`), hidden
by default (`create.js:19-102`).

Geometry (`cover/styles.css:1-31,93-97`): button **36×36**, radius 28px,
`transition: all .3s ease`; icons `--mdc-icon-size: 20px` (24px in `large`); main row
`gap: 8px`, tilt row `gap: 4px`; `.disabled → opacity 0.3; pointer-events:none`.

Options: `open_service` (`cover.open_cover`), `stop_service`, `close_service`,
`open_tilt_service`, `close_tilt_service` — each called with only `entity_id` plus
`forwardHaptic("selection")`. `icon_open`/`icon_close` choose the main icon;
`icon_up`/`icon_down` the buttons, defaulting to
`mdi:arrow-expand-horizontal`/`mdi:arrow-collapse-horizontal` for
`device_class: curtain` (`changes.js:185-195`). All accept Jinja. `tilt_buttons` ∈
`top` (default) \| `bottom` \| `left` \| `right` \| `hidden` (`changes.js:256-370`).

Enablement (`changes.js:11-254`) uses the `supported_features` bitmask (OPEN 1, CLOSE 2,
SET_POSITION 4, STOP 8, OPEN_TILT 16, CLOSE_TILT 32, STOP_TILT 64, SET_TILT_POSITION 128);
`assumed_state` always allows; `current_position` 100/0 or state `open`/`closed` blocks;
`opening`/`closing` blocks. The main icon uses the *open* glyph whenever the cover is not
fully closed (`:62-66`).

#### 1.B.5 `card_type: separator`

Hand-rolled, not the base pill (`withMainContainer`/`withBaseElements`/`iconActions`/
`buttonActions` all false, `withSubButtons` true — `separator/create.js:5-31`):
```
div.bubble-container.bubble-separator
├ ha-icon.bubble-icon        inline-flex; margin-inline: 8px 22px  (0px 8px / width 0 when absent)
├ h4.bubble-name            font-size 16px; margin-inline: 0 30px; nowrap; ellipsis; :empty → display none
├ div.bubble-line           flex-grow 1; height 6px; radius 6px; opacity 0.6
└ [sub-button container]
```
Container `height: 40px`, `background: none`, `overflow: visible`. `large` →
`calc(row-height(44) × row-size(0.8) + row-gap × (row-size − 1))`. With bottom sub-buttons
the container becomes `align-items: flex-start` and the line gains `margin-top: 15px`.
Options: `name`, `icon` (both Jinja), `card_layout`, `rows` (default **0.8**),
`sub_button`, `styles`. **No `entity`, no actions**, and `changeName` is called with
`textScrolling = false` (`index.js:15`).

#### 1.B.6 `card_type: horizontal-buttons-stack`

Does **not** use the base pill. Options: `N_link` (required per button), `N_name`,
`N_icon` (Jinja), `N_entity` (a light whose colour tints the button), `N_pir_sensor`,
`auto_order` (false), `margin`, `width_desktop` (**500px** → `--desktop-width`),
`rise_animation` (true), `highlight_current_view` (false), `hide_gradient` (false),
`is_sidebar_hidden`.

Geometry (`horizontal-buttons-stack/styles.css`): **`position: fixed; bottom: 16px;
height: 51px; z-index: 6`**, width `calc(100% − inset − 8px)`; below 870px
`calc(100% − 16px)` at `inset-inline-start: 8px`. A `::before` gradient
(`top:-32px; height:100px`) appears only with `.has-gradient`. The scroll strip has a 28px
edge `mask-image` varying with `.is-scrolled`/`.is-maxed-scroll`. Each button is
`position:absolute; height: 50px; padding: 0 16px`, radius **32px**, and is **positioned
by JS**: measured, width-cached (`button-width-storage.js`), then
`transform: translateX(±position)` with `BUTTON_MARGIN = 12px`
(`changes.js:43-67`, `create.js:10`). Light tint (`changes.js:80-98`): `rgb_color` →
`rgba(r,g,b,0.5)` (or `rgba(255,220,200,0.5)` near white) with a transparent border;
`on` without rgb → `rgba(255,255,255,0.5)`; off → transparent with a
`--primary-text-color` border. `rise_animation` is a `from-bottom` overshoot
(100px → −8px → 1px → −2px → 0) disabled after 1500 ms. `highlight_current_view` toggles
`animation: pulse 1.4s infinite alternate` (`brightness .7 → 1.3`) when
`location.pathname === link || location.hash === link` (`highlight.js:14-71`).

Tap (`create.js:38-62`): a non-hash link calls `navigate`; a `#hash` **toggles** —
`addHash` when closed, `removeHash` when open — always with `forwardHaptic("light")`. The
card also forces 80px bottom padding on its HA card wrapper so the last dashboard card is
not covered (`:141-145`). `auto_order` (`changes.js:10-42`) sorts PIR-bearing buttons
first, then `on` first, then by descending `last_updated`, keeping config order on ties.

#### 1.B.7 `media-player`, `climate`, `select`, `calendar`, `empty-column`, `sub-buttons`

**media-player** (`src/cards/media-player/`): base pill plus a
`.bubble-media-info-container` (title 12px/600 + artist, `line-height 14px`) injected into
the content container, a buttons row ordered power → previous → next → volume →
play/pause, a mute button **inside the icon circle**, and a hidden
`.bubble-volume-slider-wrapper` appended to the wrapper. Buttons **36×36** (42 in `large`),
icons 20px, `gap: 8px`; **play/pause is the accented one** (`styles.css:65-77`). The
`.bubble-background` doubles as a blurred cover art layer: `background-size: cover;
filter: blur(50px); opacity: 0.5` with 2 s crossfade layers (`:21-48,229-246`). The volume
overlay is `height: 38px; width: calc(100% − 16px)`, hidden as
`opacity:0 + translateX(14px)` (`:79-155`). Responsive hiding: previous < 250px,
next < 206px, volume < 160px (`:252-268`). Options add `min_volume`/`max_volume`,
`cover_background` (false), and `hide: {play_pause_button, volume_button, previous_button,
next_button, power_button}` all false (`changes.js:610-625`), combined with
`supported_features`. Services: `turn_on`/`turn_off`, `volume_mute`,
`media_previous_track`, `media_next_track`, and `computePlaybackControl(context).service`.

**climate** (`src/cards/climate/`): one card for three domains (`domains.js:10-59`) —
`climate` (`set_temperature`/`temperature`/`min_temp`/`max_temp`/`target_temp_step`/
`hvac_modes`), `water_heater` (same, `operation_list`), `humidifier`
(`set_humidity`/`humidity`/`min_humidity`/`max_humidity`/`target_humidity_step`/
`available_modes`, unit `%`, step 1). Structure: `.bubble-temperature-container` and a
`.bubble-target-temperature-container` holding low + high containers, each
`inline-flex; height: 36px; font-size: 12px` with a `mdi:minus` / display / `mdi:plus`
trio of **34×34** buttons at 16px icons (`styles.css`). Low is tinted
`--state-climate-heat-color`, high `--state-climate-cool-color`; `gap: 10px`. ± adjusts
locally, clamps, and **debounces the service call by 700 ms** (`create.js:128`); at a
limit it fires `forwardHaptic("failure")` plus a 0.4 s `tap-warning` shake
(`styles.css:62-67`). Options add `hide_target_temp_low`/`_high`, `state_color` (false),
`step`, `min_temp`, `max_temp`. The HVAC-modes dropdown is just an auto-added **select
sub-button**.

**select** (`src/cards/select/`): base pill plus a dropdown; `create.js:7-13`
**force-overrides `button_action.tap_action` to `none`** so a single tap always opens the
menu. `select_attribute` is required unless the entity is `input_select.*`/`select.*`
(`bubble-card.js:536-539`); supported attributes are `source_list`, `sound_mode_list`,
`hvac_modes`, `fan_modes`, `swing_modes`, `swing_horizontal_modes`, `preset_modes`,
`effect_list`, `available_modes`, `operation_list`
(`editor/bubble-card-editor.js:352-365`). Menu min-width **200px**, radius 32px, selected
item tinted with the accent. While a menu is open the container is un-clipped and lifted
to `z-index: 3` (`dropdown/create.js:36-51`).

**calendar** (`src/cards/calendar/`): base with `withBaseElements: false`, plus a
`.bubble-calendar-content` scroller; `--bubble-calendar-height = (config.rows ?? 1) × 56`
px (`create.js:17-20`). Day rows `gap: 8px; padding-block: 7px` with a 2px separator inset
62px; `.bubble-day-chip` **42×42** with a 24px/600 day number at `opacity .6` (1 when
`.is-active`) and a 12px month. Events are memoised on a key built from the entity states
and refreshed **at most every 15 minutes** (`index.js:11-24`). Options: `entities[{entity,
color}]` (required), `days` (**7**), `limit`, `show_end` (false), `show_progress` (true),
`show_started_events` (true), `scrolling_effect`, `event_action.*`, and all three actions
defaulting to `none`.

**empty-column**: zero options; one `div` at `display:flex; width:100%; height: 0px`, with
`.has-rows` giving it the computed row height (`changes.js:8-17`).

**sub-buttons card**: `withBaseElements: false`; `sub_button.main` is forcibly emptied each
render (`index.js:11-23`). Adds `hide_main_background` → `.no-background` (transparent,
radius 0), `footer_mode` → `position: fixed; bottom: var(--bubble-footer-bottom, 16px);
z-index: 5`, `footer_full_width`, `footer_width` (**500px**), `footer_bottom_offset`
(**16**), plus undocumented `menu_style`, `labels_below`, `space_between_buttons`,
`hide_button_labels`, `compact_mode` (`create.js:19-59`).

#### 1.B.8 Sub-buttons

Two accepted shapes: a legacy flat array (treated as `main`), or
`{main: [...], bottom: [...], main_layout, bottom_layout}` (`changes.js:16-22`,
`utils.js:539-575`). Entries are buttons or groups
`{group: [...], buttons_layout: 'inline'|'column', justify_content}`. Layouts default to
`inline`; `rows` stacks groups vertically. `justify_content` on bottom groups is
normalised into alignment **lanes** `start|center|fill|end` with flex `order` 1–4
(`create.js:8-13,349-358`).

Per-button options and defaults (`utils.js:22-60`) — note the two that differ from the
card: **`show_name` defaults to `false`**, and **`fill_width` defaults to `true` in the
`bottom` section** (`changes.js:397-399`):
`entity` (parent's), `name` (friendly_name, Jinja), `icon`, `force_icon` F,
`sub_button_type` (`select` when the entity is `input_select.*`/`select.*` or
`select_attribute` is set, else `default`; also `slider`, `dropdown`), `show_name` **F**,
`show_icon` T, `show_background` T, `state_background` T, `light_background` T,
`show_arrow` T, `always_visible` F, `state_content` null, `scrolling_effect`
(own → card's → T), `tap_action` (**more-info** for non-selects, **none** for
selects/sliders), `double_tap_action`/`hold_action` none, `fill_width`, `width` (px in
`main`, % in `bottom`), `custom_height`, `content_layout` (`icon-left`), `visibility`,
`hide_when_parent_unavailable` F, `css_class`, `select_attribute`, `show_button_info` F.

**The pill** (`sub-button/styles.css:179-198`): `flex-direction: row-reverse`
(**which is why the icon sits on the left while being the last DOM child**),
`min-width: 36px; height: var(--bubble-sub-button-height, 36px); font-size: 12px;
padding: 0 8px;` radius `--bubble-sub-button-border-radius ?? --bubble-border-radius ??
18px`, `transition: all .5s ease-in-out`. Container: `justify-content: end;
inset-inline-end: 8px; gap: 8px` (`:1-9`); the bottom container is
`position:absolute; bottom: 0; width: calc(100% − 16px); margin: 0 8px 8px;`
(`bottom: 44px` when main buttons are also at the bottom, `:32-52`). Icon sizing:
**16px with text** (`margin-inline-end: 4px`), **20px without** (`:340-348`). Entity
picture is a 20×20 circle, or absolute `inset:0` when it is the only content.
`content_layout` maps to `column-reverse` / `column` / `row` / `row-reverse`
(`:244-276`). `.sub-buttons-grid` becomes a CSS grid with
`grid-template-rows: repeat(var(--row-size,1), 1fr); grid-auto-flow: column` (`:382-392`).

Background (`utils.js:140-231`): only when `show_background`; on + `state_background` →
`isStateRequiringAttention` gives red, else `getStateSurfaceColor(...)` and
`.background-on`; above luminance **0.67** the button gains `.bright-background` →
text `rgba(0,0,0,0.65)`. Otherwise `.background-off`.

Text line (`utils.js:78-116`): `[name if show_name] + renderStateLine(...)` joined with
**`' · '`** — note this differs from the card's **`' • '`** — then first character
upper-cased. A button with no text, no icon and no dropdown is `.hidden`.

Indexing (`changes.js:131-166,306-345`): a global 1-based index across sections in
declaration order (`main` then `bottom`, groups expanded in place), which is what
`subButtonState[N]` / `subButtonIcon[N]` address in style templates.

#### 1.B.9 Interactions

One global delegated handler on `document.body` for `pointerdown`/`touchstart`
(`src/tools/tap-actions.js:103-104`), matching the nearest `.bubble-action`.
**Constants to match exactly:**

| Constant | Value | Line |
|---|---|---|
| `maxHoldDuration` | **500 ms** | 3 |
| `doubleTapTimeout` | **200 ms** | 4 |
| `movementThreshold` | **5 px** | 5 |
| `holdReleaseDeadZone` | **15 px** (cancels the hold) | 6 |
| `scrollDisableTime` | **300 ms** (actions suppressed after a scroll) | 7 |

Semantics (`:306-600`): hold is **recognised at 500 ms** with a visual indicator
(a `--primary-color` circle, 100px touch / 50px mouse, `opacity .4`, scale 0→1 over
180 ms, `:15-73`) but **dispatched on release**, matching HA. A tap within 200 ms of the
previous one fires `double_tap` when configured; when `double_tap_action !== none` the
single tap is **deferred 200 ms**, otherwise it fires immediately. `pointercancel`,
`touchcancel`, `scroll`, `document.hidden` and `pagehide` all abandon the interaction.
After firing, a capture-phase `click` swallower is installed for 350 ms (iOS double-fire),
except inside a pop-up with `close_on_click` (`:548-568`). Dispatch is a bubbling composed
**`hass-action`** CustomEvent (`:249-279`), i.e. HA's standard action handling — so
`more-info`, `toggle`, `call-service`/`perform-action`, `navigate`, `url`,
`fire-dom-event`, `none`, `confirmation` and `target.entity_id: "entity"` substitution all
work (`:602-650`). `addFeedback` = `preventDefault` on `pointerup` +
`forwardHaptic("selection")`.

#### 1.B.10 Templating — two engines

**(a) HA Jinja, via live `render_template` subscriptions** (`src/tools/render-template.js`).
`isTemplate(v)` = contains `{{` or `{%` (`src/tools/jinja.js:11-13`) — exactly HA's own
test. The subscription key is `template + entity + user`, and **only the variables the
template actually mentions are sent** — `entity`/`config` detected by
`/\b(?:entity|config)\b/`, `user` by `/\buser\b/` (`jinja.js:36-44`). Message:
`{type: 'render_template', template, strict: false, report_errors: <editor only>,
variables?}` (`:157-168`). One live subscription per distinct `(template, entity, user)`
triple, shared across cards, with **≈200 remembered results, a 20 s grace period before
release, a 10 s × failures retry cooldown, a 250 ms editor delay and an 8 ms flush
budget** (`:35-47`). A pending template renders as `''` (`:355-364`).

Fields that accept Jinja (verified call sites): `name` (`utils.js:372`), `icon`
(`icon.js:312`), cover `icon_up`/`icon_down` (`cover/changes.js:191-192`) and
`icon_open`/`icon_close`, HBS `N_name`/`N_icon` (`hbs/create.js:17-18`), sub-button `name`
(`sub-button/utils.js:38`) and `icon`, **any `state_content` item**
(`base-card/state-line.js:116`), `styles` blocks, and `condition: template` inside
`visibility`/`trigger`. **Not** templated: numeric/boolean options, `entity`, `hash`,
`card_type`, `button_type`, action objects.

**(b) Inline JavaScript `${…}`, only in `styles`** (`src/tools/style-processor.js:576-744`).
The whole `styles` string is compiled as a JS template-literal body via
`Function(…args, "return \`" + source + "\`;")` (`:648-666`), with injected arguments
`hass` (a **tracking proxy** so entity reads register render-gate dependencies), `entity`,
`state`, `icon`, `subButtonState`, `subButtonIcon`, `getWeatherIcon`, `card`, `name`,
`checkConditionsMet`, `onTeardown`, `hasChanged`, `__jinja`, `renderTemplate`
(`:650-664,692-715`). Jinja and JS can be **mixed**: the string is split into Jinja and JS
segments, the Jinja parts rendered server-side and spliced in as `__jinja`
(`:617-618`), with the documented constraint that a `${ }` must not straddle a
`{% if %} … {% endif %}` block. **This engine cannot be ported** — see §6 risks.

**Conditions** (`src/tools/validate-condition.js`): the full HA conditional grammar —
`state`, `numeric_state`, `screen`, `user`, `time`, `location`, `template`, `and`/`or`/
`not`, plus domain builder conditions (`sun.is_up`, `light.is_on`, `zone.in_zone`,
`temperature.is_value`) with `target`/`options`/`behavior`/`for`. All client-side except
`template`.

#### 1.B.11 Port notes

1. **Everything is one pill.** Nine of eleven types are the same 50px container with a
   38px icon circle, a two-line name/state column and a trailing control cluster.
2. **Two different separator glyphs**: cards join state parts with `' • '`, sub-buttons
   with `' · '` and sentence-case the result.
3. **The slider is a transform**, not a width — and so are the volume and sub-button
   overlays (`translateX(14px)` + opacity when hidden).
4. **Colour defaults are computed**: `--bubble-default-color` = 0.7 × `rgb(0,145,255)` +
   0.3 × background, recomputed on theme change, then ±0.84/1.16 and a conditional
   ±0.92/1.08 separation step, with text flipping above luminance 0.67.
5. **Gesture constants must match**: actions hold 500 ms / dead zone 15 px / move 5 px /
   double-tap 200 ms / post-scroll 300 ms; slider long-press 200 ms / immediate-drag 6 px /
   scroll-intent 10 px with a 4 px axis bias.
6. The pop-up is the only part with no clean native analogue: a hash-routed,
   deferred-mount, blur-backed bottom sheet whose header is itself a full card.

---

## 2. Current app support

Baseline = `main` (clean). Line numbers are `main`'s; the v1.3.0 integration line
(`fix/custom-card-fallback-label`) shifts them (e.g. the chips match moves from
`:1371` to `:1537`).

### 2.1 There is no custom-card registry

`custom:` is never stripped or normalised. The full type string is stored verbatim in
`item.cardType` (`HADashboard/Models/HALovelaceParser.m:1117`) and matched by a handful of
ad-hoc `isEqualToString:`/`containsString:`/`hasPrefix:` tests. `HAEntityCellFactory`
routes on a flat `cardType` switch (`HADashboard/Views/HAEntityCellFactory.m:252-309`)
that falls through to pure domain routing (`:142-250`, ending `return kBaseCellId;` at
`:249`).

### 2.2 Per-type status

| Config type | Status | Mapping |
|---|---|---|
| `custom:mushroom-chips-card` | **Partial (deliberate)** | `HALovelaceParser.m:1371-1384` extracts `chips[].entity`; `:879-883` sets composite `"badges"` + `customProperties = @{@"chipStyle": @YES}`; `HAEntityCellFactory.m:257-259` → `HABadgeRowCell`. Renders as a pill row with names hidden (`HABadgeRowCell.m:193-194`). **Chips with no `entity` — `template`, `action`, `conditional`, `menu`, `weather`, `back`, `spacer`, `quickbar` — are skipped (`:1375-1383`); a chips card made only of those extracts zero entities and the whole card is dropped at `:692`.** No chip shell, no `content_info`, no `icon_color`, no alignment |
| `custom:mushroom-vacuum-card` | **Partial (accidental)** | `containsString:@"vacuum"` at `:1219-1226` copies `commands`/`icon_animation`/`layout` into `customProperties`; no factory entry, so domain routing gives `HAVacuumEntityCell`, whose `commands` handling at `HAVacuumEntityCell.m:159-167` happens to mirror Mushroom's semantics. Appearance is the app's own, not Mushroom's |
| `custom:mini-graph-card` | **Native** | `containsString:@"mini-graph"` at `:792-849` normalises to composite `"graph"` and reads `show`, `color_thresholds`, `icon`, `line_width`, `lower_bound`, per-entity `show_state`/`show_graph`/`name`/`color` → `HAGraphCardCell`. **This is the model to copy for Mushroom/Bubble** |
| `custom:badge-card` | **Native-ish** | `containsString:@"badge"` (`:861-863`) → composite `"badges"` → `HABadgeRowCell` with names shown |
| `custom:clock-weather-card` | **Native** | `:1233-1240` reads `temperature_sensor`, `humidity_sensor`, `forecast_rows`, `time_format`, `date_pattern`, `locale`; `HAEntityCellFactory.m:279-281` → `HAClockWeatherCell` |
| `custom:advanced-camera-card` and any `custom:*camera*` | **Partial** | `:1179-1215` parses `elements[]` into `overlayElements`; `:1353-1368` extracts `cameras[].camera_entity` → `HACameraEntityCell` |
| **every other `custom:mushroom-*`** | **Generic fallback or silent drop** | §2.3 |
| **all `custom:bubble-card`** | **Generic fallback or silent drop** | the string `bubble` appears **nowhere** in `HADashboard/`, `HADashboardTests/`, `docs/` or `scripts/` |

### 2.3 The default path, and why psolyca sees missing cards

`HALovelaceParser.m:691-692`:
```objc
NSArray<NSDictionary *> *extracted = [self extractEntitiesFromCard:card];
if (extracted.count == 0) return;
```
`+extractEntitiesFromCard:` (`:1299-1407`) inspects only: recursion into
`horizontal-stack`/`vertical-stack`/`grid` `cards[]`, `conditional` → `card`, an
`entities[]` array, a scalar `entity`, plus the two special cases
(`custom:*camera*` `cameras[]`, exact `custom:mushroom-chips-card` `chips[]`). It does
**not** walk `sub_button`, `buttons`, `chips` (other than the exact match), `badges`,
`series`, or a Bubble pop-up's nested `card`.

Two outcomes:
1. **Silent drop** — no item, no placeholder, **no log**. The view simply renders shorter.
   This is what happens to Bubble `pop-up`, `separator`, `empty-column`,
   `horizontal-buttons-stack`, `mushroom-title-card`, a template card with no `entity`,
   and any chips card made only of entity-less chips.
2. **Generic coercion** — a single `entity` is found, the item keeps the raw `custom:…`
   `cardType`, gets `columnSpan = 12` (the `tile`/`button`/`sensor` → 6 default at
   `:666-675` does not match a `custom:` string), and is routed purely by domain. Every
   Mushroom/Bubble option is discarded. **There is never an error cell.** A Bubble
   `button_type: slider` becomes whatever the domain cell is; a Mushroom template card with
   an `entity` renders as that entity's native cell with the wrong labels.

Keys the parser **does** read for any card type including custom
(`:1120-1290`): `icon`, `color`, `show_name`, `show_state`, `show_icon`, `hide_state`,
`show_entity_picture`, `vertical`, `state_content`, `attribute`, `state_color`, `unit`,
`features`, `features_position`, `aspect_ratio`, `dimensions.*`, `icon_height`,
`show_current_as_primary`, `stat_type`, all six action keys (`:1281-1288`), and
`grid_options`/`layout_options` spans (`:620-665`).

Keys **absent from the codebase entirely**: `primary_info`, `icon_type`, `content_info`,
`icon_color`, `multiline_secondary`, `fill_container`, `collapsible_controls`,
`sub_button`, `card_layout`, `button_type`, `card_mod`, `alignment`, `commands` (outside
the vacuum branch), `layout` (outside the vacuum branch), and Mushroom's
`primary`/`secondary` templates. `secondary_info` is read **only** inside the `entities`
card branch (`:995-996`).

Unmatched card types also get `height = 100.0 + headingExtra`
(`HADashboardViewController.m:861-862`).

### 2.4 In-flight work that changes this baseline

| Branch | Effect |
|---|---|
| `feature/unsupported-card-placeholder` | Adds `HADashboard/Views/Cells/HAUnsupportedCardCell.{h,m}`, `HAUnsupportedCardType = @"__unsupported__"` + `HAUnsupportedCardTypeKey`, a `HAShowUnsupportedCardsDefaultsKey` Settings toggle (default **YES** when untouched), a change notification for live rebuild, once-per-load `HALogW` dedup, and `_handleUnsupportedCard:` on the drop path — plus `HADashboardTests/HAUnsupportedCardTests.m` (288 lines). This is exactly the fix i18n-plan §7 recommended |
| `fix/custom-card-fallback-label` | The v1.3.0 integration line: the placeholder work **plus** `HADashboard/Localization/HAStateLocalizer.{h,m}` (194/522 lines) and `HAStrings.{h,m}`, `HAConnectionManager` translation fetch (+111 lines), and `scripts/test-snapshots.sh` reworked to a pinned iOS 18.0 / iPad (10th generation) destination with `ReferenceImages_ios18_64` (871 images across 18 suites) |
| `feature/i18n`, `docs/release-v1.3.0` | also carry `HAStateLocalizer` |

**`HAStateLocalizer` is not on `main`.** Verified per branch:
```
docs/release-v1.3.0: 2   feature/i18n: 2   fix/custom-card-fallback-label: 2   main: 0
```

### 2.5 Pre-existing bugs found while auditing (report, don't silently fix)

1. `HAEntityCellFactory.m:272` tests `[cardType isEqualToString:@"mini-graph-card"]`, but
   the parser rewrites those cards to `"graph"` and non-composite paths keep the full
   `custom:mini-graph-card`. The branch is unreachable for real configs; same at
   `HADashboardViewController.m:826` and `:2241`.
2. `HADashboardTests/HASnapshotTestHelpers.m:1789,1803` set
   `@{@"chipStyle": @"badge"}`; `[@"badge" boolValue]` is `NO`, while the parser sets
   `@YES` (`HALovelaceParser.m:883`). The `hideNames` chip path
   (`HABadgeRowCell.m:194`) and its height branch (`:76`) are therefore **untested** —
   directly relevant to the chips work in Phase 1.
3. `HALogbookCardCell` gets `beginLoading` in `willDisplayCell:` but has no
   `cancelLoading` in `didEndDisplayingCell:` (`HADashboardViewController.m:1918-1957`).
4. CLAUDE.md is stale on two performance facts — see §4.7.
5. `scripts/compare-screenshots.mjs:30-32` defaults `APP_REFS_DIR` to
   `ReferenceImages_64`, the legacy iOS 17.4 set, while the v1.3.0 runner now records into
   `ReferenceImages_ios18_64`.

---

## 3. What the maintainer actually uses

Method: read-only WebSocket census over `lovelace/dashboards/list` + `lovelace/config`
for the default dashboard and all 17 storage-mode dashboards, walking every nested node
and discriminating `custom:bubble-card` by `card_type`. Script:
`<scratchpad>/cc_census.mjs`. Token never printed.

Dashboards scanned: `(default)`, `dashboard-kitchen`, `map`, `dashboard-tubby`,
`dashboard-garden`, `dashboard-office`, `dashboard-temperatures`, `living-room`,
`dashboard-landing`, `dashboard-car`, `dashboard-lights`, `dashboard-ribbit`,
`dashboard-home`, `ic3db-icloud3`, `lovelace`, `dashboard-cameras`,
`markdown-template-demo`.

**Totals: 509 card-ish nodes, of which 88 are `custom:*` (17.3%).**

| Count | Type | Dashboards |
|---|---|---|
| 35 | `custom:advanced-camera-card-menu-state-icon` | kitchen, office, living-room |
| 29 | `custom:advanced-camera-card` | kitchen, garden, office, living-room, cameras |
| **8** | `mushroom-chips-card` → `entity` chips | kitchen, living-room |
| **4** | `custom:mushroom-vacuum-card` | kitchen, landing, ribbit |
| 4 | `custom:clock-weather-card` | kitchen, office, living-room, landing |
| 4 | `custom:advanced-camera-card-menu-icon` | kitchen, living-room |
| 4 | `custom:badge-card` | kitchen, office, living-room, landing |
| 3 | `custom:mini-graph-card` | office, living-room, landing |
| **2** | `custom:mushroom-chips-card` | kitchen, living-room |
| 2 | `custom:icloud3-event-log-card` | ic3db-icloud3 |
| 1 | `custom:button-card` | kitchen |
| **0** | **`custom:bubble-card` (any `card_type`)** | — |

Non-custom context: `vertical-stack` 78, `tile` 69, `grid` 65, `glance` 63,
`entities` 48, `horizontal-stack` 43, `entity` 22, `sections` 13, `thermostat` 8.

**Mushroom options actually in use** (from the census's per-type key counts):

- `custom:mushroom-vacuum-card` (n=4): `icon_animation` 4, `layout` 4
  (observed value `vertical`), `fill_container` 4, `commands` 4 (observed
  `["on_off","start_pause","stop","locate","return_home"]`), `entity` 4,
  `icon_type` 2, `name` 2, `grid_options` 2.
- `custom:mushroom-chips-card` (n=2): `chips` only — no `alignment`.
- `entity` chips (n=8): `entity` 8, `icon` 2. No `content_info`, no `icon_color`,
  no `name`, no actions.
- **No templated field was found in any custom card config** (the census checked every
  string value for `{{`/`{%`). The one heavily-templated card is a
  `custom:button-card` using JavaScript `[[[ ... ]]]`, which is out of scope.

**Conclusions for prioritisation**

1. `fill_container` + `layout: vertical` + `icon_type` + `commands` are used **today** on
   the vacuum card, so the shared appearance model (§4.1) is immediately exercised.
2. The only chip type in use is `entity`. Phase 1 can ship the chip shell plus
   `entity`/`template`/`icon`-only chips and cover 100% of live usage.
3. **Bubble Card has zero live usage.** Its priority rests entirely on psolyca's report and
   upstream popularity (4633 stars). This is **Open decision D1**.
4. `advanced-camera-card` dwarfs everything else and is already partly native — worth
   noting, but out of this plan's scope.

> Caveat: `docs/audit/ha-config-*.json` contain older captured copies of the same configs
> and yield higher counts (e.g. camera-menu 46, vacuum 6) because the per-dashboard files
> overlap `ha-config-lovelace.json`. The live census above is de-duplicated and is the
> number to use.

---

## 4. Design

### 4.1 `HAMushroomCardCell` — the shared base

New `HABaseEntityCell` subclass, modelled on `HATileEntityCell`
(`HADashboard/Views/Cells/HATileEntityCell.{h,m}`, 26/587 lines) which is the closest
existing analogue and already demonstrates the required patterns: three pre-built
constraint arrays swapped per layout mode (`.m:100-133`), a pure class-method height API
(`.m:42-63`), and `iconTapBlock` to separate icon taps from cell selection (`.h:24`).

Anatomy, mapping Mushroom's DOM 1:1:

| Mushroom element | Native | Notes |
|---|---|---|
| `ha-card` | `contentView`, `cornerRadius 14` (already set, `HABaseEntityCell.m:22-25`) | Mushroom has no radius token of its own; it inherits `--ha-card-border-radius`. Keep the app's 14pt for visual consistency — **D5** |
| `mushroom-shape-icon` | `HAMushroomShapeIconView`: a 36×36 `UIView`, `cornerRadius 18`, `backgroundColor` = tint at 0.05/0.2/0.25, holding a centred `UILabel` with the MDI glyph at 24pt | `cornerRadius = size/2` reproduces `border-radius: 50%` |
| `mushroom-shape-avatar` | the same view with a 36×36 `UIImageView`, `cornerRadius 18`, `clipsToBounds` | reuse `HATileEntityCell`'s authenticated `entity_picture` fetch (`.m:394-440`) verbatim, including `pictureTask` cancellation in `prepareForReuse` |
| `mushroom-badge-icon` | `HAMushroomBadgeView`: 16×16, `cornerRadius 8`, 12pt glyph, positioned `top:-3 right:-3` relative to the shape | `HABaseEntityCell` has no badge slot; this is new |
| `mushroom-state-info` | two `UILabel`s: primary 14pt weight 500, secondary 12pt regular | matches `--card-primary/secondary-font-size`; `multiline_secondary` → `numberOfLines = 0` |
| `div.actions` | `UIStackView` (iOS 9) with `spacing 12`, holding `HAMushroomButton` (42pt), `HAMushroomSlider`, `HAMushroomInputNumber` | mirrors `HATileEntityCell`'s `featuresStack` (`.m:128-156`) |

Layout modes, as three pre-built constraint arrays activated/deactivated — exactly
`HATileEntityCell`'s technique:
- `default` → icon left, labels right, actions stack below.
- `horizontal` → a horizontal root stack of [state-item | actions], actions height forced
  to 36 and left/right/top padding dropped; pass `fill = NO` to the button group.
- `vertical` → icon above centred labels, actions below.

`fill_container`: the cell always fills its grid slot, so `fill_container` affects only
whether content is top-aligned or vertically centred. Implement it as
`--layout-align`-equivalent centring. **[ASSUMPTION]** that this reads as equivalent on a
fixed-height grid cell; verify in the first parity pass.

**Theming.** All colours resolve through `HATheme`
(`HADashboard/Theme/HATheme.h:68-101`), never literals. Add one new helper:

```objc
// Resolves a Mushroom/HA colour token to a UIColor, per computeRgbColor
// (lovelace-mushroom src/utils/colors.ts:33-52).
+ (UIColor *)mushroomColorForToken:(NSString *)token;   // "red", "primary", "#rrggbb", "r, g, b"
+ (UIColor *)stateColorForEntity:(HAEntity *)entity;    // the --rgb-state-* / per-state maps
```
`+[HATheme colorFromString:]` (`HATheme.h:65`) already parses named colours (green,
yellow, red, orange, blue, purple, teal, grey, white, black, cyan, pink, indigo, amber)
and `#RRGGBB`. It is **missing** Mushroom's `primary`, `accent`, `deep-purple`,
`light-blue`, `light-green`, `lime`, `deep-orange`, `brown`, `light-grey`, `dark-grey`,
`blue-grey`, `disabled`, and the `"r, g, b"` triplet form. Extend it rather than fork it,
and seed the per-name RGB values from `colors.ts:65-93` so dark/light parity matches
upstream.

The existing `+[HAEntityDisplayHelper iconColorForEntity:]`
(`HADashboard/Views/HAEntityDisplayHelper.m:573-680`) hardcodes `UIColor` literals and a
different palette from Mushroom's. **Do not reuse it for Mushroom cells** — the Mushroom
state-colour map is a distinct, documented palette (§1.A.3) and must live in its own
resolver, or the cards will be visibly off-colour. (Harmonising the two is a separate,
larger decision.)

**State text.** `primary_info`/`secondary_info` resolve through a new
`+[HAEntityDisplayHelper mushroomInfoForEntity:info:configItem:]` whose `state` branch
calls **`HAStateLocalizer`** when available and falls back to
`+humanReadableState:`. This is what makes psolyca's `not_home` → `Absent` work, and it is
why Phase 0 depends on the i18n line landing. `last-changed`/`last-updated` reuse
`+relativeTimeFromISO8601:` (`HAEntityDisplayHelper.h:58`). The `" ⸱ "` suffix joining
(cover position, climate temp/humidity, fan percentage, media volume) belongs in this
helper, not inlined per cell — note `HATileEntityCell.m:286-335` already has ~95 lines of
exactly this logic inlined, which is the pattern to **avoid** repeating.

### 4.2 Option → `customProperties` mapping

`HADashboardConfigItem.customProperties` is an untyped `NSDictionary`
(`HADashboard/Models/HADashboardConfig.h:17`), merged with the established idiom:
```objc
NSMutableDictionary *props = [NSMutableDictionary dictionaryWithDictionary:item.customProperties ?: @{}];
props[key] = value;
if (props.count > 0) item.customProperties = [props copy];
```
Mushroom and Bubble options go into the same bag, keyed by their **upstream config names**
so the mapping stays auditable:

| Upstream key | `customProperties` key | Read by |
|---|---|---|
| `layout`, `fill_container`, `primary_info`, `secondary_info`, `icon_type` | same names | `HAMushroomCardCell`, and its height class method |
| `icon_color` | `icon_color` | shape icon tint |
| `collapsible_controls`, `use_light_color`, `icon_animation` | same | per-card subclass |
| `show_*_control`, `hvac_modes`, `commands`, `volume_controls`, `media_controls`, `states`, `display_mode` | same | controls builder |
| `multiline_secondary`, `alignment` | same | labels / chips container |
| `primary`, `secondary`, `badge_icon`, `badge_color`, `picture` (templatable) | `mushroom_tpl_<key>` for the source string, `mushroom_val_<key>` for the rendered result | template manager (§4.3) |
| Bubble `card_type`, `button_type`, `card_layout`, `rows`, `sub_button`, `show_state`, `scrolling_effect`, `force_icon`, `min_value`/`max_value`/`step` | same | `HABubble*Cell` |

The parser must **normalise** `custom:*` to an internal card type, following the proven
`mini-graph` precedent (`HALovelaceParser.m:792-849` → `compositeType = @"graph"`). Add a
single table-driven step near the top of `_processCard:`:

```objc
// custom:mushroom-light-card  -> @"mushroom-light"
// custom:mushroom-chips-card  -> composite @"mushroom-chips"
// custom:bubble-card + card_type: separator -> @"bubble-separator"
```
This replaces the scattered `containsString:` tests and is the one structural change the
whole plan rests on. Keep the raw string in
`customProperties[@"original_card_type"]` for diagnostics and for the unsupported-card
placeholder.

Entity extraction must also learn to walk `chips[]` for **all** chip types (emitting
entity-less chips as items with no `entityId`), and Bubble's `sub_button[]`, so those
entities enter the live-state subscription set — today they do not
(`HALovelaceParser.m:1299-1407`).

### 4.3 Templates

Today: `-[HAConnectionManager renderTemplate:completion:]`
(`HADashboard/Networking/HAConnectionManager.h:78-81`) is a **one-shot REST
`POST /api/template`** (`HADashboard/Networking/HAAPIClient.m:84-100`). There is **no**
`subscribe_template` / `render_template` anywhere (verified by grep). The only call site is
the markdown card (`HADashboardViewController.m:2406-2459`), which already implements most
of what Mushroom needs:
- group items **by template string** so one request serves many cards (`:2410-2424`);
- in-flight dedup via `pendingMarkdownTemplateStrings` (`:2426-2440`);
- a **static dependency filter**: the parser regex-extracts entity IDs from the template
  (`HALovelaceParser.m:305-311`, matching `state_attr|states|is_state`) into
  `markdown_template_dependencies`, and a state change for an unrelated entity skips the
  render (`:2420-2423`);
- on error, keep the last content rather than blanking (`:2444-2447`).

Gaps for Mushroom, and the proposal:

1. **No result cache and no debounce.** A burst of state changes issues a burst of
   distinct renders. Add an `HATemplateManager` that owns a bounded result cache keyed by
   `(template, entity)` — **200 entries, mirroring Bubble's own `remembered` map** — plus a
   coalescing timer reusing the dashboard's existing 0.3 s reload coalescer
   (`HADashboardViewController.m:2519-2545`).
2. **A full `reloadData` per batch** (`:2449-2458`). A Mushroom-template-heavy dashboard
   would thrash this on an iPad 2. Route template results through the existing
   `pendingReloadPaths` coalescer so only the affected visible cells reload.
3. **Transport.** Upstream (both projects) uses the WebSocket `render_template`
   subscription: the server pushes on change, so there is no polling and no dependency
   regex. `HAConnectionManager` already has the generic plumbing
   (`-subscribeWithCommand:handler:completion:`, `.m:629-640`). **This is Open decision
   D3.** My recommendation: **REST one-shot for Phase 1** (reuses a proven path, zero new
   subscription lifecycle, bounded by the dependency filter), with a hard cap of
   **N distinct templates per dashboard** (suggest 20) above which templates render once
   and then stop refreshing, with the cap surfaced in the unsupported-card diagnostics.
   Move to `render_template` subscriptions only if parity testing shows staleness, because
   on an iPad 2 one subscription per template per card is the more dangerous failure mode.
4. **Template detection** must match upstream exactly: `{{` or `{%` for the v5 card and
   Bubble (`jinja.js:11-13`), the looser `includes("{")` for the legacy card, the template
   chip and the title card.
5. **Variables.** Upstream passes `{config, user, entity, area}`. The REST
   `POST /api/template` endpoint accepts only `{"template": …}`
   (`HAAPIClient.m:91-93`), so `entity`-dependent templates must be **textually
   pre-bound** — i.e. substitute the entity id into the template before sending — or
   migrated to the WebSocket path, which accepts `variables`. This is a concrete argument
   for D3 choosing subscriptions, and a correctness risk if REST is chosen: a template
   referencing `entity` would silently render wrong. **Flagged as the single biggest
   open technical risk in this plan.**
6. A templated `name` that renders empty must show **empty**, not the friendly name
   (Bubble `getName`, `src/tools/utils.js:365-379`).

### 4.4 Actions

Almost free. `HAAction` (`HADashboard/Models/HAAction.h`) already supports `toggle`,
`more-info`, `call-service`, `perform-action`, `navigate`, `url`, `none`, parses the legacy
`service`/`service_data` aliases (`HAAction.m:25-26`) and `confirmation`. All six action
keys are parsed for every card type including `custom:*`
(`HALovelaceParser.m:1281-1288`), tap/hold/double-tap gestures live on the collection view
(`HADashboardViewController.m:185-213`, with the double-tap recognizer failing fast when
unconfigured, `:2211-2225`), and everything funnels through
`-executeActionType:forEntity:configProperties:` (`:2102-2124`) into
`HAActionDispatcher`.

Work needed:
1. **Per-card default actions.** `+[HAAction defaultTapActionForEntity:]`
   (`HAAction.m:47-61`) returns `toggle` for toggle domains / scene / script / button and
   `none` otherwise. Mushroom's defaults are **per card type**, not per domain: `toggle`
   for light/fan/cover/climate/humidifier/legacy-template, `more-info` for the rest
   (§1.A.4). Bubble's are **per `button_type`** (§1.B.3). Add
   `+defaultTapActionForCardType:entity:` and have
   `-executeActionType:forEntity:configProperties:` consult it.
2. **`icon_tap_action`.** Parsed but consumed only by `HATileEntityCell`'s `iconTapBlock`
   (`.h:24`); `icon_hold_action` / `icon_double_tap_action` are parsed and never read. The
   Mushroom shape icon should wire all three.
3. **Unsupported upstream actions**: `assist`, `expand`, and Bubble's
   `fire-dom-event`. Map to `none` and log once. Bubble pop-ups use `navigate` to a hash,
   which is handled in §4.5.
4. Do **not** replicate `HATileEntityCell.m:482-519` (`-tileLongPressed:`), which bypasses
   `HAActionDispatcher` with a hardcoded per-domain service call.

### 4.5 Bubble pop-ups

The hook already exists. `HAActionDispatcher -executeNavigate:` posts
`HAActionNavigateNotification` with `userInfo[@"path"]` (`HAActionDispatcher.m:129-136`);
`-actionNavigateRequested:` in the dashboard VC resolves it against view paths and indices
(`HADashboardViewController.m` — the handler takes `[path lastPathComponent]` and matches
`view.path` or title, then a numeric index). **A path beginning with `#` currently matches
nothing and is a silent no-op** — exactly the insertion point.

Proposal:
1. The parser collects every `card_type: pop-up` into a dashboard-level registry
   `hash → {header config, cards[]}` and does **not** emit a cell for it. The pop-up's
   nested `cards[]` must still be walked for entity extraction so their state is
   subscribed.
2. `-actionNavigateRequested:` gains a leading branch: a path starting with `#` looks up
   the registry and presents an `HAPopupViewController` via the existing
   `HABottomSheetTransitioningDelegate` / `HABottomSheetPresentationController`
   (already instantiated at `HADashboardViewController.m:177` and already used for
   more-info, `HAEntityDetailViewController.m:88-89`), which gives dimming and
   pan-to-dismiss (= Bubble's `slide_to_close`) for free.
3. The pop-up body is a second `UICollectionView` running the **same**
   parser → factory → cell pipeline, so every card already supported works inside a
   pop-up with no extra work.
4. Map `popup_mode`: `default`/`fit-content` → the bottom sheet; `centered`/
   `adaptive-dialog` → a centred modal. `bg_blur`/`backdrop_blur` → `HATheme`'s existing
   blur with the `canBlur`/`blurDisabled` A5 escape hatches
   (`HATheme.h:33-39,107-112`). `auto_close` → an `NSTimer`. `trigger_entity`/
   `trigger_state` → open/close on a state change. **D4** sets how much of this ships.
5. `horizontal-buttons-stack` (`position:fixed; bottom:16px; height:51px; z-index:6`) and
   footer-mode sub-buttons (`bottom: 16px; z-index:5`) are **fixed-position bars**
   (§1.B.6, §1.B.7), so they become a pinned bottom `UIScrollView` toolbar owned by the
   dashboard VC, not cells. Upstream even forces 80pt of extra bottom padding on the
   dashboard so the last card is not covered
   (`horizontal-buttons-stack/create.js:141-145`) — the native equivalent is
   `collectionView.contentInset.bottom`. Kiosk mode must be considered (CLAUDE.md: kiosk
   hides the nav bar).

Two further specifics the survey pins down:
- **Hash semantics**: navigating to the hash that is **already open closes it**
  (`pop-up/helpers.js:3073-3081`), and the previous hash is remembered for a back button
  (`:3066`). `horizontal-buttons-stack` buttons toggle rather than always opening
  (`hbs/create.js:38-62`). Reproduce both or the UX feels broken.
- **The header is a complete button card** (`pop-up/create.js:248-304`), so
  `HAPopupViewController`'s header must host the same `HABubbleCardCell` — icon circle,
  name/state line, sub-buttons and slider all work there — plus two 50×50 round
  close/previous buttons, with the content scroller overlapping it by 50pt. Building the
  pill first (Phase 4) is therefore a hard prerequisite for the pop-up (Phase 5).

### 4.6 Cell registration checklist

Adding one card type touches exactly four places (plus `scripts/regen.sh`, since XcodeGen
globs `path: HADashboard` — `project.yml:26-30` — so new files need no project edit):

1. `HADashboard/Views/HAEntityCellFactory.m` — a `k…CellId` constant (`:48-91`) and a
   `registerClass:` line (`:95-140`).
2. `+reuseIdentifierForEntity:cardType:` (`:252-309`) — a branch on the **normalised**
   internal type.
3. `HADashboardViewController.m:1805-1869` — a configure branch, unless the cell is a
   plain `HABaseEntityCell` subclass configured by `configureWithEntity:configItem:`, in
   which case none is needed. **Design the Mushroom cells to need none.**
4. `-heightForItemAtIndexPath:itemWidth:` (`:785-870`) — a height branch calling a pure
   class method, adding `headingExtra`.

`HAColumnarLayout` needs no change: `gridColumnsForItemAtIndexPath:` already returns
`item.columnSpan` (`:1967-1971`) and `grid_options` parsing is type-agnostic
(`HALovelaceParser.m:620-665`), so Mushroom's and Bubble's spans already work — confirmed
by the live vacuum cards carrying `grid_options`.

Mushroom's own sizing hints (`src/utils/base-card.ts:67-221`: `min_columns: 4` (2 if
vertical), `columns: 6`, horizontal → `{rows:1, columns:12}`, icon-only →
`{columns:3, rows:1}`) should become the **default span** when no `grid_options` is
present, replacing the current blanket 12 for `custom:` types (`:666-675`). This alone
will visibly improve existing Mushroom dashboards.

### 4.7 Performance and iOS 9

Constraints read from code, two of which **contradict CLAUDE.md**:

1. **Rasterization is effectively OFF for card cells.**
   `HADashboardViewController.m:1937-1942` sets
   `shouldRasterize = !isCamera && !isCard && !isBadge` where
   `isCard = (cell.contentView.layer.cornerRadius > 0)` — and `HABaseEntityCell` sets
   `cornerRadius = 14` in `initWithFrame:` (`HABaseEntityCell.m:22`). So every entity cell
   is excluded, deliberately, because `shouldRasterize` bakes the blur `backgroundView`
   into a bitmap. A Mushroom cell inherits this. **Do not plan around rasterization.**
2. **The reload coalescer is 0.3 s, not 0.5 s** (`:2529`).
3. Deferred loading: any cell doing network work must implement
   `-beginLoading`/`-cancelLoading` and be registered in **both**
   `willDisplayCell:` and `didEndDisplayingCell:` (`:1918-1957`). For the shape avatar,
   prefer `HATileEntityCell`'s lighter pattern: cancel `pictureTask` in
   `configureWithEntity:` and `prepareForReuse` (`.m:395,558-559`).
4. Blur is applied in **both** `cellForItem` and `willDisplay` because **on iOS 9
   `willDisplayCell:` may not fire for initially visible cells** (`:1863-1865`).
5. **No per-frame work.** Mushroom's 280 ms colour and 180 ms slider transitions should be
   single `UIView` animations on discrete state changes, never a `CADisplayLink`. The fan
   `spin` / vacuum `cleaning` animations are `CABasicAnimation` on `transform.rotation`,
   added on becoming active and **removed when inactive or on reuse** — an always-on
   rotation on an A5 is a measurable battery and scroll cost. `HAPerfMonitor`
   (`HADashboard/Views/HAPerfMonitor.h`) already instruments every cell build; use it.
6. **iOS 9 API surface.** `NSLayoutConstraint` anchors and `UIStackView` are both iOS 9 and
   used freely by `HATileEntityCell`. The guard idiom is `if (@available(iOS X, *))`
   (65 occurrences in `HADashboard/`). Avoid: dynamic `UIColor` providers, SF Symbols,
   `systemBackgroundColor` and friends (all iOS 13), modern cell configurations (iOS 14),
   compositional layout (iOS 13), `UIAction`/`UIMenu`. Follow the deliberate-avoidance
   precedents: `HAActionDispatcher.m:144-148` keeps the deprecated `openURL:` under a
   `#pragma clang diagnostic ignored`, and `HAIconMapper.m:26-57` refuses
   `CTFontManagerRegisterGraphicsFont` entirely because it hangs on jailbroken iOS 9.
7. **Memory.** 512 MB on an iPad 2. The Mushroom base cell must be one class with
   variant constraint sets, **not** 15 near-duplicate classes, and the reuse pool must
   stay small. Chips must be sub-views in one row cell (as `HABadgeRowCell` already is),
   never one cell per chip.
8. MDI already covers 7448 glyphs (`Vendor/MDI/mdi-codepoints.tsv`), loaded from a bundled
   TSV with no font-daemon IPC, so every upstream `mdi:` icon name resolves.
   `+glyphForIconName:` returns **nil** for unknown names — handle it
   (`HATileEntityCell.m:392` falls back to `@"?"`).

---

## 5. Visual parity method

### 5.1 What exists

| Tool | What it does |
|---|---|
`scripts/capture-screenshots.mjs` | Playwright/Chromium against `https://demo.ha-dash.app` (overridable `--url`), `1280×800 @2x`, `--theme dark\|light\|both`. Authenticates via the HA REST login flow with demo credentials and injects `hassTokens` into `localStorage` (`:44-112`). Per view: a `fullPage` PNG plus **per-section crops** obtained by piercing the HA 2026.2 shadow DOM down to `hui-section` (`:130-160`), each wrapped in a try/catch that silently degrades to full-page only (`:157-159`). Output `screenshots/ha-web/<theme>/`
`scripts/capture-ios.sh` | Installs the simulator build and relaunches it once per view × theme with `-HADashboard test-harness -HAViewIndex <i> -HAThemeMode <m>`, `xcrun simctl io … screenshot` → `screenshots/app/<theme>/view-<name>.png`
`scripts/compare-screenshots.mjs` | `pixelmatch` (threshold 0.3) producing a **parity report, not a pass/fail test** (`:4-7`). `compareAppParity()` only *maps* HA section files to app test suites and counts reference images — it does **not** pixel-compare them, because "HA sections contain multiple cards; app snapshots are per-cell" (`:234-236`)
`scripts/test-snapshots.sh` | On `main`: `iPad (10th generation), OS=17.4` → `ReferenceImages_64`. On the v1.3.0 line: pinned `18.0` with `SNAPSHOT_SIM_UDID`/`SNAPSHOT_SIM_NAME` overrides and `HA_SNAPSHOT_RUNTIME_SUFFIX=_ios18` → `ReferenceImages_ios18_64` (871 images, 18 suites)
`HADashboardTests/HABaseSnapshotTestCase` | `verifyView:identifier:` renders **dual-theme** (dark+gradient, then light) (`.m:112-115`); size constants at `.h:9-26` (`kColumnWidth 320`, `kSubGridUnit 320/12`); `recordMode` comes from the `RECORD_SNAPSHOTS` preprocessor define (`.m:14-15`) — **CLAUDE.md's "edit `recordMode = YES` by hand" is stale**
`HADashboard/Demo/HADemoDataProvider.m` | 2308 lines building demo dashboards as **raw Lovelace dictionaries in code** (e.g. `:1467-1490`, `:1499-1545`) returned as `HALovelaceDashboard`, plus a demo entity set with `// --- <domain> (test-harness) ---` markers

### 5.2 Three gaps to close

1. **The harness dashboard is not in this repo.** `capture-screenshots.mjs:25` says "must
   match test-harness.yaml view paths", but no such file exists here. It lives in the
   private `ha-dashboard/demo-server` repo as `dashboard.yaml` (title "Test Harness") plus
   `ha-config/dashboards/{lighting,climate,sensors,security,media,vacuums,inputs,entities}.yaml`,
   registered under `lovelace: mode: storage` with `mode: yaml` sub-dashboards
   (`ha-config/configuration.yaml:134-146`). **A YAML-mode dashboard needs explicit
   `lovelace: resources:` entries for custom cards — HACS auto-registration only applies
   to storage mode.** So adding Mushroom/Bubble views means: install both HACS repos on the
   demo server, declare their JS resources, add the view YAML, and register the view.
2. **The view list is hardcoded in two places** — `VIEWS` at
   `capture-screenshots.mjs:26-35` and the `"0:lighting" … "7:entities"` loop in
   `capture-ios.sh:75`. Both must gain the new views.
3. **Crops are per *section*, not per *card*.** Section crops cannot be compared to
   per-cell snapshots, which is exactly why `compareAppParity()` gives up.

### 5.3 Proposal

**A. Per-card crops.** Extend the shadow-DOM walk to descend from `hui-section` into each
`hui-card` (and the custom element inside it), emitting
`card-<view>-<section>-<index>-<cardtype>.png` keyed by the card's config `type`. This is
a small change to the existing `page.evaluate` block
(`capture-screenshots.mjs:130-160`) and makes a genuine 1:1 JS-vs-native comparison
possible for the first time.

**B. Two dedicated harness views.** `mushroom` and `bubble`, each a `sections` view with
one section per card type, and within it one card per option permutation that matters
(layout × fill_container × icon_type × primary/secondary_info, and the per-card controls).
Name each section after the card type so the crop filenames are stable.

**C. Offline parity via demo mode — do this first.** `HADemoDataProvider` builds dashboards
as raw Lovelace dicts in code, so a `demo-mushroom` / `demo-bubble` dashboard can be added
**in-app with no server at all**, exercising the real parser and the real cells, reachable
via `scripts/deploy.sh --demo`. This gives a fast inner loop and a reviewer-visible
showcase, and it is the only part of the parity story that needs no access to the private
demo-server repo. **Start here.**

**D. Snapshot suites.** One new file per card family —
`HADashboardTests/HAMushroomSnapshotTests.m`, `HAMushroomChipsSnapshotTests.m`,
`HABubbleSnapshotTests.m` — subclassing `HABaseSnapshotTestCase`, modelled on
`HADisplayConfigSnapshotTests_TileFeatures.m:14-32` (build item → set
`customProperties` → compute height from the cell's own class method → size
`CGSizeMake(floor(kSubGridUnit * span), height)` → `cellForEntity:` →
`verifyView:identifier:`). XcodeGen globs `HADashboardTests`
(`project.yml:126-128`), so no project edit is needed beyond `scripts/regen.sh`.
Two prerequisites:
- `HASnapshotTestHelpers` has **no** `customProperties:` factory variant
  (`+itemWithEntityId:cardType:columnSpan:headingIcon:displayName:` only sets
  `headingIcon`), so add one rather than rebuilding props in every test.
- `HABaseSnapshotTestCase.m:52-69` `-compositeCell:size:section:entities:configItem:`
  is an `isKindOfClass:` ladder hardcoded to `HAEntitiesCardCell`, `HABadgeRowCell`,
  `HAGlanceCardCell`. **A Mushroom chips cell must be added there** or it will be laid
  out but never configured.

Record against the pinned iOS 18.0 / iPad (10th generation) set
(`ReferenceImages_ios18_64`) using
`GCC_PREPROCESSOR_DEFINITIONS='RECORD_SNAPSHOTS=1'`, and commit the new suite directories.

**E. Fix the stale default** at `compare-screenshots.mjs:30-32` so `--app-refs` defaults to
the iOS 18 set, otherwise parity runs compare against the legacy 17.4 references.

**F. Report a parity number per card.** Once B and A exist, extend `compareAppParity()` to
actually pixel-compare `card-*-<cardtype>.png` against the matching single-cell snapshot
and emit a per-card-type match percentage in `screenshots/comparison-report.md`. That
number is the plan's acceptance signal; **D5** sets the bar.

---

## 6. Phasing, effort, risks

Effort is in engineer-days, calibrated against comparable existing cells:
`HATileEntityCell.m` 587 lines, `HABadgeRowCell.m` 728, `HAVacuumEntityCell.m` 408,
`HALightEntityCell.m` 301, `HAEntityDisplayHelper.m` 825. Estimates include dual-theme
snapshot tests and one parity pass. **[ASSUMPTION]** throughout.

### Phase 0 — land the groundwork (no new cards) · ~2–3 d

| Item | Why |
|---|---|
| Merge `feature/unsupported-card-placeholder` | Converts every future report from "cards are missing" into a precise type list. Highest value per hour in the whole plan, and it is already written |
| Merge the i18n line carrying `HAStateLocalizer` | Fixes psolyca's actual complaint (`not_home` → `Absent`) and is a prerequisite for correct Mushroom state text |
| Fix the `chipStyle` fixture bug (§2.5.2) | Chips are Phase 1; shipping on top of an untested `hideNames` path is avoidable risk |
| Ask psolyca for the list | It was promised, costs nothing, and would replace the §3 assumption-driven ordering with real data |

**Gate:** do not start Phase 1 until the placeholder ships and a real-world list (or an
explicit decision to proceed without one) exists.

### Phase 1 — Mushroom core · ~16–22 d

| Item | Est. | Notes |
|---|---|---|
| `custom:*` normalisation table in the parser + internal card types | 2 d | the structural change everything depends on; replaces the scattered `containsString:` tests |
| `HAMushroomCardCell` base: shape icon, badge, primary/secondary, 3 layouts, `fill_container`, height class method | 5–7 d | the single highest-leverage item |
| `HATheme` Mushroom colour resolver + state-colour map | 1–2 d | 26 colour names + `"r,g,b"` + the per-domain/per-state maps |
| `mushroom-entity-card` | 1 d | base + `icon_color` |
| Chip shell + chips container + `entity`/`icon`/`template`/`spacer` chips | 3–4 d | covers 100% of live chip usage; needs the `compositeCell:` ladder extension |
| `mushroom-vacuum-card` (proper `commands`, layout, `icon_animation`) | 1–2 d | highest live count; replaces the accidental mapping |
| `mushroom-title-card` | 0.5 d | two labels + alignment + optional tap actions |
| `mushroom-light-card` (brightness / colour-temp / colour, `collapsible_controls`, `use_light_color`) | 4–5 d | sliders + control cycling + `improveColorContrast` |
| Per-card default tap/hold actions + `icon_*` wiring | 1 d | |
| Demo-mode `demo-mushroom` dashboard + snapshot suite | 2 d | §5.3C/D |

### Phase 2 — Mushroom breadth · ~14–19 d

`mushroom-climate-card` 3–4 d (hvac buttons, temp steppers, hvac_action badge) ·
`mushroom-cover-card` 2–3 d (single next-control cycling) ·
`mushroom-fan-card` 2 d (three simultaneous controls, spin) ·
`mushroom-lock-card` 1 d · `mushroom-person-card` 1 d (zone badge) ·
`mushroom-select-card` 1 d · `mushroom-number-card` 1–1.5 d (slider/buttons) ·
`mushroom-humidifier-card` 1 d · `mushroom-update-card` 1 d ·
`mushroom-media-player-card` 3–4 d (two control groups, `use_media_info`) ·
`mushroom-alarm-control-panel-card` 2 d (code dialog) ·
remaining chips (`conditional`, `weather`, `alarm`, `light`, `menu`, `back`, `quickbar`) 2–3 d.

### Phase 3 — templates · ~6–9 d

`HATemplateManager` (cache, coalescing, cap, narrow reload) 3–4 d ·
`mushroom-legacy-template-card` 2–3 d · `template` chip 1 d ·
title-card templates 0.5 d. The v5 Tile-shaped `mushroom-template-card` maps to
`HATileEntityCell` instead (**D2**). **Blocked on D3**, and on resolving the `variables`
problem in §4.3.5.

### Phase 4 — Bubble core · ~11–15 d

The §1.B survey is option-complete, so no separate discovery pass is needed. The
"everything is one pill" finding (§1.B.0) is what keeps this phase smaller than Mushroom's:

`card_type` normalisation + `setConfig`-equivalent validation + `card_layout`/`rows`
1–2 d · **`HABubbleCardCell`** — the 50pt pill: 38pt icon circle, name 13/600 + state
12/0.7, trailing control stack, `is-on`/`is-off`/`is-unavailable` opacity states,
computed `--bubble-default-color` and the `getStateSurfaceColor` separation steps
3–4 d · `button_type` switch/state/name + the icon-vs-card action split 1–2 d ·
slider variant (transform-based fill, the full gesture state machine, per-domain range
mapping, read-only detection) 3–4 d · `separator` 0.5 d ·
`sub_button` (`default` + `select`, the `' · '` join, the 0.67 luminance text flip, and
the **extraction fix so sub-button entities are actually subscribed**) 2–3 d ·
`empty-column` 0.25 d · demo dashboard + snapshots 1–2 d.

### Phase 5 — Bubble breadth and pop-ups · ~15–23 d

`pop-up` registry + hash routing (incl. same-hash-closes and previous-hash back) +
bottom-sheet presentation with the header-as-a-card 5–8 d ·
the other three `popup_mode`s and the three `popup_style`s 2–3 d ·
pop-up surface options (`bg_color`/`bg_opacity` 88/`bg_blur` 10/`bg_lightness` 1.02/
`shadow_opacity`/`margin*`/`width_desktop` 540) 2 d ·
`auto_close` / entity triggers / click-outside with the drag-out exclusion 1–2 d ·
`horizontal-buttons-stack` as a pinned toolbar (JS-measured widths → native sizing,
rise animation, `highlight_current_view`, `auto_order`) 3–4 d ·
`climate` (3 domains, 700 ms debounce, limit shake) 2 d · `cover` (feature bitmask,
tilt rows) 1–2 d · `media-player` (5 buttons, volume overlay, blurred cover art) 2 d ·
`select` (dropdown, forced `tap_action: none`) 1 d · `calendar` (15 min refresh) 2 d ·
sub-button `slider`/`dropdown` types 2 d.

### Phase 6 — parity tooling and the long tail · ~5–8 d

Per-card crops 1–2 d · harness views in `demo-server` 1–2 d (needs that repo) ·
per-card parity numbers in the report 1 d · `--app-refs` default fix 0.25 d ·
`apexcharts-card` / `button-card` triage 2–3 d.

**Total: roughly 70–100 engineer-days for the full scope.** Phases 0–1 (~19–25 d) deliver
most of the user-visible win; everything after Phase 3 is **D1**.

### Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Template `variables` cannot be passed over REST** (§4.3.5) — an `entity`-referencing template would render silently wrong | **High** | Resolve D3 before Phase 3. Either pre-bind textually with a correctness proof, or implement `render_template` subscriptions. Do not ship a silent wrong answer |
| **No real-world card list** — the ordering after the 3 live Mushroom types is assumption-driven | High | Phase 0 asks psolyca; the unsupported-card placeholder makes the next report precise |
| **iPad 2 regression**: 15 new cell types, template renders, more subscribed entities | High | One base class not 15; cap distinct templates; route template results through the 0.3 s coalescer instead of `reloadData`; measure with `HAPerfMonitor` on a physical iPad 2 each phase |
| **Upstream churn** — Mushroom at 5.2.3 already rewrote its template card; Bubble is at 3.4.1 with heavy pop-up refactoring | Medium | Pin the surveyed commits (`ceefff0`, v3.4.1) in the plan; treat option tables as versioned; re-survey before each phase |
| **Pixel parity is unattainable** between WebKit and UIKit (different fonts, subpixel AA) — `compare-screenshots.mjs:4-7` says so explicitly | Medium | D5: agree a **structural** bar (anatomy, metrics, colours, option behaviour) with a numeric parity *trend*, not a pass/fail pixel threshold |
| **Private `demo-server` dependency** for JS-side parity; YAML-mode dashboards additionally need explicit `lovelace: resources:` | Medium | Demo-mode dashboards (§5.3C) give offline parity with no external dependency; treat the server views as Phase 6 |
| **`customProperties` is untyped** — ~40 new string keys with no compile-time checking | Medium | One header of `extern NSString * const` key constants; one validating parse site per card type; unit tests on the parser, as `HAUnsupportedCardTests.m` already does |
| **Mushroom's palette differs from `HAEntityDisplayHelper`'s hardcoded colours** | Medium | Separate resolver (§4.1); do not merge the two palettes under this plan |
| **Bubble fixed-position bars don't fit the cell model** | Medium | Toolbar on the VC, not a cell; `contentInset.bottom` for clearance; check kiosk-mode interaction |
| **Scope**: 70–100 d for cards nobody locally uses | Medium | D1 — consider stopping after Phase 3 |
| **Bubble's computed colour model** — `--bubble-default-color` is a runtime 70/30 mix recomputed on theme change, then put through two conditional separation steps and a luminance-based text flip (§1.B.1) | Medium | Port the formulas, not sampled colours; unit-test the mixer against the upstream arithmetic. Sampling a screenshot will drift as soon as the theme changes |
| **Bubble's gesture timings are load-bearing** — hold 500 ms dispatched *on release*, 200 ms double-tap deferral, 15 px hold dead zone, and a separate 200 ms/6 px/10 px slider machine (§1.B.9) | Medium | Encode the constants as named values in one header; the app's current long-press is 0.5 s (`HADashboardViewController.m:207-208`), which already matches, but the deferral and dead-zone behaviours do not exist yet |
| **Bubble's inline JS `${...}` style blocks are unportable** — the whole `styles` string is compiled as a JS template literal with 14 injected arguments including a tracking `hass` proxy (§1.B.10b) | Low–Medium | Explicitly unsupported. Detect a `styles` key containing `${` and surface it once through the unsupported-card diagnostics rather than failing silently. Same for `card_mod` |

---

## 7. Open decisions

**D1 — How far does this go?**
Live usage is 6 Mushroom cards and **zero** Bubble cards. Options: (a) Phases 0–1 only —
fix the drop path, ship the Mushroom base plus chips/vacuum/light/title, ~19–25 d;
(b) through Phase 3 — all Mushroom including templates, ~45–55 d; (c) full scope including
Bubble pop-ups, ~70–100 d. **Recommendation: commit to (a) now, decide (b) once psolyca's
list arrives, and gate (c) on evidence that Bubble users actually want this app.**

**D2 — Which Mushroom template card?**
Mushroom v5 rewrote `mushroom-template-card` on HA's Tile primitives; the Mushroom-looking
one is now `custom:mushroom-legacy-template-card`. Options: implement the legacy anatomy
and map the v5 card onto the existing `HATileEntityCell`; implement both natively; or
implement only the v5 card. **Recommendation: legacy anatomy natively + v5 onto
`HATileEntityCell`**, since the app already has a mature tile cell with `features`.

**D3 — Template transport, and what to do about `variables`.**
REST `POST /api/template` is proven here but accepts no `variables`
(`HAAPIClient.m:91-93`), so `entity`-dependent templates need textual pre-binding — a
correctness risk. WebSocket `render_template` matches both upstreams and supports
`variables`, but adds per-template subscription lifecycle on a 512 MB device.
**Recommendation: implement the WebSocket path for Phase 3** despite the extra work,
because the REST route's failure mode is a silently wrong label — precisely the class of
bug that started this. Pair it with the bounded cache, a hard per-dashboard cap, and the
grace-period/remembered-result design Bubble already proves
(`src/tools/render-template.js`).

**D4 — Pop-up fidelity.**
Bubble's pop-up is its largest feature: **four** `popup_mode`s (`default`, `fit-content`,
`centered`, `adaptive-dialog`), **three** `popup_style`s (`bubble`, `classic`,
`home-assistant`), a header that is itself a complete button card, hash routing with
same-hash-closes and previous-hash back navigation, blur/opacity/lightness/shadow/margin/
width options, slide-to-close, auto-close, click-outside with a drag-out exclusion, and
entity triggers (§1.B.3). Options: (a) one native bottom sheet in `default` mode only,
ignoring styling; (b) bottom sheet + `centered`, plus the header-as-a-card, hash routing
with both toggle semantics, `slide_to_close` and the `bg_*` surface; (c) full fidelity.
**Recommendation: (b)** — the existing bottom-sheet controller
(`HABottomSheetPresentationController`) gives dimming and pan-to-dismiss free, and (b)
covers the defaults every Bubble dashboard actually ships with. Note the header-as-a-card
requirement makes Phase 4's pill a hard prerequisite, and `42px` pop-up corners vs the
app's 14pt house radius is a D5 question.

**D5 — What does "matches appearance" mean, and whose radius wins?**
Pixel parity across WebKit and UIKit is impossible, and
`compare-screenshots.mjs:4-7` already says the comparison is a report, not a test. Also
concretely: Mushroom inherits HA's card radius while this app uses 14pt
(`HABaseEntityCell.m:22-25`), and Bubble uses 28pt pills and 42pt pop-ups. Options:
(a) reproduce upstream metrics exactly, accepting visual inconsistency with the app's
native cards; (b) reproduce anatomy, option behaviour and colours but keep the app's
radius/spacing; (c) make it a per-card setting. **Recommendation: (b)**, with the
exceptions of Mushroom's 36pt circular shape icon and Bubble's pill button, which *are*
the recognisable identity of each project and should be exact.

**D6 — Where does JS-side parity run?**
The harness lives in the private `ha-dashboard/demo-server`, is YAML-mode (so custom cards
need explicit `lovelace: resources:` entries on top of a HACS install), and the view list
is hardcoded in two scripts. Options: (a) demo-mode dashboards only — offline, no external
dependency, but no JS reference to compare against; (b) add the two HACS repos and two
views to the demo server; (c) a disposable local HA container for parity runs.
**Recommendation: (a) for the development loop, (b) once the first cards look right**, and
fix the stale `--app-refs` default either way.

---

## Appendix — verification log

Read-only commands used, for reproducibility:
- `gh issue view 19 --comments`; `gh issue list --repo ha-dashboard/ios-app --state all`
- `gh api repos/{piitaya/lovelace-mushroom,Clooos/Bubble-Card}` (stars, branch, release)
- `gh api repos/.../git/trees/main?recursive=1`; `gh api -H "Accept: application/vnd.github.raw" .../contents/<path>`
- `gh api repos/ha-dashboard/demo-server/...` (harness YAML, `configuration.yaml:134-146`)
- live HA WebSocket census via `<scratchpad>/cc_census.mjs` and `all_cards.mjs`
  (read-only `lovelace/dashboards/list`, `lovelace/config`; token never printed)
- `git branch -a`, `git ls-tree`, `git diff --stat main..<branch>`, `git show <branch>:<path>`
- `grep`/`sed` over `HADashboard/`, `HADashboardTests/`, `scripts/`, `project.yml`, `.gitignore`

Upstream commits pinned: Mushroom **`ceefff0`** (v5.2.3), Bubble Card **`061ed83`**
(v3.4.1). Re-survey before starting each phase; both projects move quickly.

Not verified in this pass, and the only assumptions that affect the ordering: the
**relative** upstream popularity of individual Mushroom card types (used to rank items 4–8
in §0, since no download-per-card statistic exists), and whether `fill_container` is
visually equivalent on a fixed-height grid cell (§4.1). Bubble's `styles`/`card_mod` JS
engine is documented but deliberately out of scope (§1.B.10b).
