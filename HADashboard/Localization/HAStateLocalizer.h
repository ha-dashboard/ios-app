#import <Foundation/Foundation.h>

@class HAConnectionManager;

NS_ASSUME_NONNULL_BEGIN

/// Holds Home Assistant's own `frontend/get_translations` data (category
/// `entity_component`, unfiltered) and answers "what should this entity state
/// display as" without the app hardcoding per-language English/French tables.
///
/// See docs/plans/i18n-plan.md §2 for the full design. In short:
///   - HA, not the app, owns entity-state and attribute-label translations
///     (`not_home` -> "Away" / "Absent", `door`+`on` -> "Open" / "Ouvert", …).
///   - `unavailable`/`unknown` are the one exception — HA does not serve them
///     over the WebSocket, so they stay app-owned keys (§2.3).
///   - The singleton holds one flat `NSDictionary<NSString*, NSString*>` keyed
///     by HA's dotted `component.{domain}.entity_component.{device_class}.state.{state}`
///     strings, loaded from `HACacheManager` at launch and refreshed over the
///     WebSocket after connect.
///
/// Performs no I/O and no network access when merely instantiated, or when
/// running under XCTest — every public mutator here no-ops under XCTest so
/// the existing snapshot/unit test suite is unaffected unless a test injects
/// fixture data itself via `test_setResources:languageCode:`.
@interface HAStateLocalizer : NSObject

+ (instancetype)sharedLocalizer;

/// The language code the localizer currently holds live/cached data for
/// (e.g. "fr"), or nil if nothing has loaded yet.
@property (nonatomic, copy, readonly, nullable) NSString *loadedLanguageCode;

/// Whether the localizer currently holds any HA-sourced resources. False
/// before the first successful fetch/cache-load — in that state every state
/// lookup degrades to the pre-Phase-2 behaviour (humanReadableState:, then
/// the raw state), which must be byte-identical to how the app behaved
/// before this class existed.
@property (nonatomic, readonly) BOOL hasResources;

/// Synchronously loads any on-disk cache for `languageCode` (via
/// `HACacheManager`, filename `ha-translations-<lang>.json`) into memory.
/// Call once at launch, before the first dashboard render, mirroring
/// `-[HAConnectionManager loadCachedStateIfAvailable]`. A payload over
/// 512 KB on disk is treated as corrupt/unexpected and discarded rather than
/// loaded. No-op (no disk access) under XCTest.
- (void)loadCachedStateForLanguage:(NSString *)languageCode;

/// Fetches `frontend/get_translations` (category `entity_component`,
/// unfiltered — see plan §2.7 for the memory-footprint reasoning) for
/// `languageCode` over `connectionManager`, caches the result via
/// `HACacheManager`, and swaps it in once it lands. Debounced: skips the
/// network round-trip if the cache for this exact language was refreshed
/// within the last 24 hours. Caps the cached payload at 512 KB and keeps at
/// most 2 languages on disk (current + previous), evicting the rest.
/// No-op under XCTest.
- (void)refreshForLanguage:(NSString *)languageCode
          connectionManager:(HAConnectionManager *)connectionManager;

/// Resolves the user-facing string for an entity state, per the lookup chain
/// in docs/plans/i18n-plan.md §2.2/§2.7:
///   1. (deliberately skipped in Phase 2 — see plan §2.7 "Recommendation":
///      the `entity` category, which `translationKey`+`platform` would key
///      into, is not fetched.) `translationKey` and `platform` are accepted
///      here only so call sites don't need to change again if Phase 2b ships.
///   2. `component.{domain}.entity_component.{deviceClass}.state.{state}`
///      when `deviceClass` is non-empty.
///   3. `component.{domain}.entity_component._.state.{state}` (the `_`
///      no-device-class bucket).
///   4. `-[HAEntityDisplayHelper humanReadableState:]` (demoted to a
///      last-resort fallback).
///   5. the raw `state` string.
/// `unavailable` and `unknown` are special-cased and checked FIRST, against
/// the app-owned `state.default.unavailable` / `state.default.unknown` keys
/// — they never reach the HA-sourced chain, matching HA's own frontend
/// (`compute_state_display.ts:94-101`), which special-cases them before its
/// own translation lookup for the same reason: HA does not serve them either.
- (NSString *)localizedStateForDomain:(nullable NSString *)domain
                           deviceClass:(nullable NSString *)deviceClass
                              platform:(nullable NSString *)platform
                        translationKey:(nullable NSString *)translationKey
                                 state:(NSString *)state;

/// Resolves HA's own translation of an ATTRIBUTE's display label (not its
/// value) for `domain`+`attr`, per docs/plans/i18n-plan.md §2.4:
/// `component.{domain}.entity_component._.state_attributes.{attr}.name`.
///
/// Returns nil on a miss (no live HA data for this key, or no match at
/// all) rather than any fallback — unlike `-localizedStateForDomain:…`,
/// there is no sensible raw-string fallback for an attribute's *label*.
/// Callers should fall back to an app-owned `attr.*` key (plan §1.4 rule
/// 2), e.g.:
///   NSString *label = [[HAStateLocalizer sharedLocalizer]
///       localizedAttributeNameForDomain:@"climate" attr:@"aux_heat"]
///       ?: HALocalizedString(@"attr.aux_heat.name", @"…");
/// 11 of the 12 attribute labels probed in plan §2.4 come from HA; only
/// `aux_heat` (deprecated in HA core) does not, and needs the app-owned
/// fallback in every caller.
- (nullable NSString *)localizedAttributeNameForDomain:(NSString *)domain
                                                    attr:(NSString *)attr;

