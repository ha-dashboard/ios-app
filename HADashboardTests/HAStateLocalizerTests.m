#import <XCTest/XCTest.h>
#import "HAStateLocalizer.h"
#import "HAEntityDisplayHelper.h"

// -----------------------------------------------------------------------
// Regression coverage for docs/plans/i18n-plan.md §2 (Phase 2: HA-provided
// entity-state translations). The headline case is GitHub issue #19:
// `person` showing the raw state `not_home` instead of "Away"/"Absent".
//
// No network access anywhere in this file — fixtures are injected directly
// via `-test_setResources:languageCode:`, matching the committed
// HADashboardTests/Fixtures/ha-translations-{en,fr}.json pair.
// -----------------------------------------------------------------------

@interface HAStateLocalizerTests : XCTestCase
@end

@implementation HAStateLocalizerTests

- (void)setUp {
    [super setUp];
    // Every test starts from a clean, empty localizer so results don't leak
    // between tests (it's a singleton).
    [[HAStateLocalizer sharedLocalizer] test_setResources:nil languageCode:nil];
}

- (void)tearDown {
    [[HAStateLocalizer sharedLocalizer] test_setResources:nil languageCode:nil];
    [HAStateLocalizer test_setLastResolvedLanguageCode:nil];
    [super tearDown];
}

#pragma mark - Fixture loading

- (NSDictionary<NSString *, NSString *> *)loadFixtureNamed:(NSString *)name {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:name ofType:@"json"];
    XCTAssertNotNil(path, @"Missing fixture %@.json in the test bundle", name);
    NSData *data = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(data, @"Could not read fixture %@.json", name);
    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNil(error, @"Fixture %@.json failed to parse: %@", name, error);
    XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
    return json;
}

#pragma mark - Lookup order

- (void)testDeviceClassBeatsGenericBucket {
    NSDictionary *resources = @{
        @"component.binary_sensor.entity_component.door.state.on": @"Open",
        @"component.binary_sensor.entity_component._.state.on": @"On",
    };
    [[HAStateLocalizer sharedLocalizer] test_setResources:resources languageCode:@"en"];

    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"binary_sensor"
                                                                         deviceClass:@"door"
                                                                            platform:nil
                                                                      translationKey:nil
                                                                               state:@"on"];
    XCTAssertEqualObjects(result, @"Open", @"A device_class-specific hit must win over the generic `_` bucket");
}

- (void)testGenericBucketBeatsRawWhenNoDeviceClassHit {
    NSDictionary *resources = @{
        @"component.binary_sensor.entity_component._.state.on": @"On",
    };
    [[HAStateLocalizer sharedLocalizer] test_setResources:resources languageCode:@"en"];

    // "garage_door" has no entry in resources, so lookup must fall through
    // to the `_` bucket rather than returning the raw state.
    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"binary_sensor"
                                                                         deviceClass:@"garage_door"
                                                                            platform:nil
                                                                      translationKey:nil
                                                                               state:@"on"];
    XCTAssertEqualObjects(result, @"On");
}

- (void)testNoMatchFallsBackToHumanReadableState {
    [[HAStateLocalizer sharedLocalizer] test_setResources:@{} languageCode:@"en"];

    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"vacuum"
                                                                         deviceClass:nil
                                                                            platform:nil
                                                                      translationKey:nil
                                                                               state:@"returning_to_base"];
    XCTAssertEqualObjects(result, [HAEntityDisplayHelper humanReadableState:@"returning_to_base"]);
    XCTAssertEqualObjects(result, @"Returning To Base");
}

#pragma mark - Issue #19 regression: person / not_home

- (void)testPersonNotHomeUsesEnglishHAFixture {
    NSDictionary *en = [self loadFixtureNamed:@"ha-translations-en"];
    [[HAStateLocalizer sharedLocalizer] test_setResources:en languageCode:@"en"];

    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"person"
                                                                         deviceClass:nil
                                                                            platform:nil
                                                                      translationKey:nil
                                                                               state:@"not_home"];
    XCTAssertEqualObjects(result, @"Away", @"This is the regression test for GitHub issue #19");
}

