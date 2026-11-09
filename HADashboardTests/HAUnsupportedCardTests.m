#import <XCTest/XCTest.h>
#import "HALovelaceParser.h"
#import "HADashboardConfig.h"

/// Covers the "unsupported card" placeholder feature: an unknown or
/// unmapped Lovelace card type that extracts zero entities should produce
/// a visible placeholder item (toggle ON, the default) or be skipped
/// exactly like before this feature existed (toggle OFF) — never crash,
/// and never placeholder a card type that is legitimately entity-less.
@interface HAUnsupportedCardTests : XCTestCase
@property (nonatomic, strong) NSNumber *savedToggleValue; // nil = key was absent
@end

@implementation HAUnsupportedCardTests

- (void)setUp {
    [super setUp];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id existing = [defaults objectForKey:HAShowUnsupportedCardsDefaultsKey];
    self.savedToggleValue = existing ? @([defaults boolForKey:HAShowUnsupportedCardsDefaultsKey]) : nil;
}

- (void)tearDown {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (self.savedToggleValue) {
        [defaults setBool:self.savedToggleValue.boolValue forKey:HAShowUnsupportedCardsDefaultsKey];
    } else {
        [defaults removeObjectForKey:HAShowUnsupportedCardsDefaultsKey];
    }
    [defaults synchronize];
    [super tearDown];
}

#pragma mark - Helpers

- (HADashboardConfig *)configForCards:(NSArray *)cards {
    NSDictionary *viewDict = @{@"title": @"Test", @"cards": cards};
    NSDictionary *dashDict = @{@"views": @[viewDict]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashDict];
    HALovelaceView *view = dashboard.views.firstObject;
    return [HALovelaceParser dashboardConfigFromView:view columns:3];
}

- (HADashboardConfigItem *)firstUnsupportedItemIn:(HADashboardConfig *)config {
    for (HADashboardConfigItem *item in config.items) {
        if ([item.cardType isEqualToString:HAUnsupportedCardType]) return item;
    }
    return nil;
}

- (HADashboardConfigItem *)itemWithEntityId:(NSString *)entityId in:(HADashboardConfig *)config {
    for (HADashboardConfigItem *item in config.items) {
        if ([item.entityId isEqualToString:entityId]) return item;
    }
    return nil;
}

#pragma mark - Default (toggle ON): unknown / unmapped custom cards get a placeholder

- (void)testUnknownCardType_defaultToggleOn_producesPlaceholderItem {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:HAShowUnsupportedCardsDefaultsKey];

    HADashboardConfig *config = [self configForCards:@[@{@"type": @"some-made-up-card"}]];

    HADashboardConfigItem *placeholder = [self firstUnsupportedItemIn:config];
    XCTAssertNotNil(placeholder, @"Unknown card type should produce a placeholder item by default");
    XCTAssertEqualObjects(placeholder.customProperties[HAUnsupportedCardTypeKey], @"some-made-up-card");
}

- (void)testUnmappedCustomCard_bubbleCard_producesPlaceholderWithRawType {
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"custom:bubble-card",
        @"card_type": @"pop-up"
    }]];

    HADashboardConfigItem *placeholder = [self firstUnsupportedItemIn:config];
    XCTAssertNotNil(placeholder, @"custom:bubble-card has no native mapping and no entity — should placeholder");
    XCTAssertEqualObjects(placeholder.customProperties[HAUnsupportedCardTypeKey], @"custom:bubble-card");
}

- (void)testPartiallySupportedCustomCard_mushroomChipsWithNoEntityChips_producesPlaceholder {
    // A mushroom-chips card built entirely of template/action chips (no "entity"
    // key on any chip) extracts zero entities today and silently vanished.
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"custom:mushroom-chips-card",
        @"chips": @[@{@"type": @"template", @"content": @"{{ states('sensor.x') }}"},
                     @{@"type": @"action", @"icon": @"mdi:refresh"}]
    }]];

    HADashboardConfigItem *placeholder = [self firstUnsupportedItemIn:config];
    XCTAssertNotNil(placeholder, @"An entity-less mushroom-chips card should placeholder, not vanish");
}

#pragma mark - Toggle OFF: today's silent-skip behaviour is preserved

