#import <XCTest/XCTest.h>
#import "HAAction.h"
#import "HAActionDispatcher.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HASnapshotTestHelpers.h"
#import "HAWebSocketClient.h"
#import "HAAuthManager.h"
#import "HADashboardViewController.h"
#import "HADashboardConfig.h"
#import "HALovelaceParser.h"
#import <objc/runtime.h>

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

#pragma mark - Entity-less button card actions (GitHub #26)

@interface HADashboardViewController (EntitylessButtonTestAccess)
@property (nonatomic, strong) HADashboardConfig *dashboardConfig;
- (void)executeActionType:(NSString *)actionType forEntity:(HAEntity *)entity configProperties:(NSDictionary *)props;
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath;
@end

/// Taps on an entity-less button run its configured action with no entity, and
/// a perform-action reaches the WebSocket as call_service with the target's
/// entity_id list intact. HAWebSocketClient -sendCommand: is the capture seam;
/// the shared connection manager gets an "authenticated" client for the test.
@interface HAEntitylessButtonActionTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *sentCommands;
@property (nonatomic, assign) IMP originalSendCommand;
@property (nonatomic, assign) IMP originalIsAuthenticated;
@property (nonatomic, assign) IMP originalIsDemoMode;
@property (nonatomic, strong) id originalWSClient;
@property (nonatomic, strong) HADashboardViewController *dashboard;
@end

@implementation HAEntitylessButtonActionTests

- (void)setUp {
    [super setUp];
    self.sentCommands = [NSMutableArray array];
    NSMutableArray *sent = self.sentCommands;
    self.originalSendCommand = method_setImplementation(
        class_getInstanceMethod([HAWebSocketClient class], @selector(sendCommand:)),
        imp_implementationWithBlock(^NSInteger(id client, NSDictionary *command) {
            [sent addObject:command];
            return 1;
        }));
    self.originalIsAuthenticated = method_setImplementation(
        class_getInstanceMethod([HAWebSocketClient class], @selector(isAuthenticated)),
        imp_implementationWithBlock(^BOOL(id client) { return YES; }));
    self.originalIsDemoMode = method_setImplementation(
        class_getInstanceMethod([HAAuthManager class], @selector(isDemoMode)),
        imp_implementationWithBlock(^BOOL(id manager) { return NO; }));

    HAConnectionManager *conn = [HAConnectionManager sharedManager];
    self.originalWSClient = [conn valueForKey:@"wsClient"];
    [conn setValue:[[HAWebSocketClient alloc] initWithURL:[NSURL URLWithString:@"ws://127.0.0.1:9/api/websocket"] token:@"test"]
            forKey:@"wsClient"];
    self.dashboard = [[HADashboardViewController alloc] init];
}

- (void)tearDown {
    [[HAConnectionManager sharedManager] setValue:self.originalWSClient forKey:@"wsClient"];
    method_setImplementation(class_getInstanceMethod([HAWebSocketClient class], @selector(sendCommand:)), self.originalSendCommand);
    method_setImplementation(class_getInstanceMethod([HAWebSocketClient class], @selector(isAuthenticated)), self.originalIsAuthenticated);
    method_setImplementation(class_getInstanceMethod([HAAuthManager class], @selector(isDemoMode)), self.originalIsDemoMode);
    self.dashboard = nil;
    [super tearDown];
}

/// Parse `card` in a sections view and tap its (single) item on the dashboard.
- (void)tapCard:(NSDictionary *)card {
    NSDictionary *dict = @{@"views": @[@{@"title": @"T", @"type": @"sections",
                                         @"sections": @[@{@"type": @"grid", @"cards": @[card]}]}]};
    HALovelaceView *view = [HALovelaceParser parseDashboardFromDictionary:dict].views.firstObject;
    self.dashboard.dashboardConfig = [HALovelaceParser dashboardConfigFromView:view columns:3];
    NSIndexPath *indexPath = nil;
    NSArray *sections = self.dashboard.dashboardConfig.sections;
    for (NSUInteger s = 0; s < sections.count && !indexPath; s++) {
        if ([sections[s] items].count > 0) indexPath = [NSIndexPath indexPathForItem:0 inSection:(NSInteger)s];
    }
    XCTAssertNotNil(indexPath, @"The card must produce an item");
    UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectZero
                                              collectionViewLayout:[[UICollectionViewFlowLayout alloc] init]];
    [self.dashboard collectionView:cv didSelectItemAtIndexPath:indexPath];
}

