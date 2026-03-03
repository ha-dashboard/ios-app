#import <XCTest/XCTest.h>
#import "HADeviceRegistration.h"
#import "HASensorReporter.h"
#import "HARemoteCommandHandler.h"
#import "HADeviceIntegrationManager.h"
#import "HATheme.h"
#import "HAAuthManager.h"

#pragma mark - HADeviceRegistration Tests

@interface HADeviceRegistrationTests : XCTestCase
@end

@implementation HADeviceRegistrationTests

- (void)testSingletonExists {
    HADeviceRegistration *reg = [HADeviceRegistration sharedManager];
    XCTAssertNotNil(reg);
    XCTAssertEqual(reg, [HADeviceRegistration sharedManager], @"Should return same instance");
}

- (void)testDeviceInfoNonNil {
    HADeviceRegistration *reg = [HADeviceRegistration sharedManager];
    XCTAssertNotNil(reg.deviceName, @"deviceName should not be nil");
    XCTAssertTrue(reg.deviceName.length > 0, @"deviceName should not be empty");
}

- (void)testIsRegisteredReturnsFalseBeforeRegistration {
    // Clear any stored registration
    HADeviceRegistration *reg = [HADeviceRegistration sharedManager];
    [reg unregister];
    XCTAssertFalse(reg.isRegistered, @"Should not be registered after unregister");
}

- (void)testWebhookIdReturnsNilBeforeRegistration {
    HADeviceRegistration *reg = [HADeviceRegistration sharedManager];
    [reg unregister];
    XCTAssertNil(reg.webhookId, @"webhookId should be nil when not registered");
}

- (void)testResolvedWebhookURLNilWhenNotRegistered {
    HADeviceRegistration *reg = [HADeviceRegistration sharedManager];
    [reg unregister];
    NSURL *url = [reg resolvedWebhookURL];
    XCTAssertNil(url, @"resolvedWebhookURL should be nil when not registered");
}

- (void)testUnregisterClearsAllFields {
    HADeviceRegistration *reg = [HADeviceRegistration sharedManager];
    [reg unregister];
    XCTAssertNil(reg.webhookId);
    XCTAssertNil(reg.cloudhookURL);
    XCTAssertNil(reg.remoteUIURL);
    XCTAssertFalse(reg.isRegistered);
}

- (void)testSendWebhookFailsWhenNotRegistered {
    HADeviceRegistration *reg = [HADeviceRegistration sharedManager];
    [reg unregister];

    XCTestExpectation *exp = [self expectationWithDescription:@"webhook fails"];
    [reg sendWebhookWithType:@"test" data:@{} completion:^(id response, NSError *error) {
        XCTAssertNotNil(error, @"Should fail when not registered");
        XCTAssertNil(response);
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:3 handler:nil];
}

@end

#pragma mark - HASensorReporter Tests

@interface HASensorReporter (TestAccess)
- (BOOL)isSensorEnabled:(NSString *)sensorId;
- (id)currentValueForSensor:(NSString *)sensorId;
@end

@interface HASensorReporterTests : XCTestCase
@property (nonatomic, strong) HASensorReporter *reporter;
@end

@implementation HASensorReporterTests

- (void)setUp {
    [super setUp];
    self.reporter = [[HASensorReporter alloc] init];
}

- (void)tearDown {
    [self.reporter stopReporting];
    self.reporter = nil;
    // Reset sensor enable flags
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud removeObjectForKey:@"ha_sensor_battery_level_enabled"];
    [ud removeObjectForKey:@"ha_sensor_battery_state_enabled"];
    [ud removeObjectForKey:@"ha_sensor_screen_brightness_enabled"];
    [super tearDown];
}

- (void)testBatteryLevelEnabledByDefault {
    // Battery level defaults to ON when key is absent
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ha_sensor_battery_level_enabled"];
    XCTAssertTrue([self.reporter isSensorEnabled:@"battery_level"],
                  @"Battery level should be enabled by default");
}

- (void)testBatteryStateDisabledByDefault {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ha_sensor_battery_state_enabled"];
    XCTAssertFalse([self.reporter isSensorEnabled:@"battery_state"],
                   @"Battery state should be disabled by default");
}

- (void)testScreenBrightnessDisabledByDefault {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ha_sensor_screen_brightness_enabled"];
    XCTAssertFalse([self.reporter isSensorEnabled:@"screen_brightness"],
                   @"Screen brightness should be disabled by default");
}

- (void)testSensorEnabledReadsUserDefaults {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"ha_sensor_battery_state_enabled"];
    XCTAssertTrue([self.reporter isSensorEnabled:@"battery_state"]);

    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ha_sensor_battery_state_enabled"];
    XCTAssertFalse([self.reporter isSensorEnabled:@"battery_state"]);
}

- (void)testBatteryLevelValueIsNumber {
    id value = [self.reporter currentValueForSensor:@"battery_level"];
    XCTAssertTrue([value isKindOfClass:[NSNumber class]],
                  @"Battery level should be a number, got %@", [value class]);
}