- (void)testUnknownCardType_toggleOff_producesNoItem {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:HAShowUnsupportedCardsDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    XCTAssertFalse([HALovelaceParser showUnsupportedCardsEnabled]);

    HADashboardConfig *config = [self configForCards:@[@{@"type": @"some-made-up-card"}]];

    XCTAssertNil([self firstUnsupportedItemIn:config], @"Toggle OFF should skip silently, like before this feature existed");
    XCTAssertEqual(config.items.count, (NSUInteger)0);
}

#pragma mark - Known entity-optional cards never placeholder

- (void)testStandaloneButtonCard_noEntity_isNotPlaceholdered {
    // A button card with only icon/name/tap_action and no entity is a valid,
    // intentionally entity-less HA card — not "unsupported".
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"button",
        @"name": @"Doorbell",
        @"icon": @"mdi:bell",
        @"tap_action": @{@"action": @"call-service", @"service": @"script.doorbell"}
    }]];

    XCTAssertNil([self firstUnsupportedItemIn:config], @"A valid entity-less button card must not placeholder");
}

#pragma mark - Entity-less button card (GitHub #26)

/// The reporter's card: a sections-view button with no entity and a
/// perform-action tap_action targeting a vacuum.
- (NSDictionary *)reporterButtonCard {
    return @{
        @"type": @"button", @"show_name": @YES, @"show_icon": @YES, @"show_state": @NO,
        @"icon": @"mdi:robot-vacuum", @"color": @"red", @"name": @"Arr\u00eater Coco Marcel",
        @"tap_action": @{@"action": @"perform-action", @"perform_action": @"vacuum.stop",
                         @"target": @{@"entity_id": @[@"vacuum.valetudo_cocomarcel"]}},
        @"grid_options": @{@"columns": @"full"},
    };
}

- (HADashboardConfig *)sectionsConfigForCards:(NSArray *)cards {
    NSDictionary *dashDict = @{@"views": @[@{@"title": @"Test", @"type": @"sections",
                                             @"sections": @[@{@"type": @"grid", @"cards": cards}]}]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashDict];
    return [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3];
}

- (void)testEntitylessButton_reporterCard_becomesButtonItemWithConfig {
    HADashboardConfig *config = [self sectionsConfigForCards:@[[self reporterButtonCard]]];

    XCTAssertEqual(config.items.count, 1u, @"The entity-less button must render, not vanish");
    HADashboardConfigItem *item = config.items.firstObject;
    XCTAssertEqualObjects(item.cardType, @"button");
    XCTAssertNil(item.entityId);
    XCTAssertEqualObjects(item.displayName, @"Arr\u00eater Coco Marcel");
    XCTAssertEqual(item.columnSpan, 12, @"columns: full spans the whole section");
    XCTAssertEqual(item.rowSpan, 0);
    NSDictionary *props = item.customProperties;
    XCTAssertEqualObjects(props[@"icon"], @"mdi:robot-vacuum");
    XCTAssertEqualObjects(props[@"color"], @"red");
    XCTAssertEqualObjects(props[@"show_name"], @YES);
    XCTAssertEqualObjects(props[@"show_icon"], @YES);
    XCTAssertEqualObjects(props[@"show_state"], @NO);
    XCTAssertEqualObjects(props[@"tap_action"], [self reporterButtonCard][@"tap_action"]);
    XCTAssertNil(props[@"hold_action"], @"Unconfigured actions keep the dashboard defaults");
    XCTAssertNil([self firstUnsupportedItemIn:config]);
}

