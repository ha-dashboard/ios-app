#import <XCTest/XCTest.h>
#import "HAAction.h"
#import "HAActionDispatcher.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HASnapshotTestHelpers.h"

@interface HAActionDispatcherTests : XCTestCase
@property (nonatomic, strong) XCTestExpectation *notificationExpectation;
@property (nonatomic, strong) NSNotification *receivedNotification;
@end

@implementation HAActionDispatcherTests

- (void)tearDown {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.notificationExpectation = nil;
    self.receivedNotification = nil;
    [super tearDown];
}

#pragma mark - Toggle

- (void)testToggleActionCallsToggleService {
    // Toggle action for a light entity should invoke toggleService.
    // We can't easily verify the service call without mocking HAConnectionManager,
    // but we can verify the action doesn't crash and the entity resolves correctly.
    HAEntity *light = [HASnapshotTestHelpers lightEntityOnBrightness];
    HAAction *action = [HAAction actionFromDictionary:@{@"action": @"toggle"}];
    XCTAssertNoThrow([[HAActionDispatcher sharedDispatcher] executeAction:action
                                                               forEntity:light
                                                      fromViewController:[[UIViewController alloc] init]]);
}

- (void)testToggleActionWithNilEntity {
    HAAction *action = [HAAction actionFromDictionary:@{@"action": @"toggle"}];
    XCTAssertNoThrow([[HAActionDispatcher sharedDispatcher] executeAction:action
                                                               forEntity:nil
                                                      fromViewController:[[UIViewController alloc] init]]);
}

#pragma mark - More Info

