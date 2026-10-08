#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HASensorEntityCell.h"
#import "HACounterEntityCell.h"
#import "HATimerEntityCell.h"
#import "HAUpdateEntityCell.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"
#import "HABaseEntityCell.h"

@interface HASensorSnapshotTests : HABaseSnapshotTestCase
@end

@implementation HASensorSnapshotTests

#pragma mark - HASensorEntityCell (6 variants)

- (void)testSensorTemperature {
    HAEntity *entity = [HASnapshotTestHelpers sensorTemperature];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorHumidity {
    HAEntity *entity = [HASnapshotTestHelpers sensorHumidity];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorEnergy {
    HAEntity *entity = [HASnapshotTestHelpers sensorEnergy];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorBattery {
    HAEntity *entity = [HASnapshotTestHelpers sensorBattery];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorIlluminance {
    HAEntity *entity = [HASnapshotTestHelpers sensorIlluminance];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorGenericText {
    HAEntity *entity = [HASnapshotTestHelpers sensorGenericText];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HACounterEntityCell (2 variants)

- (void)testCounterLow {
    HAEntity *entity = [HASnapshotTestHelpers counterLow];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"counter" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HACounterEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCounterHigh {
    HAEntity *entity = [HASnapshotTestHelpers counterHigh];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"counter" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HACounterEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HATimerEntityCell (3 variants)

- (void)testTimerActive {
    HAEntity *entity = [HASnapshotTestHelpers timerActive];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"timer" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATimerEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kGenericCardHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testTimerPaused {
    HAEntity *entity = [HASnapshotTestHelpers timerPaused];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"timer" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATimerEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kGenericCardHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testTimerIdle {
    HAEntity *entity = [HASnapshotTestHelpers timerIdle];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"timer" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATimerEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kGenericCardHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HAUpdateEntityCell (2 variants)

- (void)testUpdateAvailable {
    HAEntity *entity = [HASnapshotTestHelpers updateAvailable];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"update" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAUpdateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testUpdateUpToDate {
    HAEntity *entity = [HASnapshotTestHelpers updateUpToDate];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"update" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HAUpdateEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kStandardCellHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Fallback-card-type badge (GitHub #19)

// An unmapped custom:* card (e.g. a mushroom-entity-card or any bubble-card
// type) with an "entity" key renders generically instead of vanishing, but
// HALovelaceParser stamps fallbackCardType on the item so HABaseEntityCell
// shows a small, subtle badge rather than looking indistinguishable from a
// fully-supported sensor card. See HALovelaceParser.isNativelySupportedCustomCardType:.
- (void)testSensorWithFallbackCardTypeBadge {
    HAEntity *entity = [HASnapshotTestHelpers sensorTemperature];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"custom:mushroom-entity-card" columnSpan:6 headingIcon:nil displayName:nil];
    item.fallbackCardType = @"custom:mushroom-entity-card";
    // Matches HADashboardViewController.heightForItemAtIndexPath:itemWidth:,
    // which adds +[HABaseEntityCell fallbackBadgeExtraHeight] to the standard
    // height whenever fallbackCardType is set, so the badge has breathing
    // room instead of crowding the "22.8°C" value above it.
    CGFloat height = kStandardCellHeight + [HABaseEntityCell fallbackBadgeExtraHeight];
    UIView *cell = [self cellForEntity:entity cellClass:[HASensorEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), height) configItem:item];
    [self verifyView:cell identifier:nil];
}

@end
