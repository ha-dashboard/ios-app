#import <XCTest/XCTest.h>
#import "HADeviceRegistration.h"
#import "HASensorReporter.h"
#import "HARemoteCommandHandler.h"
#import "HADeviceIntegrationManager.h"
#import "HANotificationPresenter.h"
#import "HATheme.h"
#import "HAAuthManager.h"
#import "HAProximityWakeController.h"

#pragma mark - HADeviceRegistration Tests

@interface HADeviceRegistrationTests : XCTestCase
@end

@interface HADeviceRegistration (TestAccess)
- (NSDictionary *)registrationBody;
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

- (void)testRegistrationExplicitlyAdvertisesWebSocketPush {
    NSDictionary *appData = [[HADeviceRegistration sharedManager] registrationBody][@"app_data"];
    XCTAssertEqualObjects(appData[@"push_websocket_channel"], @YES);
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
- (id)currentValueForSensor:(NSString *)sensorId;
- (NSString *)iconForSensor:(NSString *)sensorId;
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
    [super tearDown];
}

- (void)testAllSensorsHaveValues {
    NSArray *sensorIds = @[@"battery_level", @"battery_state", @"screen_brightness",
                           @"storage_available", @"app_state", @"active_dashboard",
                           @"wifi_ssid", @"wifi_bssid", @"connection_type",
                           @"last_update_trigger", @"device_model"];
    for (NSString *sensorId in sensorIds) {
        id value = [self.reporter currentValueForSensor:sensorId];
        XCTAssertNotNil(value, @"Sensor '%@' should return a non-nil value", sensorId);
    }
}

- (void)testAllSensorsHaveIcons {
    NSArray *sensorIds = @[@"battery_level", @"battery_state", @"screen_brightness",
                           @"storage_available", @"app_state", @"active_dashboard",
                           @"wifi_ssid", @"wifi_bssid", @"connection_type",
                           @"last_update_trigger", @"device_model"];
    for (NSString *sensorId in sensorIds) {
        NSString *icon = [self.reporter iconForSensor:sensorId];
        XCTAssertTrue([icon hasPrefix:@"mdi:"], @"Sensor '%@' icon should start with mdi:, got '%@'", sensorId, icon);
    }
}

- (void)testStorageValueIsNumber {
    id value = [self.reporter currentValueForSensor:@"storage_available"];
    XCTAssertTrue([value isKindOfClass:[NSNumber class]],
                  @"Storage should be a number, got %@", [value class]);
}

- (void)testAppStateValueIsString {
    id value = [self.reporter currentValueForSensor:@"app_state"];
    XCTAssertTrue([value isKindOfClass:[NSString class]],
                  @"App state should be a string, got %@", [value class]);
    NSArray *validStates = @[@"Active", @"Inactive", @"Background", @"Unknown"];
    XCTAssertTrue([validStates containsObject:value],
                  @"App state '%@' should be one of %@", value, validStates);
}

- (void)testActiveDashboardValueIsString {
    id value = [self.reporter currentValueForSensor:@"active_dashboard"];
    XCTAssertTrue([value isKindOfClass:[NSString class]],
                  @"Active dashboard should be a string, got %@", [value class]);
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
    XCTAssertTrue(brightness == -1 || (brightness >= 0 && brightness <= 100),
                  @"Brightness %ld should be -1 (unavailable) or 0-100", (long)brightness);
}

- (void)testUnknownSensorReturnsUnknown {
    id value = [self.reporter currentValueForSensor:@"nonexistent_sensor"];
    XCTAssertEqualObjects(value, @"unknown");
}

- (void)testWifiSSIDIsString {
    id value = [self.reporter currentValueForSensor:@"wifi_ssid"];
    XCTAssertTrue([value isKindOfClass:[NSString class]],
                  @"WiFi SSID should be a string, got %@", [value class]);
    // On simulator without entitlement, returns "Unknown"
}

- (void)testWifiBSSIDIsString {
    id value = [self.reporter currentValueForSensor:@"wifi_bssid"];
    XCTAssertTrue([value isKindOfClass:[NSString class]],
                  @"WiFi BSSID should be a string, got %@", [value class]);
}

- (void)testConnectionTypeIsValidString {
    id value = [self.reporter currentValueForSensor:@"connection_type"];
    XCTAssertTrue([value isKindOfClass:[NSString class]],
                  @"Connection type should be a string, got %@", [value class]);
    NSArray *validTypes = @[@"WiFi", @"Cellular", @"No Connection"];
    XCTAssertTrue([validTypes containsObject:value],
                  @"Connection type '%@' should be one of %@", value, validTypes);
}