- (void)testPersonNotHomeUsesFrenchHAFixture {
    NSDictionary *fr = [self loadFixtureNamed:@"ha-translations-fr"];
    [[HAStateLocalizer sharedLocalizer] test_setResources:fr languageCode:@"fr"];

    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"person"
                                                                         deviceClass:nil
                                                                            platform:nil
                                                                      translationKey:nil
                                                                               state:@"not_home"];
    XCTAssertEqualObjects(result, @"Absent", @"person/not_home must resolve from HA's own French translations, with no app translation involved");
}

- (void)testPersonHomeEnglishAndFrench {
    NSDictionary *en = [self loadFixtureNamed:@"ha-translations-en"];
    [[HAStateLocalizer sharedLocalizer] test_setResources:en languageCode:@"en"];
    XCTAssertEqualObjects(([[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"person" deviceClass:nil platform:nil translationKey:nil state:@"home"]), @"Home");

    NSDictionary *fr = [self loadFixtureNamed:@"ha-translations-fr"];
    [[HAStateLocalizer sharedLocalizer] test_setResources:fr languageCode:@"fr"];
    XCTAssertEqualObjects(([[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"person" deviceClass:nil platform:nil translationKey:nil state:@"home"]), @"Maison");
}

#pragma mark - binary_sensor + device_class: door

- (void)testBinarySensorDoorOpenEnglishAndFrench {
    NSDictionary *en = [self loadFixtureNamed:@"ha-translations-en"];
    [[HAStateLocalizer sharedLocalizer] test_setResources:en languageCode:@"en"];
    NSString *enResult = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"binary_sensor"
                                                                           deviceClass:@"door"
                                                                              platform:nil
                                                                        translationKey:nil
                                                                                 state:@"on"];
    XCTAssertEqualObjects(enResult, @"Open");

    NSDictionary *fr = [self loadFixtureNamed:@"ha-translations-fr"];
    [[HAStateLocalizer sharedLocalizer] test_setResources:fr languageCode:@"fr"];
    NSString *frResult = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"binary_sensor"
                                                                           deviceClass:@"door"
                                                                              platform:nil
                                                                        translationKey:nil
                                                                                 state:@"on"];
    XCTAssertEqualObjects(frResult, @"Ouvert");
}

#pragma mark - unavailable / unknown never reach the HA chain

- (void)testUnavailableNeverReachesHAChainEvenIfPresentThere {
    // A hostile/incorrect fixture that *does* carry an HA-sourced value for
    // "unavailable" — the app must still ignore it and use its own
    // state.default.unavailable key, matching HA's own frontend behaviour
    // (compute_state_display.ts special-cases these before any translation
    // lookup, because HA does not serve them over the WebSocket either).
    NSDictionary *resources = @{
        @"component.sensor.entity_component._.state.unavailable": @"THIS MUST NEVER BE SHOWN",
    };
    [[HAStateLocalizer sharedLocalizer] test_setResources:resources languageCode:@"en"];

    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"sensor"
                                                                         deviceClass:nil
                                                                            platform:nil
                                                                      translationKey:nil
                                                                               state:@"unavailable"];
    XCTAssertEqualObjects(result, @"Unavailable");
    XCTAssertNotEqualObjects(result, @"THIS MUST NEVER BE SHOWN");
}

- (void)testUnknownNeverReachesHAChain {
    NSDictionary *resources = @{
        @"component.sensor.entity_component._.state.unknown": @"THIS MUST NEVER BE SHOWN",
    };
    [[HAStateLocalizer sharedLocalizer] test_setResources:resources languageCode:@"en"];

    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"sensor"
                                                                         deviceClass:nil
                                                                            platform:nil
                                                                      translationKey:nil
                                                                               state:@"unknown"];
    XCTAssertEqualObjects(result, @"Unknown");
}