- (void)testBatteryStateValueIsString {
    id value = [self.reporter currentValueForSensor:@"battery_state"];
    XCTAssertTrue([value isKindOfClass:[NSString class]],
                  @"Battery state should be a string, got %@", [value class]);
    // Must be one of the known values
    NSArray *validStates = @[@"Charging", @"Full", @"Not Charging", @"Unknown"];
    XCTAssertTrue([validStates containsObject:value],
                  @"Battery state '%@' should be one of %@", value, validStates);
}

- (void)testScreenBrightnessValueIsNumber {
    id value = [self.reporter currentValueForSensor:@"screen_brightness"];
    XCTAssertTrue([value isKindOfClass:[NSNumber class]],
                  @"Screen brightness should be a number, got %@", [value class]);
    NSInteger brightness = [value integerValue];
    XCTAssertTrue(brightness >= 0 && brightness <= 100,
                  @"Brightness %ld should be 0-100", (long)brightness);
}

- (void)testUnknownSensorReturnsUnknown {
    id value = [self.reporter currentValueForSensor:@"nonexistent_sensor"];
    XCTAssertEqualObjects(value, @"unknown");
}

- (void)testReportAllSensorsNowDoesNotCrashWhenNotRegistered {
    // Ensure not registered
    [[HADeviceRegistration sharedManager] unregister];
    XCTAssertNoThrow([self.reporter reportAllSensorsNow],
                     @"reportAllSensorsNow should not crash when not registered");
}

- (void)testStartStopReporting {
    // Should not crash even without a webhook registered
    XCTAssertNoThrow([self.reporter startReporting]);
    XCTAssertNoThrow([self.reporter stopReporting]);
    // Double stop should be safe
    XCTAssertNoThrow([self.reporter stopReporting]);
}

@end

#pragma mark - HARemoteCommandHandler Tests

@interface HARemoteCommandHandler (TestAccess)
- (void)dispatchCommand:(NSString *)command data:(NSDictionary *)data;
- (void)handleNotificationEvent:(NSDictionary *)eventData;
@end

@interface HARemoteCommandHandlerTests : XCTestCase
@property (nonatomic, strong) HARemoteCommandHandler *handler;
@end

@implementation HARemoteCommandHandlerTests

- (void)setUp {
    [super setUp];
    self.handler = [[HARemoteCommandHandler alloc] init];
}

- (void)tearDown {
    [self.handler stopListening];
    self.handler = nil;
    [super tearDown];
}

- (void)testBrightnessCommandDoesNotCrash {
    // UIScreen.brightness is a no-op on the simulator, so we verify the
    // command dispatches without crashing for all key variants.
    XCTAssertNoThrow([self.handler dispatchCommand:@"set_brightness" data:@{@"level": @50}]);
    XCTAssertNoThrow([self.handler dispatchCommand:@"set_brightness" data:@{@"brightness": @128}]);
    XCTAssertNoThrow([self.handler dispatchCommand:@"command_screen_brightness_level"
                                              data:@{@"command_screen_brightness_level": @255}]);
}

- (void)testBrightnessCommandPostsGenericNotification {
    XCTestExpectation *exp = [self expectationWithDescription:@"brightness notification"];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:HARemoteCommandNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        XCTAssertEqualObjects(note.userInfo[@"command"], @"set_brightness");
        [exp fulfill];
    }];
    [self.handler dispatchCommand:@"set_brightness" data:@{@"level": @50}];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testThemeCommand {
    HAThemeMode before = [HATheme currentMode];
    [self.handler dispatchCommand:@"set_theme" data:@{@"mode": @"dark"}];
    XCTAssertEqual([HATheme currentMode], HAThemeModeDark);
    [self.handler dispatchCommand:@"set_theme" data:@{@"mode": @"light"}];
    XCTAssertEqual([HATheme currentMode], HAThemeModeLight);
    [self.handler dispatchCommand:@"set_theme" data:@{@"mode": @"auto"}];
    XCTAssertEqual([HATheme currentMode], HAThemeModeAuto);
    // Restore
    [HATheme setCurrentMode:before];
}

- (void)testKioskModeCommand {
    BOOL before = [[HAAuthManager sharedManager] isKioskMode];
    [self.handler dispatchCommand:@"set_kiosk_mode" data:@{@"enabled": @YES}];
    XCTAssertTrue([[HAAuthManager sharedManager] isKioskMode]);
    [self.handler dispatchCommand:@"set_kiosk_mode" data:@{@"enabled": @NO}];
    XCTAssertFalse([[HAAuthManager sharedManager] isKioskMode]);
    // Restore
    [[HAAuthManager sharedManager] setKioskMode:before];
}

- (void)testSwitchViewPostsNotification {
    XCTestExpectation *exp = [self expectationWithDescription:@"navigate notification"];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:@"HAActionNavigateNotification" object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        XCTAssertEqualObjects(note.userInfo[@"path"], @"2");
        [exp fulfill];
    }];

    [self.handler dispatchCommand:@"switch_view" data:@{@"path": @"2"}];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testUnknownCommandDoesNotCrash {
    XCTAssertNoThrow([self.handler dispatchCommand:@"totally_unknown_command" data:@{@"foo": @"bar"}],
                     @"Unknown command should log but not crash");
}

