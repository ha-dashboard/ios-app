#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"

// Cell imports
#import "HALightEntityCell.h"
#import "HASwitchEntityCell.h"
#import "HAClimateEntityCell.h"
#import "HAThermostatGaugeCell.h"
#import "HACoverEntityCell.h"
#import "HALockEntityCell.h"
#import "HAMediaPlayerEntityCell.h"
#import "HAAlarmEntityCell.h"
#import "HAFanEntityCell.h"
#import "HASensorEntityCell.h"
#import "HAVacuumEntityCell.h"
#import "HAHumidifierEntityCell.h"
#import "HAPersonEntityCell.h"
#import "HASceneEntityCell.h"
#import "HAButtonEntityCell.h"
#import "HACounterEntityCell.h"
#import "HATimerEntityCell.h"
#import "HAUpdateEntityCell.h"
#import "HAInputNumberEntityCell.h"
#import "HAInputSelectEntityCell.h"
#import "HAInputTextEntityCell.h"
#import "HAInputDateTimeEntityCell.h"
#import "HACameraEntityCell.h"
#import "HAWeatherEntityCell.h"

/// Phase 1 snapshot tests: one test per showcase entity, rendered in its primary cell type.
@interface HAEntityShowcaseSnapshotTests : HABaseSnapshotTestCase
@end

@implementation HAEntityShowcaseSnapshotTests

#pragma mark - Light (10 variants)