- (void)testLastUpdateTriggerIsString {
    id value = [self.reporter currentValueForSensor:@"last_update_trigger"];
    XCTAssertTrue([value isKindOfClass:[NSString class]],
                  @"Last update trigger should be a string, got %@", [value class]);
}

- (void)testDeviceModelIsNonEmptyString {
    id value = [self.reporter currentValueForSensor:@"device_model"];
    XCTAssertTrue([value isKindOfClass:[NSString class]],
                  @"Device model should be a string, got %@", [value class]);
    XCTAssertTrue([value length] > 0, @"Device model should not be empty");
    // On simulator, returns something like "arm64" or "x86_64"
}

- (void)testAllElevenSensorsHaveValues {
    NSArray *sensorIds = @[@"battery_level", @"battery_state", @"screen_brightness",
                           @"storage_available", @"app_state", @"active_dashboard",
                           @"wifi_ssid", @"wifi_bssid", @"connection_type",
                           @"last_update_trigger", @"device_model"];
    XCTAssertEqual(sensorIds.count, 11u, @"Should have 11 sensors");
    for (NSString *sensorId in sensorIds) {
        id value = [self.reporter currentValueForSensor:sensorId];
        XCTAssertNotNil(value, @"Sensor '%@' should return a non-nil value", sensorId);
    }
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

#pragma mark - HAProximityWakeController Tests

@interface HAProximityWakeController (TestAccess)
- (void)dim;
@property (nonatomic, readonly) BOOL sleeping;
@property (nonatomic, readonly) CGFloat savedBrightness;
@property (nonatomic, strong, readonly) UIView *sleepOverlay;
@end

@interface HAProximityWakeControllerTests : XCTestCase
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) HAProximityWakeController *controller;
@end

@implementation HAProximityWakeControllerTests

- (void)setUp {
    [super setUp];
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    self.controller = [[HAProximityWakeController alloc] initWithWindow:self.window];
    [self.controller start];
}

- (void)tearDown {
    [self.controller stop];
    self.controller = nil;
    self.window = nil;
    [super tearDown];
}

- (void)testRemoteWakeUsesTheSameStateTransitionAsTouch {
    [self.controller dim];
    XCTAssertTrue(self.controller.sleeping);

    [[NSNotificationCenter defaultCenter]
        postNotificationName:HAWindowUserDidInteractNotification object:self];

    XCTAssertFalse(self.controller.sleeping);
}

- (void)testRemoteBrightnessChangesTheNextWakeLevelWithoutWaking {
    [self.controller dim];
    XCTAssertTrue(self.controller.sleeping);

    [[NSNotificationCenter defaultCenter]
        postNotificationName:HAProximityWakeSetBrightnessNotification
                      object:self
                    userInfo:@{@"brightness": @0.73}];

    XCTAssertTrue(self.controller.sleeping);
    XCTAssertEqualWithAccuracy(self.controller.savedBrightness, 0.73, 0.001);
}

- (void)testRemoteSleepAddsTheTouchAbsorbingOverlay {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:HAProximityWakeSleepNotification object:self];

    XCTAssertTrue(self.controller.sleeping);
    XCTAssertNotNil(self.controller.sleepOverlay);
    XCTAssertTrue(self.controller.sleepOverlay.userInteractionEnabled);
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

- (void)testWakeOnTouchBrightnessIsDelegatedToTheProximityController {
    HAAuthManager *auth = [HAAuthManager sharedManager];
    BOOL oldKiosk = auth.isKioskMode;
    BOOL oldWake = auth.proximityWakeEnabled;
    [auth setKioskMode:YES];
    [auth setProximityWakeEnabled:YES];

    XCTestExpectation *exp = [self expectationWithDescription:@"proximity brightness request"];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:HAProximityWakeSetBrightnessNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        XCTAssertEqualWithAccuracy([note.userInfo[@"brightness"] doubleValue], 0.75, 0.001);
        [exp fulfill];
    }];
    [self.handler dispatchCommand:@"set_brightness" data:@{@"level": @75}];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    [auth setProximityWakeEnabled:oldWake];
    [auth setKioskMode:oldKiosk];
}