- (void)testEntitylessButton_iconOnlyWithEntityRemoved_becomesButtonItem {
    // HA's default button card with the entity deleted and only an icon kept;
    // an empty entity string is the same thing.
    for (NSDictionary *card in @[@{@"type": @"button", @"icon": @"mdi:lightbulb", @"icon_height": @"48px",
                                   @"hold_action": @{@"action": @"navigate", @"navigation_path": @"/x"},
                                   @"double_tap_action": @{@"action": @"url", @"url_path": @"https://example.com"}},
                                 @{@"type": @"button", @"entity": @"", @"icon": @"mdi:lightbulb", @"icon_height": @"48px",
                                   @"hold_action": @{@"action": @"navigate", @"navigation_path": @"/x"},
                                   @"double_tap_action": @{@"action": @"url", @"url_path": @"https://example.com"}}]) {
        HADashboardConfig *config = [self sectionsConfigForCards:@[card]];
        XCTAssertEqual(config.items.count, 1u, @"%@", card);
        HADashboardConfigItem *item = config.items.firstObject;
        XCTAssertEqualObjects(item.cardType, @"button");
        XCTAssertEqual(item.entityId.length, 0u);
        XCTAssertNil(item.displayName, @"No configured name: HA shows an empty name");
        XCTAssertEqual(item.columnSpan, 6, @"hui-button-card getGridOptions(): icon + name → 6 columns");
        XCTAssertEqualObjects(item.customProperties[@"icon"], @"mdi:lightbulb");
        XCTAssertEqualObjects(item.customProperties[@"icon_height"], @"48px");
        XCTAssertEqualObjects(item.customProperties[@"hold_action"][@"navigation_path"], @"/x");
        XCTAssertEqualObjects(item.customProperties[@"double_tap_action"][@"url_path"], @"https://example.com");
    }
}

- (void)testEntitylessButton_sizingFollowsHAButtonGridOptions {
    // show_name: false → 3 columns; below min_columns (2) widens, as for entity buttons.
    HADashboardConfig *iconOnly = [self sectionsConfigForCards:@[@{@"type": @"button", @"icon": @"mdi:bell", @"show_name": @NO}]];
    XCTAssertEqual(iconOnly.items.firstObject.columnSpan, 3);
    HADashboardConfig *narrow = [self sectionsConfigForCards:@[@{@"type": @"button", @"icon": @"mdi:bell",
                                                                 @"grid_options": @{@"columns": @1, @"rows": @1}}]];
    XCTAssertEqual(narrow.items.firstObject.columnSpan, 2);
    XCTAssertEqual(narrow.items.firstObject.rowSpan, 2, @"icon + name: min_rows 2");
    // Masonry views: half width like entity buttons.
    HADashboardConfig *masonry = [self configForCards:@[@{@"type": @"button", @"icon": @"mdi:bell"}]];
    XCTAssertEqual(masonry.items.firstObject.columnSpan, 6);
}

- (void)testEntitylessButton_blankNameAndNameConfigObject {
    HADashboardConfig *config = [self configForCards:@[@{@"type": @"button", @"icon": @"mdi:bell", @"name": @" "},
                                                       @{@"type": @"button", @"icon": @"mdi:bell", @"name": @{@"type": @"area"}}]];
    XCTAssertEqual(config.items.count, 2u);
    XCTAssertEqualObjects(config.items[0].customProperties[@"name_blank"], @YES);
    XCTAssertNil(config.items[0].displayName);
    XCTAssertNil(config.items[1].displayName, @"A name-config object has no entity to resolve against");
    XCTAssertNil(config.items[1].customProperties[@"name_blank"]);
}

- (void)testEntitylessButton_rendersEvenWithUnsupportedToggleOff {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:HAShowUnsupportedCardsDefaultsKey];
    HADashboardConfig *config = [self configForCards:@[[self reporterButtonCard]]];
    XCTAssertEqual(config.items.count, 1u);
    XCTAssertEqualObjects(config.items.firstObject.cardType, @"button");
}

- (void)testEntitylessButton_underGridHeading_embedsHeading {
    HADashboardConfig *config = [self configForCards:@[@{@"type": @"grid", @"grid_options": @{@"columns": @6}, @"cards": @[
        @{@"type": @"heading", @"heading": @"Robots", @"icon": @"mdi:robot"},
        [self reporterButtonCard]]}]];
    HADashboardConfigItem *item = config.items.firstObject;
    XCTAssertEqualObjects(item.cardType, @"button");
    XCTAssertEqualObjects(item.displayName, @"Robots");
    XCTAssertEqualObjects(item.customProperties[@"headingIcon"], @"mdi:robot");
    XCTAssertEqualObjects(item.customProperties[@"nameOverride"], @"Arr\u00eater Coco Marcel");
}