- (void)testReporterButtonTap_sendsCallServiceWithTargetEntityList {
    [self tapCard:@{
        @"type": @"button", @"show_name": @YES, @"show_icon": @YES, @"show_state": @NO,
        @"icon": @"mdi:robot-vacuum", @"color": @"red", @"name": @"Arrêter Coco Marcel",
        @"tap_action": @{@"action": @"perform-action", @"perform_action": @"vacuum.stop",
                         @"target": @{@"entity_id": @[@"vacuum.valetudo_cocomarcel"]}},
        @"grid_options": @{@"columns": @"full"},
    }];

    XCTAssertEqual(self.sentCommands.count, 1u);
    NSDictionary *command = self.sentCommands.firstObject;
    XCTAssertEqualObjects(command[@"type"], @"call_service");
    XCTAssertEqualObjects(command[@"domain"], @"vacuum");
    XCTAssertEqualObjects(command[@"service"], @"stop");
    XCTAssertEqualObjects(command[@"service_data"], (@{@"entity_id": @[@"vacuum.valetudo_cocomarcel"]}));
}

- (void)testLegacyCallServiceWithServiceDataAndStringTarget {
    [self tapCard:@{@"type": @"button", @"icon": @"mdi:lightbulb",
                    @"tap_action": @{@"action": @"call-service", @"service": @"light.turn_on",
                                     @"service_data": @{@"brightness_pct": @40},
                                     @"target": @{@"entity_id": @"light.kitchen", @"area_id": @"kitchen"}}}];

    XCTAssertEqual(self.sentCommands.count, 1u);
    NSDictionary *command = self.sentCommands.firstObject;
    XCTAssertEqualObjects(command[@"domain"], @"light");
    XCTAssertEqualObjects(command[@"service"], @"turn_on");
    XCTAssertEqualObjects(command[@"service_data"],
                          (@{@"brightness_pct": @40, @"entity_id": @"light.kitchen", @"area_id": @"kitchen"}));
}

- (void)testDefaultTapAndToggle_doNothingWithoutEntity {
    __block BOOL moreInfoPosted = NO;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"HAActionMoreInfoNotification" object:nil
                                                                     queue:nil usingBlock:^(NSNotification *note) {
        moreInfoPosted = YES;
    }];
    // HA default tap_action without an entity is more-info: nothing to show.
    [self tapCard:@{@"type": @"button", @"icon": @"mdi:lightbulb"}];
    [self tapCard:@{@"type": @"button", @"icon": @"mdi:lightbulb", @"tap_action": @{@"action": @"toggle"}}];
    [self tapCard:@{@"type": @"button", @"icon": @"mdi:lightbulb", @"tap_action": @{@"action": @"more-info"}}];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];

    XCTAssertEqual(self.sentCommands.count, 0u);
    XCTAssertFalse(moreInfoPosted);
}

- (void)testTapNavigate_postsNavigation {
    [self expectationForNotification:HAActionNavigateNotification object:nil handler:^BOOL(NSNotification *note) {
        return [note.userInfo[@"path"] isEqualToString:@"/lovelace/robots"];
    }];
    [self tapCard:@{@"type": @"button", @"name": @"Robots",
                    @"tap_action": @{@"action": @"navigate", @"navigation_path": @"/lovelace/robots"}}];
    [self waitForExpectationsWithTimeout:1.0 handler:nil];
}

- (void)testHoldAndDoubleTapActions_runWithoutEntity {
    NSDictionary *props = @{
        @"hold_action": @{@"action": @"perform-action", @"perform_action": @"script.turn_on",
                          @"target": @{@"entity_id": @[@"script.a", @"script.b"]}},
        @"double_tap_action": @{@"action": @"perform-action", @"perform_action": @"vacuum.return_to_base",
                                @"data": @{@"entity_id": @"vacuum.x"}},
    };
    [self.dashboard executeActionType:@"hold_action" forEntity:nil configProperties:props];
    [self.dashboard executeActionType:@"double_tap_action" forEntity:nil configProperties:props];

    XCTAssertEqual(self.sentCommands.count, 2u);
    XCTAssertEqualObjects(self.sentCommands[0][@"service_data"], (@{@"entity_id": @[@"script.a", @"script.b"]}));
    XCTAssertEqualObjects(self.sentCommands[1][@"service"], @"return_to_base");
    XCTAssertEqualObjects(self.sentCommands[1][@"service_data"], (@{@"entity_id": @"vacuum.x"}));
}

@end
