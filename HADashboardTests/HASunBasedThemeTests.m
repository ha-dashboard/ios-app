#import <XCTest/XCTest.h>
#import "HASunBasedTheme.h"
#import "HATheme.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"

/// Unit tests for HASunBasedTheme — verifies that the sun entity drives
/// light/dark switching on iOS 9-12 (where there is no system dark mode).
///
/// These tests mock the sun.sun entity by posting entity-update notifications
/// directly, avoiding any real HA connection.
@interface HASunBasedThemeTests : XCTestCase
@property (nonatomic, strong) XCTestExpectation *themeChangeExpectation;
@end

@implementation HASunBasedThemeTests

- (void)setUp {
    [super setUp];
    // Ensure Auto mode so the sun-based logic is active
    [HATheme setCurrentMode:HAThemeModeAuto];
}

- (void)tearDown {
    [[HASunBasedTheme sharedInstance] stop];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super tearDown];
}

#pragma mark - Helpers

/// Create a fake sun.sun entity with the given state and attributes.
- (HAEntity *)sunEntityWithState:(NSString *)state
                      nextRising:(NSString *)rising
                     nextSetting:(NSString *)setting {
    HAEntity *sun = [[HAEntity alloc] init];
    sun.entityId = @"sun.sun";
    sun.state = state;
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    if (rising) attrs[@"next_rising"] = rising;
    if (setting) attrs[@"next_setting"] = setting;
    attrs[@"elevation"] = @(10.0);
    sun.attributes = attrs;
    return sun;
}

/// Post an entity-update notification as if the connection manager sent it.
- (void)postEntityUpdate:(HAEntity *)entity {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:HAConnectionManagerEntityDidUpdateNotification
                      object:nil
                    userInfo:@{@"entity": entity}];
}

#pragma mark - Tests

- (void)testSunBelowHorizonReturnsDark {
    // Verify that effectiveDarkMode returns YES when sun is below horizon.
    // On iOS 13+ this test is a no-op since sun-based theme defers to system.
    if (@available(iOS 13.0, *)) {
        // HASunBasedTheme.start no-ops on iOS 13+, so isSunBelowHorizon stays NO.
        // effectiveDarkMode uses UITraitCollection on iOS 13+ — we can't test
        // the sun path here. Just verify it doesn't crash.
        XCTAssertNotNil([HASunBasedTheme sharedInstance]);
        return;
    }

    HASunBasedTheme *theme = [HASunBasedTheme sharedInstance];
    [theme start];

    HAEntity *sun = [self sunEntityWithState:@"below_horizon"
                                  nextRising:@"2026-03-01T06:42:00+00:00"
                                 nextSetting:nil];
    [self postEntityUpdate:sun];

    XCTAssertTrue(theme.isSunBelowHorizon,
                  @"isSunBelowHorizon should be YES when sun state is below_horizon");
}

- (void)testSunAboveHorizonReturnsLight {
    if (@available(iOS 13.0, *)) {
        return; // Sun-based theme defers to system on iOS 13+
    }

    HASunBasedTheme *theme = [HASunBasedTheme sharedInstance];
    [theme start];

    HAEntity *sun = [self sunEntityWithState:@"above_horizon"
                                  nextRising:nil
                                 nextSetting:@"2026-02-28T17:32:00+00:00"];
    [self postEntityUpdate:sun];

    XCTAssertFalse(theme.isSunBelowHorizon,
                   @"isSunBelowHorizon should be NO when sun state is above_horizon");
}

- (void)testTransitionPostsNotification {
    if (@available(iOS 13.0, *)) {
        return; // Sun-based theme defers to system on iOS 13+
    }

    HASunBasedTheme *theme = [HASunBasedTheme sharedInstance];
    [theme start];

    // Start with above_horizon
    HAEntity *sunDay = [self sunEntityWithState:@"above_horizon"
                                    nextRising:nil
                                   nextSetting:@"2026-02-28T17:32:00+00:00"];
    [self postEntityUpdate:sunDay];
    XCTAssertFalse(theme.isSunBelowHorizon);

    // Expect a theme change notification when transitioning to below_horizon
    self.themeChangeExpectation = [self expectationForNotification:HAThemeDidChangeNotification
                                                           object:nil
                                                          handler:nil];

    HAEntity *sunNight = [self sunEntityWithState:@"below_horizon"
                                       nextRising:@"2026-03-01T06:42:00+00:00"
                                      nextSetting:nil];
    [self postEntityUpdate:sunNight];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertTrue(theme.isSunBelowHorizon,
                  @"Should have transitioned to dark after sun went below horizon");
}

- (void)testNoNotificationWhenStateUnchanged {
    if (@available(iOS 13.0, *)) {
        return;
    }

    HASunBasedTheme *theme = [HASunBasedTheme sharedInstance];
    [theme start];

    // Set initial state
    HAEntity *sun1 = [self sunEntityWithState:@"above_horizon"
                                   nextRising:nil
                                  nextSetting:@"2026-02-28T17:32:00+00:00"];
    [self postEntityUpdate:sun1];

    // Post same state again — should NOT fire notification
    __block BOOL notificationFired = NO;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:HAThemeDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *n) { notificationFired = YES; }];

    HAEntity *sun2 = [self sunEntityWithState:@"above_horizon"
                                   nextRising:nil
                                  nextSetting:@"2026-02-28T17:32:00+00:00"];
    [self postEntityUpdate:sun2];

    // Give a small delay for any async delivery
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    XCTAssertFalse(notificationFired,
                   @"Should not post notification when sun state hasn't changed");
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testStopCancelsTimer {
    if (@available(iOS 13.0, *)) {
        return;
    }

    HASunBasedTheme *theme = [HASunBasedTheme sharedInstance];
    [theme start];

    HAEntity *sun = [self sunEntityWithState:@"above_horizon"
                                  nextRising:nil
                                 nextSetting:@"2026-02-28T17:32:00+00:00"];
    [self postEntityUpdate:sun];

    [theme stop];

    // After stop, posting updates should have no effect
    __block BOOL notificationFired = NO;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:HAThemeDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *n) { notificationFired = YES; }];

    HAEntity *sunNight = [self sunEntityWithState:@"below_horizon"
                                       nextRising:@"2026-03-01T06:42:00+00:00"
                                      nextSetting:nil];
    [self postEntityUpdate:sunNight];

    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    XCTAssertFalse(notificationFired,
                   @"Should not respond to entity updates after stop");
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testNonAutoModeIgnoresSunEntity {
    if (@available(iOS 13.0, *)) {
        return;
    }

    [HATheme setCurrentMode:HAThemeModeDark];
    HASunBasedTheme *theme = [HASunBasedTheme sharedInstance];
    [theme start];

    HAEntity *sun = [self sunEntityWithState:@"above_horizon"
                                  nextRising:nil
                                 nextSetting:@"2026-02-28T17:32:00+00:00"];
    [self postEntityUpdate:sun];

    // In Dark mode, sun entity should be ignored
    XCTAssertFalse(theme.isSunBelowHorizon,
                   @"Sun-based theme should not activate in non-Auto mode");

    // Restore
    [HATheme setCurrentMode:HAThemeModeAuto];
}

@end
