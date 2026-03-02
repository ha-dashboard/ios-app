#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HATileEntityCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"

/// Phase 2 snapshot tests: display configuration variants for tile and button cards.
/// Covers input_boolean, input_number, input_select, input_text, input_datetime,
/// timer, counter, update, automation, water_heater, valve, lawn_mower, remote,
/// and device_tracker domains.
@interface HADisplayConfigSnapshotTests_Batch4 : HABaseSnapshotTestCase
@end

@implementation HADisplayConfigSnapshotTests_Batch4

#pragma mark - Helpers

/// Create a tile config item with optional custom properties.
- (HADashboardConfigItem *)tileItemForEntity:(HAEntity *)entity
                                       props:(NSDictionary *)props
                                 displayName:(NSString *)displayName {
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:displayName];
    if (props) item.customProperties = props;
    return item;
}

/// Create a button config item with optional custom properties.
- (HADashboardConfigItem *)buttonItemForEntity:(HAEntity *)entity
                                         props:(NSDictionary *)props
                                   displayName:(NSString *)displayName {
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button" columnSpan:6 headingIcon:nil displayName:displayName];
    if (props) item.customProperties = props;
    return item;
}

/// Render a tile/button cell at standard tile size.
- (UIView *)tileCellForEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)item {
    CGFloat width = floor(kSubGridUnit * 6);
    return [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(width, kTileHeight) configItem:item];
}

#pragma mark - Input Boolean: Tile Card

- (void)testInputBooleanTile_default {
    HAEntity *entity = [HASnapshotTestHelpers inputBooleanScOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testInputBooleanTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers inputBooleanScOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testInputBooleanTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers inputBooleanScOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_name": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Input Number: Tile Card

- (void)testInputNumberTile_default {
    HAEntity *entity = [HASnapshotTestHelpers inputNumberScSlider];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testInputNumberTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers inputNumberScSlider];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Input Select: Tile Card

- (void)testInputSelectTile_default {
    HAEntity *entity = [HASnapshotTestHelpers inputSelectSc];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testInputSelectTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers inputSelectSc];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Input Text: Tile Card

- (void)testInputTextTile_default {
    HAEntity *entity = [HASnapshotTestHelpers inputTextScText];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testInputTextTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers inputTextScText];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Input DateTime: Tile Card

- (void)testInputDateTimeTile_default {
    HAEntity *entity = [HASnapshotTestHelpers inputDateTimeScDate];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testInputDateTimeTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers inputDateTimeScDate];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Timer: Tile Card

- (void)testTimerTile_default {
    HAEntity *entity = [HASnapshotTestHelpers timerScActive];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testTimerTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers timerScActive];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testTimerTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers timerScActive];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_name": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Counter: Tile Card

- (void)testCounterTile_default {
    HAEntity *entity = [HASnapshotTestHelpers counterSc];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCounterTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers counterSc];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Update: Tile Card

- (void)testUpdateTile_default {
    HAEntity *entity = [HASnapshotTestHelpers updateScAvailable];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testUpdateTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers updateScAvailable];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testUpdateTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers updateScAvailable];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_name": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Automation: Tile Card

- (void)testAutomationTile_default {
    HAEntity *entity = [HASnapshotTestHelpers automationSc];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testAutomationTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers automationSc];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testAutomationTile_iconOverride {
    HAEntity *entity = [HASnapshotTestHelpers automationSc];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"icon": @"mdi:robot"} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Automation: Button Card

- (void)testAutomationButton_default {
    HAEntity *entity = [HASnapshotTestHelpers automationSc];
    HADashboardConfigItem *item = [self buttonItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Water Heater: Tile Card

- (void)testWaterHeaterTile_default {
    HAEntity *entity = [HASnapshotTestHelpers waterHeaterSc];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testWaterHeaterTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers waterHeaterSc];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Valve: Tile Card

- (void)testValveTile_default {
    HAEntity *entity = [HASnapshotTestHelpers valveScOpen];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testValveTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers valveScOpen];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testValveTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers valveScOpen];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_name": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Lawn Mower: Tile Card

- (void)testLawnMowerTile_default {
    HAEntity *entity = [HASnapshotTestHelpers lawnMowerScDocked];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLawnMowerTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers lawnMowerScDocked];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Remote: Tile Card

- (void)testRemoteTile_default {
    HAEntity *entity = [HASnapshotTestHelpers remoteSc];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testRemoteTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers remoteSc];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Device Tracker: Tile Card

- (void)testDeviceTrackerTile_default {
    HAEntity *entity = [HASnapshotTestHelpers deviceTrackerScHome];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testDeviceTrackerTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers deviceTrackerScHome];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

@end