- (void)testNilDataDoesNotCrash {
    XCTAssertNoThrow([self.handler dispatchCommand:@"set_brightness" data:nil],
                     @"Nil data should not crash");
    XCTAssertNoThrow([self.handler dispatchCommand:@"set_theme" data:nil],
                     @"Nil data should not crash");
    XCTAssertNoThrow([self.handler dispatchCommand:@"set_kiosk_mode" data:nil],
                     @"Nil data should not crash");
    XCTAssertNoThrow([self.handler dispatchCommand:@"switch_dashboard" data:nil],
                     @"Nil data should not crash");
    XCTAssertNoThrow([self.handler dispatchCommand:@"switch_view" data:nil],
                     @"Nil data should not crash");
}

- (void)testEmptyDataDoesNotCrash {
    XCTAssertNoThrow([self.handler dispatchCommand:@"set_brightness" data:@{}]);
    XCTAssertNoThrow([self.handler dispatchCommand:@"set_theme" data:@{}]);
    XCTAssertNoThrow([self.handler dispatchCommand:@"set_kiosk_mode" data:@{}]);
    XCTAssertNoThrow([self.handler dispatchCommand:@"switch_dashboard" data:@{}]);
}

- (void)testHandleNotificationEventCompanionStyle {
    // Companion-style: message field with "command_" prefix
    XCTestExpectation *exp = [self expectationWithDescription:@"command notification"];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:HARemoteCommandNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        XCTAssertEqualObjects(note.userInfo[@"command"], @"command_screen_on");
        [exp fulfill];
    }];

    [self.handler handleNotificationEvent:@{
        @"message": @"command_screen_on",
        @"data": @{}
    }];

    [self waitForExpectationsWithTimeout:2 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testHandleNotificationEventHADictStyle {
    XCTestExpectation *exp = [self expectationWithDescription:@"ha dict command"];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:HARemoteCommandNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        XCTAssertEqualObjects(note.userInfo[@"command"], @"reload");
        [exp fulfill];
    }];

    [self.handler handleNotificationEvent:@{
        @"homeassistant": @{@"command": @"reload"}
    }];

    [self waitForExpectationsWithTimeout:2 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testGenericNotificationPostedOnDispatch {
    XCTestExpectation *exp = [self expectationWithDescription:@"generic notification"];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:HARemoteCommandNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        XCTAssertNotNil(note.userInfo[@"command"]);
        XCTAssertNotNil(note.userInfo[@"data"]);
        [exp fulfill];
    }];

    [self.handler dispatchCommand:@"anything" data:@{@"key": @"val"}];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

@end

#pragma mark - HADeviceIntegrationManager Tests

@interface HADeviceIntegrationManagerTests : XCTestCase
@end

@implementation HADeviceIntegrationManagerTests

- (void)testSingletonExists {
    HADeviceIntegrationManager *mgr = [HADeviceIntegrationManager sharedManager];
    XCTAssertNotNil(mgr);
    XCTAssertEqual(mgr, [HADeviceIntegrationManager sharedManager]);
}

- (void)testStartWhenNotRegisteredIsNoOp {
    // Ensure not registered
    [[HADeviceRegistration sharedManager] unregister];
    HADeviceIntegrationManager *mgr = [HADeviceIntegrationManager sharedManager];
    BOOL wasPreviouslyEnabled = mgr.enabled;
    mgr.enabled = YES;

    // start should be a no-op when not registered
    XCTAssertNoThrow([mgr start]);
    XCTAssertFalse(mgr.isRegistered);

    // Restore
    mgr.enabled = wasPreviouslyEnabled;
}

- (void)testStopCleansUp {
    HADeviceIntegrationManager *mgr = [HADeviceIntegrationManager sharedManager];
    // Even calling stop when not running should be safe
    XCTAssertNoThrow([mgr stop]);
    // Double stop
    XCTAssertNoThrow([mgr stop]);
}

- (void)testIsRegisteredDelegatesToDeviceRegistration {
    [[HADeviceRegistration sharedManager] unregister];
    HADeviceIntegrationManager *mgr = [HADeviceIntegrationManager sharedManager];
    XCTAssertFalse(mgr.isRegistered);
    XCTAssertEqual(mgr.isRegistered, [HADeviceRegistration sharedManager].isRegistered);
}

- (void)testEnabledPersistsToUserDefaults {
    HADeviceIntegrationManager *mgr = [HADeviceIntegrationManager sharedManager];
    BOOL before = mgr.enabled;

    mgr.enabled = YES;
    XCTAssertTrue([[NSUserDefaults standardUserDefaults] boolForKey:@"HADeviceIntegration_enabled"]);

    mgr.enabled = NO;
    XCTAssertFalse([[NSUserDefaults standardUserDefaults] boolForKey:@"HADeviceIntegration_enabled"]);

    mgr.enabled = before;
}

@end