- (void)testEntitylessNonButtonCard_stillPlaceholdered {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:HAShowUnsupportedCardsDefaultsKey];
    HADashboardConfig *config = [self configForCards:@[@{@"type": @"gauge", @"name": @"No entity"}]];
    HADashboardConfigItem *placeholder = [self firstUnsupportedItemIn:config];
    XCTAssertNotNil(placeholder, @"Only button cards gain an entity-less rendering");
    XCTAssertEqualObjects(placeholder.customProperties[HAUnsupportedCardTypeKey], @"gauge");
}

- (void)testEmptyGridContainer_isNotPlaceholdered {
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"grid",
        @"cards": @[]
    }]];

    XCTAssertNil([self firstUnsupportedItemIn:config], @"An empty grid/stack wrapper is not an unsupported card type");
    XCTAssertEqual(config.items.count, (NSUInteger)0);
}

#pragma mark - Nested stack / grid cases

- (void)testUnsupportedCardNestedInsideHorizontalStack_stillPlaceholders {
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"horizontal-stack",
        @"cards": @[
            @{@"type": @"entity", @"entity": @"light.kitchen"},
            @{@"type": @"custom:bubble-card", @"card_type": @"separator"}
        ]
    }]];

    HADashboardConfigItem *placeholder = [self firstUnsupportedItemIn:config];
    XCTAssertNotNil(placeholder, @"An unsupported card nested inside a horizontal-stack should still placeholder");

    // The sibling entity card must still render normally alongside it.
    BOOL foundLightItem = NO;
    for (HADashboardConfigItem *item in config.items) {
        if ([item.entityId isEqualToString:@"light.kitchen"]) foundLightItem = YES;
    }
    XCTAssertTrue(foundLightItem, @"Sibling supported card inside the stack must be unaffected");
}

- (void)testUnsupportedCardNestedInsideGridWithHeading_getsHeadingAndPlaceholder {
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"grid",
        @"grid_options": @{@"columns": @6},
        @"cards": @[
            @{@"type": @"heading", @"heading": @"Living Room", @"icon": @"mdi:sofa"},
            @{@"type": @"custom:mushroom-template-card"} // no entity → unsupported
        ]
    }]];

    HADashboardConfigItem *placeholder = [self firstUnsupportedItemIn:config];
    XCTAssertNotNil(placeholder, @"Nested unsupported card inside a grid with a heading should still placeholder");
}

#pragma mark - Conditional cards

- (void)testConditionalCardWrappingUnsupportedInnerCard_producesPlaceholderWithConditions {
    NSArray *conditions = @[@{@"condition": @"state", @"entity": @"binary_sensor.door", @"state": @"on"}];
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"conditional",
        @"conditions": conditions,
        @"card": @{@"type": @"custom:bubble-card", @"card_type": @"separator"}
    }]];

    HADashboardConfigItem *placeholder = [self firstUnsupportedItemIn:config];
    XCTAssertNotNil(placeholder, @"A conditional card wrapping an unsupported card should still placeholder");
    XCTAssertEqual(placeholder.visibilityConditions.count, conditions.count,
        @"Conditions must be applied exactly once, not duplicated");
    XCTAssertEqualObjects(placeholder.visibilityConditions.firstObject, conditions.firstObject);
}

#pragma mark - Conditional conditions must apply exactly once (regression)
//
// _processCard:'s conditional branch used to set item.visibilityConditions =
// conditions directly on every item from the inner card, and then the public
// processCard: wrapper (which applies card[@"visibility"], falling back to
// card[@"conditions"] for a conditional card) appended the same array again
// via arrayByAddingObjectsFromArray:, doubling it. These use plain supported
// cards (not the unsupported-card placeholder) so they isolate the
// conditional-handling bug from the placeholder feature.

- (void)testSingleConditional_appliesConditionsExactlyOnce {
    NSArray *conditions = @[@{@"condition": @"state", @"entity": @"binary_sensor.door", @"state": @"on"}];
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"conditional",
        @"conditions": conditions,
        @"card": @{@"type": @"entity", @"entity": @"light.kitchen"}
    }]];

    HADashboardConfigItem *item = [self itemWithEntityId:@"light.kitchen" in:config];
    XCTAssertNotNil(item);
    XCTAssertEqual(item.visibilityConditions.count, conditions.count);
    XCTAssertEqualObjects(item.visibilityConditions.firstObject, conditions.firstObject);
}

