#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HATileEntityCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"

@interface HADisplayConfigSnapshotTests_TileFeatures : HABaseSnapshotTestCase
@end

@implementation HADisplayConfigSnapshotTests_TileFeatures

#pragma mark - Helpers

- (HADashboardConfigItem *)tileItemWithEntityId:(NSString *)entityId features:(NSArray *)features {
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entityId
                                                                cardType:@"tile"
                                                              columnSpan:6
                                                             headingIcon:nil
                                                             displayName:nil];
    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    if (features) props[@"features"] = features;
    item.customProperties = [props copy];
    return item;
}

- (void)verifyTileForEntity:(HAEntity *)entity features:(NSArray *)features {
    HADashboardConfigItem *item = [self tileItemWithEntityId:entity.entityId features:features];
    CGFloat height = [HATileEntityCell preferredHeightForConfigItem:item];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 6), height);
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class] size:size configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Light

- (void)testLightTile_brightness {
    HAEntity *entity = [HASnapshotTestHelpers lightScBasicOn];
    [self verifyTileForEntity:entity features:@[@{@"type": @"light-brightness"}]];
}

- (void)testLightTile_colorTemp {
    HAEntity *entity = [HASnapshotTestHelpers lightScColorTemp];
    [self verifyTileForEntity:entity features:@[@{@"type": @"light-color-temp"}]];
}

- (void)testLightTile_brightnessAndColorTemp {
    HAEntity *entity = [HASnapshotTestHelpers lightScAllModes];
    [self verifyTileForEntity:entity features:@[
        @{@"type": @"light-brightness"},
        @{@"type": @"light-color-temp"}
    ]];
}

#pragma mark - Cover

- (void)testCoverTile_openClose {
    HAEntity *entity = [HASnapshotTestHelpers coverScPosition];
    [self verifyTileForEntity:entity features:@[@{@"type": @"cover-open-close"}]];
}

- (void)testCoverTile_position {
    HAEntity *entity = [HASnapshotTestHelpers coverScPosition];
    [self verifyTileForEntity:entity features:@[@{@"type": @"cover-position"}]];
}

- (void)testCoverTile_tiltPosition {
    HAEntity *entity = [HASnapshotTestHelpers coverScTilt];
    [self verifyTileForEntity:entity features:@[@{@"type": @"cover-tilt-position"}]];
}

- (void)testCoverTile_allCoverFeatures {
    HAEntity *entity = [HASnapshotTestHelpers coverScPosTilt];
    [self verifyTileForEntity:entity features:@[
        @{@"type": @"cover-open-close"},
        @{@"type": @"cover-position"},
        @{@"type": @"cover-tilt-position"}
    ]];
}

#pragma mark - Climate

- (void)testClimateTile_hvacModes {
    HAEntity *entity = [HASnapshotTestHelpers climateScHeating];
    [self verifyTileForEntity:entity features:@[@{@"type": @"climate-hvac-modes"}]];
}

- (void)testClimateTile_presetModes {
    HAEntity *entity = [HASnapshotTestHelpers climateScPresets];
    [self verifyTileForEntity:entity features:@[@{@"type": @"climate-preset-modes"}]];
}

- (void)testClimateTile_fanModes {
    HAEntity *entity = [HASnapshotTestHelpers climateScFan];
    [self verifyTileForEntity:entity features:@[@{@"type": @"climate-fan-modes"}]];
}

- (void)testClimateTile_targetTemperature {
    HAEntity *entity = [HASnapshotTestHelpers climateScCooling];
    [self verifyTileForEntity:entity features:@[@{@"type": @"target-temperature"}]];
}

- (void)testClimateTile_hvacAndPreset {
    HAEntity *entity = [HASnapshotTestHelpers climateScPresets];
    [self verifyTileForEntity:entity features:@[
        @{@"type": @"climate-hvac-modes"},
        @{@"type": @"climate-preset-modes"}
    ]];
}

- (void)testClimateTile_allClimateFeatures {
    HAEntity *entity = [HASnapshotTestHelpers climateScAll];
    [self verifyTileForEntity:entity features:@[
        @{@"type": @"climate-hvac-modes"},
        @{@"type": @"climate-preset-modes"},
        @{@"type": @"climate-fan-modes"},
        @{@"type": @"target-temperature"}
    ]];
}

#pragma mark - Fan

- (void)testFanTile_speed {
    HAEntity *entity = [HASnapshotTestHelpers fanScBasic];
    [self verifyTileForEntity:entity features:@[@{@"type": @"fan-speed"}]];
}

#pragma mark - Lock

- (void)testLockTile_commands {
    HAEntity *entity = [HASnapshotTestHelpers lockScLocked];
    [self verifyTileForEntity:entity features:@[@{@"type": @"lock-commands"}]];
}

#pragma mark - Vacuum

- (void)testVacuumTile_commands {
    HAEntity *entity = [HASnapshotTestHelpers vacuumScCleaning];
    [self verifyTileForEntity:entity features:@[@{@"type": @"vacuum-commands"}]];
}

#pragma mark - Humidifier

- (void)testHumidifierTile_modes {
    HAEntity *entity = [HASnapshotTestHelpers humidifierScOn];
    [self verifyTileForEntity:entity features:@[@{@"type": @"humidifier-modes"}]];
}

#pragma mark - Alarm

- (void)testAlarmTile_modes {
    HAEntity *entity = [HASnapshotTestHelpers alarmScDisarmed];
    [self verifyTileForEntity:entity features:@[@{@"type": @"alarm-modes"}]];
}

#pragma mark - Counter / Numeric

- (void)testCounterTile_numericInput {
    HAEntity *entity = [HASnapshotTestHelpers counterSc];
    [self verifyTileForEntity:entity features:@[@{@"type": @"numeric-input"}]];
}

#pragma mark - Media Player

- (void)testMediaPlayerTile_volume {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerScFull];
    [self verifyTileForEntity:entity features:@[@{@"type": @"media-player-volume"}]];
}

@end