- (void)testWakeOnTouchScreenOnUsesTheTouchWakePath {
    HAAuthManager *auth = [HAAuthManager sharedManager];
    BOOL oldKiosk = auth.isKioskMode;
    BOOL oldWake = auth.proximityWakeEnabled;
    [auth setKioskMode:YES];
    [auth setProximityWakeEnabled:YES];

    XCTestExpectation *exp = [self expectationWithDescription:@"touch wake request"];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:HAWindowUserDidInteractNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        [exp fulfill];
    }];
    [self.handler dispatchCommand:@"command_screen_on" data:@{}];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    [auth setProximityWakeEnabled:oldWake];
    [auth setKioskMode:oldKiosk];
}

- (void)testWakeOnTouchScreenOffUsesTheProtectiveSleepOverlay {
    HAAuthManager *auth = [HAAuthManager sharedManager];
    BOOL oldKiosk = auth.isKioskMode;
    BOOL oldWake = auth.proximityWakeEnabled;
    [auth setKioskMode:YES];
    [auth setProximityWakeEnabled:YES];

    XCTestExpectation *exp = [self expectationWithDescription:@"proximity sleep request"];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:HAProximityWakeSleepNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        [exp fulfill];
    }];
    [self.handler dispatchCommand:@"command_screen_off" data:@{}];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    [auth setProximityWakeEnabled:oldWake];
    [auth setKioskMode:oldKiosk];
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

- (void)testCommandNotificationDoesNotTriggerDisplayNotification {
    // A "command_" prefixed message should NOT post HADisplayNotificationReceivedNotification
    XCTestExpectation *notCalled = [self expectationWithDescription:@"display NOT posted"];
    notCalled.inverted = YES; // Expect this NOT to be fulfilled

    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:HADisplayNotificationReceivedNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        [notCalled fulfill]; // This should NOT happen
    }];

    [self.handler handleNotificationEvent:@{
        @"message": @"command_screen_brightness_level",
        @"data": @{@"level": @50}
    }];

    [self waitForExpectationsWithTimeout:0.5 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testNonCommandNotificationTriggersDisplayNotification {
    // A plain message (not command) should post HADisplayNotificationReceivedNotification
    XCTestExpectation *exp = [self expectationWithDescription:@"display posted"];

    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:HADisplayNotificationReceivedNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        XCTAssertEqualObjects(note.userInfo[@"title"], @"Test Alert");
        XCTAssertEqualObjects(note.userInfo[@"message"], @"Hello from HA");
        [exp fulfill];
    }];

    [self.handler handleNotificationEvent:@{
        @"title": @"Test Alert",
        @"message": @"Hello from HA"
    }];

    [self waitForExpectationsWithTimeout:2 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testDataCommandDoesNotTriggerDisplayNotification {
    // A notification with data.command should dispatch as command, NOT display
    XCTestExpectation *notCalled = [self expectationWithDescription:@"display NOT posted"];
    notCalled.inverted = YES;

    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:HADisplayNotificationReceivedNotification object:nil queue:nil
                usingBlock:^(NSNotification *note) {
        [notCalled fulfill];
    }];

    [self.handler handleNotificationEvent:@{
        @"message": @"remote_command",
        @"data": @{@"command": @"set_theme", @"mode": @"dark"}
    }];

    [self waitForExpectationsWithTimeout:0.5 handler:nil];
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

#pragma mark - HANotificationPresenter Tests

@interface HANotificationPresenterTests : XCTestCase
@end

@implementation HANotificationPresenterTests

- (void)testSingletonExists {
    HANotificationPresenter *p = [HANotificationPresenter sharedPresenter];
    XCTAssertNotNil(p);
    XCTAssertEqual(p, [HANotificationPresenter sharedPresenter]);
}

- (void)testStartStopDoesNotCrash {
    HANotificationPresenter *p = [HANotificationPresenter sharedPresenter];
    XCTAssertNoThrow([p start]);
    XCTAssertNoThrow([p stop]);
    // Double stop safe
    XCTAssertNoThrow([p stop]);
    // Start after stop safe
    XCTAssertNoThrow([p start]);
    [p stop]; // cleanup
}

- (void)testPostingNotificationQueues {
    HANotificationPresenter *p = [HANotificationPresenter sharedPresenter];
    [p start];

    // Post a display notification — presenter should receive it without crash
    // (no keyWindow in test environment, so it won't actually display, but shouldn't crash)
    [[NSNotificationCenter defaultCenter] postNotificationName:HADisplayNotificationReceivedNotification
                                                        object:nil
                                                      userInfo:@{@"title": @"Test", @"message": @"Body"}];

    [p stop];
}

@end