- (void)testNestedConditional_bothConditionSetsPresentExactlyOnce {
    NSArray *outerConditions = @[@{@"condition": @"state", @"entity": @"binary_sensor.door", @"state": @"on"}];
    NSArray *innerConditions = @[@{@"condition": @"state", @"entity": @"input_boolean.armed", @"state": @"on"}];
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"conditional",
        @"conditions": outerConditions,
        @"card": @{
            @"type": @"conditional",
            @"conditions": innerConditions,
            @"card": @{@"type": @"entity", @"entity": @"light.kitchen"}
        }
    }]];

    HADashboardConfigItem *item = [self itemWithEntityId:@"light.kitchen" in:config];
    XCTAssertNotNil(item);
    XCTAssertEqual(item.visibilityConditions.count, outerConditions.count + innerConditions.count,
        @"Both the outer and inner condition sets must each be present exactly once (AND'd together)");

    NSUInteger outerMatches = 0, innerMatches = 0;
    for (NSDictionary *cond in item.visibilityConditions) {
        if ([cond isEqualToDictionary:outerConditions.firstObject]) outerMatches++;
        if ([cond isEqualToDictionary:innerConditions.firstObject]) innerMatches++;
    }
    XCTAssertEqual(outerMatches, (NSUInteger)1, @"Outer condition should appear exactly once");
    XCTAssertEqual(innerMatches, (NSUInteger)1, @"Inner condition should appear exactly once");
}

- (void)testConditionalWrappingStack_everyChildHasConditionsExactlyOnce {
    NSArray *conditions = @[@{@"condition": @"state", @"entity": @"binary_sensor.door", @"state": @"on"}];
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"conditional",
        @"conditions": conditions,
        @"card": @{
            @"type": @"horizontal-stack",
            @"cards": @[
                @{@"type": @"entity", @"entity": @"light.kitchen"},
                @{@"type": @"entity", @"entity": @"light.hallway"}
            ]
        }
    }]];

    for (NSString *entityId in @[@"light.kitchen", @"light.hallway"]) {
        HADashboardConfigItem *item = [self itemWithEntityId:entityId in:config];
        XCTAssertNotNil(item, @"%@ should be present", entityId);
        XCTAssertEqual(item.visibilityConditions.count, conditions.count,
            @"%@ should have the stack's wrapping conditions exactly once", entityId);
    }
}

#pragma mark - Malformed configs must never crash

- (void)testMalformedCard_missingType_doesNotCrash {
    // Note: a literal with a top-level comma (multi-key dict, multi-element
    // array) can't be passed directly as an XCTAssert macro argument — the
    // preprocessor only balances parentheses, not [] / {}, so it misparses
    // the comma as a macro-argument separator. Build the literal first.
    NSDictionary *card = @{@"foo": @"bar"};
    XCTAssertNoThrow([self configForCards:@[card]]);
}

- (void)testMalformedCard_typeIsNotAString_doesNotCrash {
    XCTAssertNoThrow([self configForCards:@[@{@"type": @42}]]);
}

- (void)testMalformedCard_cardsArrayHasNonDictionaryEntries_doesNotCrash {
    NSArray *cards = @[@"not-a-dictionary", @[@"also-not-a-dictionary"]];
    XCTAssertNoThrow([self configForCards:cards]);
}

- (void)testMalformedGrid_cardsFieldIsNotAnArray_doesNotCrash {
    NSDictionary *card = @{@"type": @"grid", @"cards": @"oops-a-string"};
    XCTAssertNoThrow([self configForCards:@[card]]);
}

- (void)testMalformedConditional_cardFieldMissing_doesNotCrash {
    NSDictionary *card = @{@"type": @"conditional", @"conditions": @[]};
    XCTAssertNoThrow([self configForCards:@[card]]);
}

#pragma mark - isNativelySupportedCustomCardType: table (GitHub #19)
//
// A custom:* card the parser maps natively or partially on purpose must
// never be flagged as a fallback — only a truly unmapped custom:* type gets
// the fallback-card-type badge.