- (void)testMoreInfoPostsNotification {
    HAEntity *sensor = [HASnapshotTestHelpers sensorTemperature];
    self.notificationExpectation = [self expectationForNotification:@"HAActionMoreInfoNotification"
                                                            object:nil
                                                           handler:^BOOL(NSNotification *note) {
        HAEntity *entity = note.userInfo[@"entity"];
        return [entity.entityId isEqualToString:sensor.entityId];
    }];

    HAAction *action = [HAAction actionFromDictionary:@{@"action": @"more-info"}];
    [[HAActionDispatcher sharedDispatcher] executeAction:action
                                              forEntity:sensor
                                     fromViewController:[[UIViewController alloc] init]];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testMoreInfoWithEntityOverride {
    HAEntity *sensor = [HASnapshotTestHelpers sensorTemperature];
    HAEntity *light = [HASnapshotTestHelpers lightEntityOnBrightness];

    // Register the override entity in the connection manager's cache
    // Since we can't easily mock this, we verify the notification fires.
    // The entity override lookup will return nil (not connected), so it falls back to primary entity.
    self.notificationExpectation = [self expectationForNotification:@"HAActionMoreInfoNotification"
                                                            object:nil
                                                           handler:^BOOL(NSNotification *note) {
        // Should get the primary entity since override lookup fails
        return note.userInfo[@"entity"] != nil;
    }];

    HAAction *action = [HAAction actionFromDictionary:@{
        @"action": @"more-info",
        @"entity": light.entityId,
    }];
    [[HAActionDispatcher sharedDispatcher] executeAction:action
                                              forEntity:sensor
                                     fromViewController:[[UIViewController alloc] init]];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

#pragma mark - Navigate

- (void)testNavigatePostsNotificationWithPath {
    self.notificationExpectation = [self expectationForNotification:HAActionNavigateNotification
                                                            object:nil
                                                           handler:^BOOL(NSNotification *note) {
        return [note.userInfo[@"path"] isEqualToString:@"/lovelace/rooms"];
    }];

    HAAction *action = [HAAction actionFromDictionary:@{
        @"action": @"navigate",
        @"navigation_path": @"/lovelace/rooms",
    }];
    [[HAActionDispatcher sharedDispatcher] executeAction:action
                                              forEntity:nil
                                     fromViewController:[[UIViewController alloc] init]];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testNavigateWithNilPathDoesNothing {
    // Listen for notification — it should NOT fire
    __block BOOL notificationReceived = NO;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:HAActionNavigateNotification
                                                                    object:nil
                                                                     queue:nil
                                                                usingBlock:^(NSNotification *note) {
        notificationReceived = YES;
    }];

    HAAction *action = [HAAction actionFromDictionary:@{@"action": @"navigate"}];
    [[HAActionDispatcher sharedDispatcher] executeAction:action
                                              forEntity:nil
                                     fromViewController:[[UIViewController alloc] init]];

    // Give a moment for async delivery
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertFalse(notificationReceived, @"Navigate with nil path should not post notification");

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

#pragma mark - URL

- (void)testURLActionDoesNotCrashWithValidURL {
    HAAction *action = [HAAction actionFromDictionary:@{
        @"action": @"url",
        @"url_path": @"https://example.com",
    }];
    // Can't easily verify openURL in tests, but verify no crash
    XCTAssertNoThrow([[HAActionDispatcher sharedDispatcher] executeAction:action
                                                               forEntity:nil
                                                      fromViewController:[[UIViewController alloc] init]]);
}

- (void)testURLActionWithNilPathDoesNothing {
    HAAction *action = [HAAction actionFromDictionary:@{@"action": @"url"}];
    XCTAssertNoThrow([[HAActionDispatcher sharedDispatcher] executeAction:action
                                                               forEntity:nil
                                                      fromViewController:[[UIViewController alloc] init]]);
}

#pragma mark - None

- (void)testNoneActionDoesNothing {
    HAAction *action = [HAAction actionFromDictionary:@{@"action": @"none"}];

    // Verify no notifications are posted
    __block BOOL anyNotification = NO;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:nil
                                                                    object:nil
                                                                     queue:nil
                                                                usingBlock:^(NSNotification *note) {
        if ([note.name hasPrefix:@"HAAction"]) {
            anyNotification = YES;
        }
    }];

    [[HAActionDispatcher sharedDispatcher] executeAction:action
                                              forEntity:[HASnapshotTestHelpers lightEntityOnBrightness]
                                     fromViewController:[[UIViewController alloc] init]];

    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertFalse(anyNotification, @"None action should not post any notifications");

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testNilActionDoesNothing {
    XCTAssertNoThrow([[HAActionDispatcher sharedDispatcher] executeAction:nil
                                                               forEntity:nil
                                                      fromViewController:[[UIViewController alloc] init]]);
}

#pragma mark - Call Service

- (void)testCallServiceParsesDomainAndService {
    // Verify the action parses "domain.service" correctly.
    // We can't verify the actual service call without mocking, but we can verify
    // the action doesn't crash and the service string is parsed.
    HAAction *action = [HAAction actionFromDictionary:@{
        @"action": @"call-service",
        @"perform_action": @"light.turn_on",
        @"data": @{@"brightness_pct": @(50)},
    }];
    XCTAssertEqualObjects(action.performAction, @"light.turn_on");

    // Execute — should not crash even without a real connection
    HAEntity *light = [HASnapshotTestHelpers lightEntityOnBrightness];
    XCTAssertNoThrow([[HAActionDispatcher sharedDispatcher] executeAction:action
                                                               forEntity:light
                                                      fromViewController:[[UIViewController alloc] init]]);
}

- (void)testCallServiceMergesTargetAndData {
    HAAction *action = [HAAction actionFromDictionary:@{
        @"action": @"perform-action",
        @"perform_action": @"light.turn_on",
        @"data": @{@"brightness_pct": @(100)},
        @"target": @{@"entity_id": @"light.bedroom"},
    }];
    XCTAssertNotNil(action.data);
    XCTAssertNotNil(action.target);
    XCTAssertEqualObjects(action.target[@"entity_id"], @"light.bedroom");

    // Execute — should not crash
    XCTAssertNoThrow([[HAActionDispatcher sharedDispatcher] executeAction:action
                                                               forEntity:nil
                                                      fromViewController:[[UIViewController alloc] init]]);
}

- (void)testCallServiceWithInvalidServiceStringDoesNotCrash {
    HAAction *action = [HAAction actionFromDictionary:@{
        @"action": @"call-service",
        @"perform_action": @"invalid_no_dot",
    }];
    XCTAssertNoThrow([[HAActionDispatcher sharedDispatcher] executeAction:action
                                                               forEntity:nil
                                                      fromViewController:[[UIViewController alloc] init]]);
}

- (void)testCallServiceWithNilPerformActionDoesNotCrash {
    HAAction *action = [HAAction actionFromDictionary:@{@"action": @"call-service"}];
    XCTAssertNoThrow([[HAActionDispatcher sharedDispatcher] executeAction:action
                                                               forEntity:nil
                                                      fromViewController:[[UIViewController alloc] init]]);
}

#pragma mark - Unknown Action Type

- (void)testUnknownActionTypeDoesNotCrash {
    HAAction *action = [HAAction actionFromDictionary:@{@"action": @"assist"}];
    XCTAssertNoThrow([[HAActionDispatcher sharedDispatcher] executeAction:action
                                                               forEntity:nil
                                                      fromViewController:[[UIViewController alloc] init]]);
}

#pragma mark - Singleton

- (void)testSharedDispatcherIsSingleton {
    HAActionDispatcher *a = [HAActionDispatcher sharedDispatcher];
    HAActionDispatcher *b = [HAActionDispatcher sharedDispatcher];
    XCTAssertEqual(a, b);
}

@end
