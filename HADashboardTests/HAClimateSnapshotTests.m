#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HAClimateEntityCell.h"
#import "HAThermostatGaugeCell.h"
#import "HAHumidifierEntityCell.h"
#import "HAWeatherEntityCell.h"
#import "HAClockWeatherCell.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"

@interface HAClimateSnapshotTests : HABaseSnapshotTestCase
@end

@implementation HAClimateSnapshotTests

#pragma mark - HAClimateEntityCell (6-col, kStandardCellHeight)

- (void)testClimateHeat {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityHeat];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"climate" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAClimateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testClimateCool {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityCool];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"climate" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAClimateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testClimateAuto {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityAuto];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"climate" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAClimateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testClimateOff {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityOff];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"climate" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAClimateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HAThermostatGaugeCell (9-col, kThermostatHeight)

- (void)testThermostatHeat {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityHeat];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"thermostat" columnSpan:9 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAThermostatGaugeCell class]
        size:CGSizeMake(floor(kSubGridUnit * 9), kThermostatHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testThermostatCool {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityCool];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"thermostat" columnSpan:9 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAThermostatGaugeCell class]
        size:CGSizeMake(floor(kSubGridUnit * 9), kThermostatHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testThermostatAuto {
    HAEntity *entity = [HASnapshotTestHelpers climateEntityAuto];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"thermostat" columnSpan:9 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAThermostatGaugeCell class]
        size:CGSizeMake(floor(kSubGridUnit * 9), kThermostatHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testThermostatShowCurrentAsPrimary {
    // TRV mode: current room temp shown large, target setpoint shown small below
    HAEntity *entity = [HASnapshotTestHelpers climateEntityHeat];
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.entityId = entity.entityId;
    item.cardType = @"thermostat";
    item.columnSpan = 9;
    item.rowSpan = 1;
    item.customProperties = @{@"show_current_as_primary": @YES};
    UIView *cell = [self cellForEntity:entity cellClass:[HAThermostatGaugeCell class]
        size:CGSizeMake(floor(kSubGridUnit * 9), kThermostatHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HAHumidifierEntityCell (6-col, kStandardCellHeight)

- (void)testHumidifierOn {
    HAEntity *entity = [HASnapshotTestHelpers humidifierOn];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"humidifier" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAHumidifierEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testHumidifierOff {
    HAEntity *entity = [HASnapshotTestHelpers humidifierOff];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"humidifier" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAHumidifierEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HAWeatherEntityCell (12-col, kWeatherHeight)

- (void)testWeatherSunny {
    HAEntity *entity = [HASnapshotTestHelpers weatherSunny];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"weather" columnSpan:12 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAWeatherEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 12), kWeatherHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testWeatherCloudy {
    HAEntity *entity = [HASnapshotTestHelpers weatherCloudy];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"weather" columnSpan:12 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAWeatherEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 12), kWeatherHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testWeatherRainy {
    HAEntity *entity = [HASnapshotTestHelpers weatherRainy];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"weather" columnSpan:12 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAWeatherEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 12), kWeatherHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HAClockWeatherCell (12-col, kClockWeatherHeight)

- (void)testClockWeatherSunny {
    HAEntity *entity = [HASnapshotTestHelpers clockWeatherSunny];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"clock-weather" columnSpan:12 headingIcon:nil displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 12), kClockWeatherHeight);
    HAClockWeatherCell *cell = [[HAClockWeatherCell alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
    cell.overrideDate = [self fixedTestDate];
    [cell configureWithEntity:entity configItem:item];
    [cell layoutIfNeeded];
    [self verifyView:cell identifier:nil];
}

- (void)testClockWeatherCloudy {
    HAEntity *entity = [HASnapshotTestHelpers clockWeatherCloudy];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"clock-weather" columnSpan:12 headingIcon:nil displayName:nil];
    CGSize size = CGSizeMake(floor(kSubGridUnit * 12), kClockWeatherHeight);
    HAClockWeatherCell *cell = [[HAClockWeatherCell alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
    cell.overrideDate = [self fixedTestDate];
    [cell configureWithEntity:entity configItem:item];
    [cell layoutIfNeeded];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Helpers

/// Returns a fixed date (2026-01-15 14:30:00 UTC) for deterministic clock rendering.
- (NSDate *)fixedTestDate {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.year = 2026;
    components.month = 1;
    components.day = 15;
    components.hour = 14;
    components.minute = 30;
    components.second = 0;
    components.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    return [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian] dateFromComponents:components];
}

@end
