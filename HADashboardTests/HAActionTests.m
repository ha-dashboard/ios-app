#import <XCTest/XCTest.h>
#import "HAAction.h"
#import "HAEntity.h"
#import "HASnapshotTestHelpers.h"

@interface HAActionTests : XCTestCase
@end

@implementation HAActionTests

#pragma mark - Parsing from Dictionary

- (void)testParseFullDictionary {
    NSDictionary *dict = @{
        @"action": @"navigate",
        @"navigation_path": @"/lovelace/rooms",
        @"confirmation": @{@"text": @"Navigate?"},
    };
    HAAction *action = [HAAction actionFromDictionary:dict];
    XCTAssertNotNil(action);
    XCTAssertEqualObjects(action.action, @"navigate");
    XCTAssertEqualObjects(action.navigationPath, @"/lovelace/rooms");
    XCTAssertNotNil(action.confirmation);
    XCTAssertEqualObjects(((NSDictionary *)action.confirmation)[@"text"], @"Navigate?");
}

- (void)testParsePerformAction {
    NSDictionary *dict = @{
        @"action": @"perform-action",
        @"perform_action": @"light.turn_on",
        @"data": @{@"brightness_pct": @(100)},
        @"target": @{@"entity_id": @"light.bedroom"},
    };
    HAAction *action = [HAAction actionFromDictionary:dict];
    XCTAssertNotNil(action);
    XCTAssertEqualObjects(action.action, HAActionTypePerformAction);
    XCTAssertEqualObjects(action.performAction, @"light.turn_on");
    XCTAssertEqualObjects(action.data[@"brightness_pct"], @(100));
    XCTAssertEqualObjects(action.target[@"entity_id"], @"light.bedroom");
}

- (void)testParseLegacyServiceKeys {
    NSDictionary *dict = @{
        @"action": @"call-service",
        @"service": @"media_player.play_media",
        @"service_data": @{@"media_content_id": @"playlist"},
    };
    HAAction *action = [HAAction actionFromDictionary:dict];
    XCTAssertNotNil(action);
    XCTAssertEqualObjects(action.action, HAActionTypeCallService);
    XCTAssertEqualObjects(action.performAction, @"media_player.play_media");
    XCTAssertEqualObjects(action.data[@"media_content_id"], @"playlist");
}

- (void)testPerformActionKeyOverridesLegacyService {
    NSDictionary *dict = @{
        @"action": @"perform-action",
        @"perform_action": @"light.turn_on",
        @"service": @"light.toggle", // legacy — should be ignored
    };
    HAAction *action = [HAAction actionFromDictionary:dict];
    XCTAssertEqualObjects(action.performAction, @"light.turn_on");
}

- (void)testParseURLAction {
    NSDictionary *dict = @{
        @"action": @"url",
        @"url_path": @"https://example.com",
    };
    HAAction *action = [HAAction actionFromDictionary:dict];
    XCTAssertEqualObjects(action.action, HAActionTypeURL);
    XCTAssertEqualObjects(action.urlPath, @"https://example.com");
}

- (void)testParseEntityOverride {
    NSDictionary *dict = @{
        @"action": @"more-info",
        @"entity": @"sensor.temperature",
    };
    HAAction *action = [HAAction actionFromDictionary:dict];
    XCTAssertEqualObjects(action.action, HAActionTypeMoreInfo);
    XCTAssertEqualObjects(action.entityOverride, @"sensor.temperature");
}

- (void)testParseConfirmationBool {
    NSDictionary *dict = @{
        @"action": @"toggle",
        @"confirmation": @YES,
    };
    HAAction *action = [HAAction actionFromDictionary:dict];
    XCTAssertNotNil(action.confirmation);
    XCTAssertEqualObjects(action.confirmation, @YES);
}