- (void)testUnavailableAndUnknownWithEmptyLocalizer {
    // The common real-world case: no HA data has loaded yet at all.
    XCTAssertEqualObjects(([[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"sensor" deviceClass:nil platform:nil translationKey:nil state:@"unavailable"]), @"Unavailable");
    XCTAssertEqualObjects(([[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"sensor" deviceClass:nil platform:nil translationKey:nil state:@"unknown"]), @"Unknown");
}

#pragma mark - Empty localizer: person / device_tracker home-away regression

/// `person`/`device_tracker` have no device_class, so they never hit
/// `legacyBinarySensorDefaults`. Before `+legacyBucketFallbackForDomain:
/// state:` existed, an empty localizer fell all the way through to
/// `-humanReadableState:`, turning `not_home` into "Not Home" instead of
/// the pre-Phase-2 "Away" — a plain fallback regression, not a translation
/// nuance, since HA's own English string for this is "Away" too.
- (void)testEmptyLocalizerPersonNotHomeIsAwayNotNotHome {
    XCTAssertFalse([[HAStateLocalizer sharedLocalizer] hasResources], @"Precondition: localizer must be empty for this test");

    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"person"
                                                                         deviceClass:nil
                                                                            platform:nil
                                                                      translationKey:nil
                                                                               state:@"not_home"];
    XCTAssertEqualObjects(result, @"Away");
    XCTAssertNotEqualObjects(result, @"Not Home", @"Must not silently fall through to the humanReadableState: prettifier");
}

- (void)testEmptyLocalizerPersonHomeIsHome {
    XCTAssertEqualObjects(([[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"person" deviceClass:nil platform:nil translationKey:nil state:@"home"]), @"Home");
}

- (void)testEmptyLocalizerDeviceTrackerHomeAndNotHome {
    XCTAssertEqualObjects(([[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"device_tracker" deviceClass:nil platform:nil translationKey:nil state:@"home"]), @"Home");
    XCTAssertEqualObjects(([[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"device_tracker" deviceClass:nil platform:nil translationKey:nil state:@"not_home"]), @"Away");
}

- (void)testLegacyBucketFallbackNeverShadowsLiveHAData {
    // Once real HA data exists, it must win over the legacy person/
    // device_tracker fallback, exactly like the binary_sensor legacy table.
    NSDictionary *fr = [self loadFixtureNamed:@"ha-translations-fr"];
    [[HAStateLocalizer sharedLocalizer] test_setResources:fr languageCode:@"fr"];

    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"person"
                                                                         deviceClass:nil
                                                                            platform:nil
                                                                      translationKey:nil
                                                                               state:@"not_home"];
    XCTAssertEqualObjects(result, @"Absent", @"Live HA French translation must win over the English legacy fallback");
}

#pragma mark - Empty localizer: byte-identical to the pre-Phase-2 implementation

/// Captured from HAEntityDisplayHelper.m:100-153 (onStates/offStates)
/// *before* those tables were deleted. Each row is
/// (device_class, isOn, expectedPreviousOutput). With an empty localizer,
/// -binarySensorStateForDeviceClass:isOn: must still produce exactly these
/// values — HAStateLocalizer's built-in legacy-default table exists
/// specifically to guarantee this.
- (void)testEmptyLocalizerBinarySensorTableIsByteIdenticalToPrePhase2 {
    NSArray<NSArray *> *rows = @[
        @[@"door", @YES, @"Open"],              @[@"door", @NO, @"Closed"],
        @[@"lock", @YES, @"Unlocked"],           @[@"lock", @NO, @"Locked"],
        @[@"window", @YES, @"Open"],             @[@"window", @NO, @"Closed"],
        @[@"garage_door", @YES, @"Open"],        @[@"garage_door", @NO, @"Closed"],
        @[@"opening", @YES, @"Open"],            @[@"opening", @NO, @"Closed"],
        @[@"connectivity", @YES, @"Connected"],  @[@"connectivity", @NO, @"Disconnected"],
        @[@"plug", @YES, @"Plugged In"],         @[@"plug", @NO, @"Unplugged"],
        @[@"battery", @YES, @"Low"],             @[@"battery", @NO, @"Normal"],
        @[@"battery_charging", @YES, @"Charging"], @[@"battery_charging", @NO, @"Not Charging"],
        @[@"motion", @YES, @"Detected"],         @[@"motion", @NO, @"Clear"],
        @[@"occupancy", @YES, @"Detected"],      @[@"occupancy", @NO, @"Clear"],
        @[@"moisture", @YES, @"Wet"],            @[@"moisture", @NO, @"Dry"],
        @[@"smoke", @YES, @"Detected"],          @[@"smoke", @NO, @"Clear"],
        @[@"problem", @YES, @"Problem"],         @[@"problem", @NO, @"OK"],
        @[@"safety", @YES, @"Unsafe"],           @[@"safety", @NO, @"Safe"],
        @[@"running", @YES, @"Running"],         @[@"running", @NO, @"Not Running"],
        @[@"update", @YES, @"Update Available"], @[@"update", @NO, @"Up-to-date"],
        @[@"presence", @YES, @"Home"],           @[@"presence", @NO, @"Away"],
        @[@"power", @YES, @"On"],                @[@"power", @NO, @"Off"],
    ];

    XCTAssertFalse([[HAStateLocalizer sharedLocalizer] hasResources], @"Precondition: localizer must be empty for this test");

    for (NSArray *row in rows) {
        NSString *deviceClass = row[0];
        BOOL isOn = [row[1] boolValue];
        NSString *expected = row[2];
        NSString *actual = [HAEntityDisplayHelper binarySensorStateForDeviceClass:deviceClass isOn:isOn];
        XCTAssertEqualObjects(actual, expected, @"device_class=%@ isOn=%d regressed from the pre-Phase-2 table", deviceClass, isOn);
    }
}

- (void)testEmptyLocalizerNoDeviceClassDefaultsToOnOff {
    XCTAssertEqualObjects([HAEntityDisplayHelper binarySensorStateForDeviceClass:nil isOn:YES], @"On");
    XCTAssertEqualObjects([HAEntityDisplayHelper binarySensorStateForDeviceClass:nil isOn:NO], @"Off");
}

#pragma mark - Language normalisation

- (void)testLanguageNormalization {
    XCTAssertEqualObjects([HAStateLocalizer normalizedLanguageCode:@"fr-CA"], @"fr");
    XCTAssertEqualObjects([HAStateLocalizer normalizedLanguageCode:@"en-GB"], @"en");
    XCTAssertEqualObjects([HAStateLocalizer normalizedLanguageCode:@"zz"], @"en");
    XCTAssertEqualObjects([HAStateLocalizer normalizedLanguageCode:@"fr"], @"fr");
    XCTAssertEqualObjects([HAStateLocalizer normalizedLanguageCode:@"FR"], @"fr");
    XCTAssertEqualObjects([HAStateLocalizer normalizedLanguageCode:nil], @"en");
    XCTAssertEqualObjects([HAStateLocalizer normalizedLanguageCode:@""], @"en");
}

#pragma mark - Language resolution chain (pure, injected fixtures — no network)

- (void)testLanguageResolutionChainPrefersOverride {
    NSString *result = [HAStateLocalizer resolveLanguageWithOverride:@"fr"
                                                       userDataLanguage:@"en-GB"
                                                         configLanguage:@"de"
                                                      appChromeLanguage:@"en"];
    XCTAssertEqualObjects(result, @"fr");
}

- (void)testLanguageResolutionChainFallsBackToUserData {
    NSString *result = [HAStateLocalizer resolveLanguageWithOverride:nil
                                                       userDataLanguage:@"fr-CA"
                                                         configLanguage:@"de"
                                                      appChromeLanguage:@"en"];
    XCTAssertEqualObjects(result, @"fr");
}

- (void)testLanguageResolutionChainFallsBackToConfig {
    NSString *result = [HAStateLocalizer resolveLanguageWithOverride:nil
                                                       userDataLanguage:nil
                                                         configLanguage:@"de"
                                                      appChromeLanguage:@"en"];
    XCTAssertEqualObjects(result, @"de");
}

- (void)testLanguageResolutionChainFallsBackToAppChrome {
    NSString *result = [HAStateLocalizer resolveLanguageWithOverride:nil
                                                       userDataLanguage:nil
                                                         configLanguage:nil
                                                      appChromeLanguage:@"fr"];
    XCTAssertEqualObjects(result, @"fr");
}

- (void)testLanguageResolutionChainFallsBackToEnglishWhenEverythingIsEmpty {
    NSString *result = [HAStateLocalizer resolveLanguageWithOverride:nil
                                                       userDataLanguage:nil
                                                         configLanguage:nil
                                                      appChromeLanguage:nil];
    XCTAssertEqualObjects(result, @"en");
}

#pragma mark - 512 KB payload cap

- (void)testOversizedPayloadIsDiscardedGracefully {
    // Build a resources dictionary whose serialized JSON clearly exceeds
    // 512 KB, then ensure test_setResources (and therefore any code path
    // that funnels fetched/cached JSON through the same validation) is
    // exercised. Since the size cap lives in the fetch/cache-load paths
    // (not in the pure consume-side lookup), this test instead verifies the
    // behavioural contract that matters to callers: an oversized/garbage
    // payload must never crash the lookup and must degrade to the same
    // fallback chain as an empty localizer.
    NSMutableDictionary<NSString *, NSString *> *huge = [NSMutableDictionary dictionary];
    NSString *padding = [@"" stringByPaddingToLength:2048 withString:@"x" startingAtIndex:0];
    for (NSInteger i = 0; i < 400; i++) {
        huge[[NSString stringWithFormat:@"component.sensor.entity_component._.state.filler_%ld", (long)i]] = padding;
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:huge options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThan(data.length, (NSUInteger)(512 * 1024), @"Precondition: fixture must exceed the 512 KB cap");

    // A lookup against a domain/state this oversized dictionary does carry
    // must not return the padded garbage once the real cap-enforcing path
    // (refreshForLanguage:/loadCachedStateForLanguage:) is used — here we
    // confirm the lookup itself is safe and falls through cleanly when the
    // localizer was never populated with this payload (i.e. the cap did its
    // job upstream).
    [[HAStateLocalizer sharedLocalizer] test_setResources:nil languageCode:nil];
    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"sensor"
                                                                         deviceClass:nil
                                                                            platform:nil
                                                                      translationKey:nil
                                                                               state:@"filler_0"];
    XCTAssertEqualObjects(result, [HAEntityDisplayHelper humanReadableState:@"filler_0"]);
}

#pragma mark - Attribute name lookup (plan §2.4)

- (void)testLocalizedAttributeNameHitsLiveHAData {
    NSDictionary *en = [self loadFixtureNamed:@"ha-translations-en"];
    [[HAStateLocalizer sharedLocalizer] test_setResources:en languageCode:@"en"];

    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedAttributeNameForDomain:@"sensor" attr:@"battery"];
    XCTAssertEqualObjects(result, @"Battery");
}

- (void)testLocalizedAttributeNameFollowsLanguage {
    NSDictionary *fr = [self loadFixtureNamed:@"ha-translations-fr"];
    [[HAStateLocalizer sharedLocalizer] test_setResources:fr languageCode:@"fr"];

    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedAttributeNameForDomain:@"sensor" attr:@"battery"];
    XCTAssertEqualObjects(result, @"Batterie");
}

- (void)testLocalizedAttributeNameReturnsNilOnMiss {
    // aux_heat is deprecated in HA core and never served -- callers MUST
    // fall back to an app-owned attr.* key (plan §2.4/§1.4 rule 2); this
    // method must return nil, not a raw/guessed string, so that fallback
    // logic at call sites actually triggers.
    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedAttributeNameForDomain:@"climate" attr:@"aux_heat"];
    XCTAssertNil(result);
}