- (void)testIsNativelySupportedCustomCardType_table {
    NSDictionary<NSString *, NSNumber *> *table = @{
        // Natively/partially mapped -> YES
        @"custom:advanced-camera-card": @YES,
        @"custom:frigate-camera-card": @YES,
        @"custom:mini-graph-card": @YES,
        @"custom:badge-card": @YES,
        @"custom:mushroom-chips-card": @YES,
        @"custom:clock-weather-card": @YES,
        // Unmapped -> NO
        @"custom:bubble-card": @NO,
        @"custom:mushroom-entity-card": @NO,
        @"custom:mushroom-light-card": @NO,
        @"custom:mushroom-template-card": @NO,
        @"custom:button-card": @NO,
        // Not a custom:* type at all -> NO (built-in cards are never "unsupported")
        @"entities": @NO,
        @"tile": @NO,
        @"mini-graph-card": @NO, // missing "custom:" prefix
    };
    for (NSString *type in table) {
        BOOL expected = table[type].boolValue;
        XCTAssertEqual([HALovelaceParser isNativelySupportedCustomCardType:type], expected,
            @"%@ should be %@", type, expected ? @"natively supported" : @"a fallback type");
    }
}

#pragma mark - fallbackCardType badge (GitHub #19)
//
// An unmapped custom:* card with an "entity"/"entities" key produced zero
// placeholders before this feature (it extracts entities, so it never hit
// _handleUnsupportedCard) and rendered generically with no visible marker.
// It should still render generically (never a placeholder), but the
// generated item(s) must carry fallbackCardType so the cell can badge it.

- (void)testUnmappedCustomCardWithEntity_setsFallbackCardTypeOnGenericItem {
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"custom:mushroom-entity-card",
        @"entity": @"sensor.downstairs_temperature"
    }]];

    HADashboardConfigItem *item = [self itemWithEntityId:@"sensor.downstairs_temperature" in:config];
    XCTAssertNotNil(item, @"An unmapped custom card with an entity key must still render generically, not vanish");
    XCTAssertEqualObjects(item.fallbackCardType, @"custom:mushroom-entity-card");
    XCTAssertNil([self firstUnsupportedItemIn:config], @"Must never ALSO produce an unsupported-card placeholder");
}

- (void)testUnmappedCustomCardWithEntities_setsFallbackCardTypeOnEveryGenericItem {
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"custom:bubble-card",
        @"card_type": @"climate-buttons",
        @"entities": @[@"climate.living_room", @"climate.bedroom"]
    }]];

    for (NSString *entityId in @[@"climate.living_room", @"climate.bedroom"]) {
        HADashboardConfigItem *item = [self itemWithEntityId:entityId in:config];
        XCTAssertNotNil(item, @"%@ should be present", entityId);
        XCTAssertEqualObjects(item.fallbackCardType, @"custom:bubble-card");
    }
}

- (void)testNativelySupportedCustomCard_doesNotSetFallbackCardType {
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"custom:mini-graph-card",
        @"entities": @[@"sensor.downstairs_temperature"]
    }]];

    HADashboardConfigItem *item = config.items.firstObject;
    XCTAssertNotNil(item);
    XCTAssertNil(item.fallbackCardType, @"A natively-mapped custom card must never be badged as a fallback");
}

- (void)testBuiltInCard_neverSetsFallbackCardType {
    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"entity",
        @"entity": @"sensor.downstairs_temperature"
    }]];

    HADashboardConfigItem *item = [self itemWithEntityId:@"sensor.downstairs_temperature" in:config];
    XCTAssertNotNil(item);
    XCTAssertNil(item.fallbackCardType, @"A built-in (non custom:*) card is never a fallback");
}

- (void)testUnmappedCustomCardWithEntity_toggleOff_doesNotSetFallbackCardType {
    // Mirrors the placeholder toggle: OFF restores pre-feature behaviour —
    // generic rendering stays, but with no visible marker at all.
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:HAShowUnsupportedCardsDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    HADashboardConfig *config = [self configForCards:@[@{
        @"type": @"custom:mushroom-entity-card",
        @"entity": @"sensor.downstairs_temperature"
    }]];

    HADashboardConfigItem *item = [self itemWithEntityId:@"sensor.downstairs_temperature" in:config];
    XCTAssertNotNil(item, @"Generic rendering must stay even with the toggle off");
    XCTAssertNil(item.fallbackCardType, @"Toggle OFF must hide the badge too (fallbackCardType unset)");
}

@end
