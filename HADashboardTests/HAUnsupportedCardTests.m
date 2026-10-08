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

@end