/// Resolves HA's own translation of an ATTRIBUTE's VALUE (not its label,
/// and not the entity's own state) for `domain`+`attr`+`value`, per
/// docs/plans/i18n-plan.md §2.4 and verified live against a real HA
/// instance (2026.9.4) for climate preset_mode/fan_mode/swing_mode/
/// hvac_action, humidifier mode, and water_heater operation_mode --
/// confirmed key shape:
///   `component.{domain}.entity_component.{deviceClass}.state_attributes.{attr}.state.{value}`
///   `component.{domain}.entity_component._.state_attributes.{attr}.state.{value}` (no-device-class bucket)
/// (core: `async_translate_state_attr`,
/// `homeassistant/helpers/translation.py:496-533`.) A device_class-keyed
/// bucket genuinely exists for some domains (verified live: `event`'s
/// `event_type` attribute is keyed by device_class `button`/`doorbell`),
/// so both rungs are checked, same shape as `-localizedStateForDomain:…`.
///
/// NOT confirmed served by HA (verified live, same instance): fan's
/// preset_mode, media_player's source/sound_mode, vacuum's fan_speed --
/// these are either free-form/integration-specific text or simply not
/// covered by this category. Callers for those attributes should not use
/// this method; keep them on the algorithmic prettifier.
///
/// Same fallback rungs as `-localizedStateForDomain:…`: device_class rung,
/// then the `_` bucket rung, then `-[HAEntityDisplayHelper
/// humanReadableState:]` as the final algorithmic fallback (never raw
/// `value` unprettified, matching how entity states degrade). Returns
/// `value` itself unmodified if `value` is nil.
- (nullable NSString *)localizedAttributeValueForDomain:(NSString *)domain
                                               deviceClass:(nullable NSString *)deviceClass
                                                      attr:(NSString *)attr
                                                     value:(NSString *)value;

#pragma mark - Language resolution (pure functions — no network, no I/O)

/// Normalises a BCP-47-ish code to HA's bare language code: lowercases,
/// strips the region (`fr-CA` -> `fr`, `en-GB` -> `en`), and falls back to
/// "en" for anything empty or not a recognised ISO 639-1 language code
/// (`zz` -> `en`), per docs/plans/i18n-plan.md §2.6.
+ (NSString *)normalizedLanguageCode:(nullable NSString *)code;

/// Pure language-resolution chain (docs/plans/i18n-plan.md §2.6), safe to
/// unit-test with injected fixture values and no network access:
///   1. `overrideLanguageCode` (the in-app Settings override), if non-empty.
///   2. `userDataLanguage` (`frontend/get_user_data` key `language` ->
///      `.value.language`), if non-empty.
///   3. `configLanguage` (`get_config` -> `language`), if non-empty.
///   4. `appChromeLanguage` (`HAStrings.activeLanguageCode`), else "en".
/// The chosen value is passed through `+normalizedLanguageCode:`.
+ (NSString *)resolveLanguageWithOverride:(nullable NSString *)overrideLanguageCode
                          userDataLanguage:(nullable NSString *)userDataLanguage
                            configLanguage:(nullable NSString *)configLanguage
                         appChromeLanguage:(nullable NSString *)appChromeLanguage;

/// The language code the full resolution chain last landed on (persisted to
/// NSUserDefaults every time `-refreshForLanguage:connectionManager:` runs,
/// regardless of whether that call's network fetch succeeds, is debounced,
/// or fails) -- i.e. our best-known answer to "what language is the
/// connected HA server actually in", independent of the app's own chrome
/// language. Nil before the first successful connect of this install.
+ (nullable NSString *)lastResolvedLanguageCode;

/// Pure cold-start language choice (docs/plans/i18n-plan.md §2.7's "cold
/// start" gap): which cached-translations file to load synchronously at
/// launch, before HA's own profile language is known (that requires a
/// round trip once connected -- see `-refreshStateLocalizerLanguage` in
/// HAConnectionManager). Prefers the server's own last-known language over
/// the device/app chrome language, so a French HA on an English iPad shows
/// French states immediately offline instead of waiting for the
/// post-connect refresh:
///   1. `overrideLanguageCode` (the in-app Settings override), if non-empty.
///   2. `persistedLanguage` (`+lastResolvedLanguageCode`), if non-empty.
///   3. `appChromeLanguage`, else "en".
/// The chosen value is passed through `+normalizedLanguageCode:`.
+ (NSString *)coldStartLanguageWithOverride:(nullable NSString *)overrideLanguageCode
                           persistedLanguage:(nullable NSString *)persistedLanguage
                           appChromeLanguage:(nullable NSString *)appChromeLanguage;

#pragma mark - Test support

/// Test-only seam: injects a flat resources dictionary directly, bypassing
/// fetch/cache entirely, so tests can exercise `-localizedStateForDomain:...`
/// against a committed fixture (see HADashboardTests/Fixtures/) without
/// touching the network or disk. Pass a nil dictionary to reset the
/// localizer back to its empty, pre-Phase-2-equivalent state.
- (void)test_setResources:(nullable NSDictionary<NSString *, NSString *> *)resources
              languageCode:(nullable NSString *)languageCode;

/// Test-only seam: directly sets/clears the persisted "last resolved HA
/// language" (normally written only by `-refreshForLanguage:connectionManager:`),
/// so cold-start tests can inject it without a real connection. Pass nil to
/// clear back to the "never connected" state.
+ (void)test_setLastResolvedLanguageCode:(nullable NSString *)languageCode;

@end

NS_ASSUME_NONNULL_END