- (void)testLightScBasicOn {
    HAEntity *entity = [HASnapshotTestHelpers lightScBasicOn];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightScBasicOff {
    HAEntity *entity = [HASnapshotTestHelpers lightScBasicOff];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightScColorTemp {
    HAEntity *entity = [HASnapshotTestHelpers lightScColorTemp];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightScRgb {
    HAEntity *entity = [HASnapshotTestHelpers lightScRgb];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightScRgbw {
    HAEntity *entity = [HASnapshotTestHelpers lightScRgbw];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightScAllModes {
    HAEntity *entity = [HASnapshotTestHelpers lightScAllModes];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightScEffect {
    HAEntity *entity = [HASnapshotTestHelpers lightScEffect];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightScBrightnessOnly {
    HAEntity *entity = [HASnapshotTestHelpers lightScBrightnessOnly];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightScDimmedLow {
    HAEntity *entity = [HASnapshotTestHelpers lightScDimmedLow];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightScMaxBright {
    HAEntity *entity = [HASnapshotTestHelpers lightScMaxBright];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALightEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Climate (8 variants) - Standard Cell

- (void)testClimateScHeating {
    HAEntity *entity = [HASnapshotTestHelpers climateScHeating];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"climate" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAClimateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testClimateScCooling {
    HAEntity *entity = [HASnapshotTestHelpers climateScCooling];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"climate" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAClimateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testClimateScHeatCool {
    HAEntity *entity = [HASnapshotTestHelpers climateScHeatCool];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"climate" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAClimateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testClimateScPresets {
    HAEntity *entity = [HASnapshotTestHelpers climateScPresets];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"climate" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAClimateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testClimateScFan {
    HAEntity *entity = [HASnapshotTestHelpers climateScFan];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"climate" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAClimateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testClimateScSwing {
    HAEntity *entity = [HASnapshotTestHelpers climateScSwing];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"climate" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAClimateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testClimateScAll {
    HAEntity *entity = [HASnapshotTestHelpers climateScAll];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"climate" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAClimateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testClimateScOff {
    HAEntity *entity = [HASnapshotTestHelpers climateScOff];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"climate" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAClimateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Climate (4 variants) - Thermostat Gauge

- (void)testThermostatScHeating {
    HAEntity *entity = [HASnapshotTestHelpers climateScHeating];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"thermostat" columnSpan:9 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAThermostatGaugeCell class]
        size:CGSizeMake(floor(kSubGridUnit * 9), kThermostatHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testThermostatScCooling {
    HAEntity *entity = [HASnapshotTestHelpers climateScCooling];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"thermostat" columnSpan:9 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAThermostatGaugeCell class]
        size:CGSizeMake(floor(kSubGridUnit * 9), kThermostatHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testThermostatScHeatCool {
    HAEntity *entity = [HASnapshotTestHelpers climateScHeatCool];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"thermostat" columnSpan:9 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAThermostatGaugeCell class]
        size:CGSizeMake(floor(kSubGridUnit * 9), kThermostatHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testThermostatScOff {
    HAEntity *entity = [HASnapshotTestHelpers climateScOff];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"thermostat" columnSpan:9 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAThermostatGaugeCell class]
        size:CGSizeMake(floor(kSubGridUnit * 9), kThermostatHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Cover (10 variants)

- (void)testCoverScPosition {
    HAEntity *entity = [HASnapshotTestHelpers coverScPosition];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"cover" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HACoverEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverScTilt {
    HAEntity *entity = [HASnapshotTestHelpers coverScTilt];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"cover" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HACoverEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverScPosTilt {
    HAEntity *entity = [HASnapshotTestHelpers coverScPosTilt];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"cover" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HACoverEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverScNoPosition {
    HAEntity *entity = [HASnapshotTestHelpers coverScNoPosition];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"cover" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HACoverEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverScOpening {
    HAEntity *entity = [HASnapshotTestHelpers coverScOpening];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"cover" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HACoverEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverScClosed {
    HAEntity *entity = [HASnapshotTestHelpers coverScClosed];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"cover" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HACoverEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverScBlind {
    HAEntity *entity = [HASnapshotTestHelpers coverScBlind];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"cover" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HACoverEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverScGarage {
    HAEntity *entity = [HASnapshotTestHelpers coverScGarage];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"cover" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HACoverEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverScDoor {
    HAEntity *entity = [HASnapshotTestHelpers coverScDoor];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"cover" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HACoverEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverScShutter {
    HAEntity *entity = [HASnapshotTestHelpers coverScShutter];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"cover" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HACoverEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Lock (5 variants)

- (void)testLockScLocked {
    HAEntity *entity = [HASnapshotTestHelpers lockScLocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"lock" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALockEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLockScUnlocked {
    HAEntity *entity = [HASnapshotTestHelpers lockScUnlocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"lock" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALockEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLockScJammed {
    HAEntity *entity = [HASnapshotTestHelpers lockScJammed];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"lock" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALockEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLockScCode {
    HAEntity *entity = [HASnapshotTestHelpers lockScCode];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"lock" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALockEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLockScLocking {
    HAEntity *entity = [HASnapshotTestHelpers lockScLocking];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"lock" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HALockEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Media Player (6 variants)

- (void)testMediaPlayerScFull {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerScFull];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"media-control" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAMediaPlayerEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), 120.0) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testMediaPlayerScPaused {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerScPaused];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"media-control" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAMediaPlayerEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), 120.0) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testMediaPlayerScMuted {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerScMuted];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"media-control" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAMediaPlayerEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), 120.0) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testMediaPlayerScIdle {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerScIdle];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"media-control" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAMediaPlayerEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), 120.0) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testMediaPlayerScOff {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerScOff];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"media-control" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAMediaPlayerEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), 120.0) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testMediaPlayerScNoSource {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerScNoSource];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"media-control" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAMediaPlayerEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), 120.0) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Alarm Control Panel (7 variants)

- (void)testAlarmScDisarmed {
    HAEntity *entity = [HASnapshotTestHelpers alarmScDisarmed];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"alarm-panel" columnSpan:12 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAAlarmEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 12), 320.0) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testAlarmScHome {
    HAEntity *entity = [HASnapshotTestHelpers alarmScHome];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"alarm-panel" columnSpan:12 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAAlarmEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 12), 320.0) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testAlarmScAway {
    HAEntity *entity = [HASnapshotTestHelpers alarmScAway];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"alarm-panel" columnSpan:12 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAAlarmEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 12), 320.0) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testAlarmScNight {
    HAEntity *entity = [HASnapshotTestHelpers alarmScNight];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"alarm-panel" columnSpan:12 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAAlarmEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 12), 320.0) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testAlarmScVacation {
    HAEntity *entity = [HASnapshotTestHelpers alarmScVacation];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"alarm-panel" columnSpan:12 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAAlarmEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 12), 320.0) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testAlarmScTriggered {
    HAEntity *entity = [HASnapshotTestHelpers alarmScTriggered];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"alarm-panel" columnSpan:12 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAAlarmEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 12), 320.0) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testAlarmScNoCode {
    HAEntity *entity = [HASnapshotTestHelpers alarmScNoCode];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"alarm-panel" columnSpan:12 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAAlarmEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 12), 320.0) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Fan (5 variants)

- (void)testFanScBasic {
    HAEntity *entity = [HASnapshotTestHelpers fanScBasic];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"fan" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAFanEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testFanScPresets {
    HAEntity *entity = [HASnapshotTestHelpers fanScPresets];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"fan" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAFanEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testFanScOscillating {
    HAEntity *entity = [HASnapshotTestHelpers fanScOscillating];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"fan" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAFanEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testFanScReverse {
    HAEntity *entity = [HASnapshotTestHelpers fanScReverse];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"fan" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAFanEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testFanScOff {
    HAEntity *entity = [HASnapshotTestHelpers fanScOff];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"fan" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAFanEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Sensor (10 variants)

- (void)testSensorScTemperature {
    HAEntity *entity = [HASnapshotTestHelpers sensorScTemperature];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorScHumidity {
    HAEntity *entity = [HASnapshotTestHelpers sensorScHumidity];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorScPower {
    HAEntity *entity = [HASnapshotTestHelpers sensorScPower];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorScEnergy {
    HAEntity *entity = [HASnapshotTestHelpers sensorScEnergy];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorScBattery {
    HAEntity *entity = [HASnapshotTestHelpers sensorScBattery];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorScIlluminance {
    HAEntity *entity = [HASnapshotTestHelpers sensorScIlluminance];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorScPressure {
    HAEntity *entity = [HASnapshotTestHelpers sensorScPressure];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorScGas {
    HAEntity *entity = [HASnapshotTestHelpers sensorScGas];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorScMonetary {
    HAEntity *entity = [HASnapshotTestHelpers sensorScMonetary];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorScText {
    HAEntity *entity = [HASnapshotTestHelpers sensorScText];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Binary Sensor (12 variants)

- (void)testBinarySensorScDoorOpen {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScDoorOpen];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"binary_sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorScDoorClosed {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScDoorClosed];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"binary_sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorScMotionOn {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScMotionOn];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"binary_sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorScMotionOff {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScMotionOff];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"binary_sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorScSmoke {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScSmoke];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"binary_sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorScMoisture {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScMoisture];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"binary_sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorScWindow {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScWindow];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"binary_sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorScOccupancy {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScOccupancy];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"binary_sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorScPresence {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScPresence];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"binary_sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorScBatteryLow {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScBatteryLow];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"binary_sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorScPlug {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScPlug];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"binary_sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorScGeneric {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScGeneric];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"binary_sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Vacuum (4 variants)

- (void)testVacuumScDocked {
    HAEntity *entity = [HASnapshotTestHelpers vacuumScDocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"vacuum" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAVacuumEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kVacuumHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testVacuumScCleaning {
    HAEntity *entity = [HASnapshotTestHelpers vacuumScCleaning];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"vacuum" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAVacuumEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kVacuumHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testVacuumScReturning {
    HAEntity *entity = [HASnapshotTestHelpers vacuumScReturning];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"vacuum" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAVacuumEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kVacuumHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testVacuumScError {
    HAEntity *entity = [HASnapshotTestHelpers vacuumScError];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"vacuum" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAVacuumEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kVacuumHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Humidifier (3 variants)

- (void)testHumidifierScOn {
    HAEntity *entity = [HASnapshotTestHelpers humidifierScOn];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"humidifier" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAHumidifierEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testHumidifierScEco {
    HAEntity *entity = [HASnapshotTestHelpers humidifierScEco];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"humidifier" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAHumidifierEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testHumidifierScOff {
    HAEntity *entity = [HASnapshotTestHelpers humidifierScOff];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"humidifier" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAHumidifierEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Input Boolean (2 variants)

- (void)testInputBooleanScOn {
    HAEntity *entity = [HASnapshotTestHelpers inputBooleanScOn];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"input_boolean" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testInputBooleanScOff {
    HAEntity *entity = [HASnapshotTestHelpers inputBooleanScOff];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"input_boolean" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Input Number (2 variants)

- (void)testInputNumberScSlider {
    HAEntity *entity = [HASnapshotTestHelpers inputNumberScSlider];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"input_number" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAInputNumberEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testInputNumberScBox {
    HAEntity *entity = [HASnapshotTestHelpers inputNumberScBox];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"input_number" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAInputNumberEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Input Select (1 variant)

- (void)testInputSelectSc {
    HAEntity *entity = [HASnapshotTestHelpers inputSelectSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"input_select" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAInputSelectEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Input Text (2 variants)

- (void)testInputTextScText {
    HAEntity *entity = [HASnapshotTestHelpers inputTextScText];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"input_text" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAInputTextEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testInputTextScPassword {
    HAEntity *entity = [HASnapshotTestHelpers inputTextScPassword];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"input_text" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAInputTextEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Input DateTime (3 variants)

- (void)testInputDateTimeScDate {
    HAEntity *entity = [HASnapshotTestHelpers inputDateTimeScDate];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"input_datetime" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAInputDateTimeEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testInputDateTimeScTime {
    HAEntity *entity = [HASnapshotTestHelpers inputDateTimeScTime];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"input_datetime" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAInputDateTimeEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testInputDateTimeScBoth {
    HAEntity *entity = [HASnapshotTestHelpers inputDateTimeScBoth];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"input_datetime" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAInputDateTimeEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Counter (1 variant)

- (void)testCounterSc {
    HAEntity *entity = [HASnapshotTestHelpers counterSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"counter" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HACounterEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Timer (3 variants)

- (void)testTimerScActive {
    HAEntity *entity = [HASnapshotTestHelpers timerScActive];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"timer" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATimerEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testTimerScPaused {
    HAEntity *entity = [HASnapshotTestHelpers timerScPaused];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"timer" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATimerEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testTimerScIdle {
    HAEntity *entity = [HASnapshotTestHelpers timerScIdle];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"timer" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATimerEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Person (3 variants)

- (void)testPersonScHome {
    HAEntity *entity = [HASnapshotTestHelpers personScHome];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"person" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAPersonEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testPersonScAway {
    HAEntity *entity = [HASnapshotTestHelpers personScAway];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"person" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAPersonEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testPersonScZone {
    HAEntity *entity = [HASnapshotTestHelpers personScZone];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"person" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAPersonEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Scene & Script

- (void)testSceneSc {
    HAEntity *entity = [HASnapshotTestHelpers sceneSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"scene" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASceneEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testScriptSc {
    HAEntity *entity = [HASnapshotTestHelpers scriptSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"script" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASceneEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Automation

- (void)testAutomationSc {
    HAEntity *entity = [HASnapshotTestHelpers automationSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"automation" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Update (2 variants)

- (void)testUpdateScAvailable {
    HAEntity *entity = [HASnapshotTestHelpers updateScAvailable];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"update" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAUpdateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testUpdateScCurrent {
    HAEntity *entity = [HASnapshotTestHelpers updateScCurrent];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"update" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAUpdateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Valve (2 variants)

- (void)testValveScOpen {
    HAEntity *entity = [HASnapshotTestHelpers valveScOpen];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"valve" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testValveScClosed {
    HAEntity *entity = [HASnapshotTestHelpers valveScClosed];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"valve" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Lawn Mower (2 variants)

- (void)testLawnMowerScDocked {
    HAEntity *entity = [HASnapshotTestHelpers lawnMowerScDocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"lawn_mower" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLawnMowerScMowing {
    HAEntity *entity = [HASnapshotTestHelpers lawnMowerScMowing];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"lawn_mower" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Water Heater

- (void)testWaterHeaterSc {
    HAEntity *entity = [HASnapshotTestHelpers waterHeaterSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"water_heater" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Misc Domains (default toggle cells)

- (void)testRemoteSc {
    HAEntity *entity = [HASnapshotTestHelpers remoteSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"remote" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testImageSc {
    HAEntity *entity = [HASnapshotTestHelpers imageSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"image" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testTodoSc {
    HAEntity *entity = [HASnapshotTestHelpers todoSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"todo" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testEventSc {
    HAEntity *entity = [HASnapshotTestHelpers eventSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"event" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testDeviceTrackerScHome {
    HAEntity *entity = [HASnapshotTestHelpers deviceTrackerScHome];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"device_tracker" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAPersonEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testDeviceTrackerScAway {
    HAEntity *entity = [HASnapshotTestHelpers deviceTrackerScAway];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"device_tracker" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAPersonEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

@end