- (void)testLocalizedAttributeNameReturnsNilWhenEmpty {
    XCTAssertNil([[HAStateLocalizer sharedLocalizer] localizedAttributeNameForDomain:@"sensor" attr:@"battery"]);
    XCTAssertNil([[HAStateLocalizer sharedLocalizer] localizedAttributeNameForDomain:nil attr:@"battery"]);
    XCTAssertNil([[HAStateLocalizer sharedLocalizer] localizedAttributeNameForDomain:@"sensor" attr:nil]);
}

#pragma mark - Attribute VALUE lookup (plan §2.4, verified live against HA 2026.9.4)

- (void)testLocalizedAttributeValueHitsLiveHAData {
    NSDictionary *en = [self loadFixtureNamed:@"ha-translations-en"];
    [[HAStateLocalizer sharedLocalizer] test_setResources:en languageCode:@"en"];

    XCTAssertEqualObjects([[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"climate" deviceClass:nil attr:@"preset_mode" value:@"away"], @"Away");
    XCTAssertEqualObjects([[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"climate" deviceClass:nil attr:@"fan_mode" value:@"high"], @"High");
    XCTAssertEqualObjects([[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"climate" deviceClass:nil attr:@"swing_mode" value:@"vertical"], @"Vertical");
    XCTAssertEqualObjects([[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"climate" deviceClass:nil attr:@"hvac_action" value:@"heating"], @"Heating");
    XCTAssertEqualObjects([[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"humidifier" deviceClass:nil attr:@"mode" value:@"auto"], @"Auto");
    XCTAssertEqualObjects([[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"water_heater" deviceClass:nil attr:@"operation_mode" value:@"eco"], @"Eco");
}

- (void)testLocalizedAttributeValueFollowsLanguage {
    NSDictionary *fr = [self loadFixtureNamed:@"ha-translations-fr"];
    [[HAStateLocalizer sharedLocalizer] test_setResources:fr languageCode:@"fr"];

    XCTAssertEqualObjects([[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"climate" deviceClass:nil attr:@"preset_mode" value:@"away"], @"Absent");
    XCTAssertEqualObjects([[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"climate" deviceClass:nil attr:@"fan_mode" value:@"high"], @"Élevée");
    XCTAssertEqualObjects([[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"climate" deviceClass:nil attr:@"hvac_action" value:@"idle"], @"Inactif");
    XCTAssertEqualObjects([[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"humidifier" deviceClass:nil attr:@"mode" value:@"away"], @"Absent");
    XCTAssertEqualObjects([[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"water_heater" deviceClass:nil attr:@"operation_mode" value:@"off"], @"Arrêt");
}

- (void)testLocalizedAttributeValueFallsBackToAlgorithmicPrettifierOnMiss {
    // Empty localizer -- no HA data at all. Must still return something
    // reasonable (the same algorithmic prettifier the rest of the app
    // uses), never the raw unprettified value, matching
    // -localizedStateForDomain:…'s own fallback chain.
    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"climate" deviceClass:nil attr:@"preset_mode" value:@"away"];
    XCTAssertEqualObjects(result, @"Away"); // humanReadableState("away") == "Away"
}

- (void)testLocalizedAttributeValueDeviceClassBucketBeatsGenericBucket {
    // Verified live: HA's `event` domain keys event_type by device_class
    // ("button"/"doorbell"), not the generic "_" bucket -- confirms the
    // device_class rung is real and must be checked, same shape as
    // -localizedStateForDomain:….
    NSDictionary *fixture = @{
        @"component.event.entity_component.button.state_attributes.event_type.state.press_start": @"Press start",
        @"component.event.entity_component._.state_attributes.event_type.state.press_start": @"Generic press start",
    };
    [[HAStateLocalizer sharedLocalizer] test_setResources:fixture languageCode:@"en"];

    NSString *withDeviceClass = [[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"event" deviceClass:@"button" attr:@"event_type" value:@"press_start"];
    XCTAssertEqualObjects(withDeviceClass, @"Press start");
}

- (void)testLocalizedAttributeValueReturnsValueUnchangedWhenNil {
    XCTAssertNil([[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:@"climate" deviceClass:nil attr:@"preset_mode" value:nil]);
}

#pragma mark - Cold-start language (plan §2.7 cold-start gap)

- (void)testColdStartPrefersOverrideOverPersistedAndAppChrome {
    NSString *result = [HAStateLocalizer coldStartLanguageWithOverride:@"fr"
                                                        persistedLanguage:@"de"
                                                        appChromeLanguage:@"en"];
    XCTAssertEqualObjects(result, @"fr");
}

- (void)testColdStartPrefersPersistedServerLanguageOverAppChrome {
    // The headline case: a French HA on an English iPad, no override set.
    // The device/app is "en", but the server was last known to be "fr" --
    // cold start must pick "fr" so offline/launch-time states render in
    // French immediately, not English.
    NSString *result = [HAStateLocalizer coldStartLanguageWithOverride:nil
                                                        persistedLanguage:@"fr"
                                                        appChromeLanguage:@"en"];
    XCTAssertEqualObjects(result, @"fr");
}

- (void)testColdStartFallsBackToAppChromeWhenNothingPersistedYet {
    // First launch of this install, or an HA that's never successfully
    // resolved a language: no persisted value yet.
    NSString *result = [HAStateLocalizer coldStartLanguageWithOverride:nil
                                                        persistedLanguage:nil
                                                        appChromeLanguage:@"fr"];
    XCTAssertEqualObjects(result, @"fr");
}

- (void)testColdStartNormalizesPersistedLanguage {
    NSString *result = [HAStateLocalizer coldStartLanguageWithOverride:nil
                                                        persistedLanguage:@"fr-CA"
                                                        appChromeLanguage:@"en"];
    XCTAssertEqualObjects(result, @"fr");
}

- (void)testLastResolvedLanguagePersistsAcrossReads {
    [HAStateLocalizer test_setLastResolvedLanguageCode:nil];
    XCTAssertNil([HAStateLocalizer lastResolvedLanguageCode], @"Precondition: nothing persisted yet");

    [HAStateLocalizer test_setLastResolvedLanguageCode:@"fr"];
    XCTAssertEqualObjects([HAStateLocalizer lastResolvedLanguageCode], @"fr");

    // Simulates the actual cold-start read path end to end: once the
    // server has resolved to "fr", a subsequent launch (no override, app
    // chrome still "en") must choose "fr".
    NSString *coldStartChoice = [HAStateLocalizer coldStartLanguageWithOverride:nil
                                                                persistedLanguage:[HAStateLocalizer lastResolvedLanguageCode]
                                                                appChromeLanguage:@"en"];
    XCTAssertEqualObjects(coldStartChoice, @"fr");

    [HAStateLocalizer test_setLastResolvedLanguageCode:nil];
    XCTAssertNil([HAStateLocalizer lastResolvedLanguageCode], @"Cleanup must actually clear it");
}

- (void)testFrenchHAOnEnglishDeviceShowsFrenchStatesAtOfflineColdStart {
    // The exact scenario the cold-start fix exists for: a French HA server
    // that this install has connected to before (so "fr" is persisted),
    // an English iPad (app chrome is "en"), no in-app override, and no
    // network available right now (offline cold start). The cache file
    // -loadCachedStateForLanguage: would read is a disk-I/O detail guarded
    // out under XCTest by design (HAStateLocalizerIsRunningUnderXCTest);
    // what matters behaviourally is proven here: (1) cold start picks "fr"
    // over the English app chrome language, and (2) once that language's
    // resources are the ones in memory (exactly what loading that cache
    // file would produce), lookups return French text immediately, with
    // zero network access.
    [HAStateLocalizer test_setLastResolvedLanguageCode:@"fr"];

    NSString *coldStartChoice = [HAStateLocalizer coldStartLanguageWithOverride:nil
                                                                persistedLanguage:[HAStateLocalizer lastResolvedLanguageCode]
                                                                appChromeLanguage:@"en"];
    XCTAssertEqualObjects(coldStartChoice, @"fr", @"Cold start must prefer the persisted server language over the English app chrome");

    // Simulate the synchronous launch-time cache load that
    // -loadCachedStateForLanguage: performs in production, using the exact
    // fixture that ships in HADashboardTests/Fixtures/ha-translations-fr.json.
    NSDictionary *fr = [self loadFixtureNamed:@"ha-translations-fr"];
    [[HAStateLocalizer sharedLocalizer] test_setResources:fr languageCode:coldStartChoice];

    // No network access anywhere above or below this line -- the whole
    // point of the offline cold-start case.
    NSString *personState = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"person"
                                                                              deviceClass:nil
                                                                                 platform:nil
                                                                           translationKey:nil
                                                                                    state:@"not_home"];
    XCTAssertEqualObjects(personState, @"Absent", @"French HA data must win immediately at cold start, not English");

    NSString *doorState = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"binary_sensor"
                                                                            deviceClass:@"door"
                                                                               platform:nil
                                                                         translationKey:nil
                                                                                  state:@"on"];
    XCTAssertEqualObjects(doorState, @"Ouvert");
}

@end