- (void)testParseConfirmationDict {
    NSDictionary *dict = @{
        @"action": @"toggle",
        @"confirmation": @{@"text": @"Are you sure?"},
    };
    HAAction *action = [HAAction actionFromDictionary:dict];
    XCTAssertTrue([action.confirmation isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(((NSDictionary *)action.confirmation)[@"text"], @"Are you sure?");
}

- (void)testParseNilDictionary {
    HAAction *action = [HAAction actionFromDictionary:nil];
    XCTAssertNil(action);
}

- (void)testParseEmptyDictionary {
    HAAction *action = [HAAction actionFromDictionary:@{}];
    XCTAssertNil(action, @"Dictionary without 'action' key should return nil");
}

- (void)testParseNonDictionary {
    HAAction *action = [HAAction actionFromDictionary:(NSDictionary *)@"not a dict"];
    XCTAssertNil(action);
}

- (void)testParseDictionaryMissingAction {
    NSDictionary *dict = @{@"navigation_path": @"/lovelace/rooms"};
    HAAction *action = [HAAction actionFromDictionary:dict];
    XCTAssertNil(action, @"Missing 'action' key should return nil");
}

#pragma mark - Default Actions

- (void)testDefaultTapActionForToggleableEntity {
    HAEntity *light = [HASnapshotTestHelpers lightEntityOnBrightness];
    HAAction *action = [HAAction defaultTapActionForEntity:light];
    XCTAssertEqualObjects(action.action, HAActionTypeToggle);
}

- (void)testDefaultTapActionForSwitchEntity {
    HAEntity *sw = [HASnapshotTestHelpers switchEntityOn];
    HAAction *action = [HAAction defaultTapActionForEntity:sw];
    XCTAssertEqualObjects(action.action, HAActionTypeToggle);
}

// Default tap action for non-toggle, non-actionable entities was changed from
// more-info to none by 32ba3c7 ("fix: script button full-area tap + long-press
// for entity detail"): detail view now only opens on long-press, so tap does
// nothing for entities that don't toggle or activate.
- (void)testDefaultTapActionForNonToggleableEntity {
    HAEntity *sensor = [HASnapshotTestHelpers sensorTemperature];
    HAAction *action = [HAAction defaultTapActionForEntity:sensor];
    XCTAssertEqualObjects(action.action, HAActionTypeNone);
}

- (void)testDefaultTapActionForLockIsNone {
    // Lock is NOT in HA's DOMAINS_TOGGLE and isn't an actionable domain either
    // (scene/script/button) — per 32ba3c7, tap does nothing; long-press for more-info.
    HAEntity *lock = [HASnapshotTestHelpers lockLocked];
    HAAction *action = [HAAction defaultTapActionForEntity:lock];
    XCTAssertEqualObjects(action.action, HAActionTypeNone);
}

- (void)testDefaultTapActionForCoverIsNone {
    // Cover is NOT in HA's DOMAINS_TOGGLE and isn't actionable — per 32ba3c7, tap does nothing.
    HAEntity *cover = [HASnapshotTestHelpers coverEntityOpenShutter];
    HAAction *action = [HAAction defaultTapActionForEntity:cover];
    XCTAssertEqualObjects(action.action, HAActionTypeNone);
}

- (void)testDefaultTapActionForSceneIsToggle {
    // Scene is NOT in DOMAINS_TOGGLE, but 32ba3c7 explicitly keeps scene/script/button
    // "actionable": they still activate on tap (modeled as HAActionTypeToggle), unlike
    // other non-toggle domains which now get HAActionTypeNone.
    HAEntity *scene = [HASnapshotTestHelpers sceneDefault];
    HAAction *action = [HAAction defaultTapActionForEntity:scene];
    XCTAssertEqualObjects(action.action, HAActionTypeToggle);
}

- (void)testDefaultTapActionForNilEntity {
    // No entity to toggle, activate, or show more-info for — falls through to the
    // same "nothing happens on tap" default as any other non-actionable entity.
    HAAction *action = [HAAction defaultTapActionForEntity:nil];
    XCTAssertEqualObjects(action.action, HAActionTypeNone);
}

- (void)testDefaultHoldAction {
    HAAction *action = [HAAction defaultHoldAction];
    XCTAssertEqualObjects(action.action, HAActionTypeMoreInfo);
}

#pragma mark - isNone

- (void)testIsNoneTrue {
    NSDictionary *dict = @{@"action": @"none"};
    HAAction *action = [HAAction actionFromDictionary:dict];
    XCTAssertTrue([action isNone]);
}

- (void)testIsNoneFalse {
    NSDictionary *dict = @{@"action": @"toggle"};
    HAAction *action = [HAAction actionFromDictionary:dict];
    XCTAssertFalse([action isNone]);
}

#pragma mark - All Action Types Parse

- (void)testAllActionTypesParse {
    NSArray *types = @[@"toggle", @"more-info", @"call-service", @"perform-action",
                       @"navigate", @"url", @"none"];
    for (NSString *type in types) {
        HAAction *action = [HAAction actionFromDictionary:@{@"action": type}];
        XCTAssertNotNil(action, @"Action type '%@' should parse", type);
        XCTAssertEqualObjects(action.action, type);
    }
}

@end
