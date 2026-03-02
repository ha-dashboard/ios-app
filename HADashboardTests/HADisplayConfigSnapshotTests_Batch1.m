#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HATileEntityCell.h"
#import "HAGlanceCardCell.h"
#import "HAEntitiesCardCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"

/// Phase 2 snapshot tests: display configuration variants for tile, button, and glance cards.
/// Covers light, switch, sensor, binary_sensor, and climate domains.
@interface HADisplayConfigSnapshotTests_Batch1 : HABaseSnapshotTestCase
@end

@implementation HADisplayConfigSnapshotTests_Batch1

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

/// Create a glance config item with custom properties.
- (HADashboardConfigItem *)glanceItemWithProperties:(NSDictionary *)props {
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.cardType = @"glance";
    item.columnSpan = 12;
    item.rowSpan = 1;
    item.customProperties = props;
    return item;
}

/// Create and configure a glance card cell with dynamic height.
- (UIView *)glanceCellWithSection:(HADashboardConfigSection *)section
                         entities:(NSDictionary<NSString *, HAEntity *> *)entities
                       configItem:(HADashboardConfigItem *)configItem {
    CGFloat height = [HAGlanceCardCell preferredHeightForSection:section width:kColumnWidth configItem:configItem];
    return [self compositeCell:[HAGlanceCardCell class]
                          size:CGSizeMake(kColumnWidth, height)
                       section:section
                      entities:entities
                    configItem:configItem];
}

#pragma mark - Light: Tile Card

- (void)testLightTile_default {
    HAEntity *entity = [HASnapshotTestHelpers lightScBasicOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers lightScBasicOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers lightScBasicOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_name": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightTile_showIconFalse {
    HAEntity *entity = [HASnapshotTestHelpers lightScBasicOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_icon": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightTile_nameOverride {
    HAEntity *entity = [HASnapshotTestHelpers lightScBasicOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:@"Custom Light"];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightTile_iconOverride {
    HAEntity *entity = [HASnapshotTestHelpers lightScBasicOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"icon": @"mdi:lamp"} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Light: Button Card

- (void)testLightButton_default {
    HAEntity *entity = [HASnapshotTestHelpers lightScBasicOn];
    HADashboardConfigItem *item = [self buttonItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightButton_showStateTrue {
    HAEntity *entity = [HASnapshotTestHelpers lightScBasicOn];
    HADashboardConfigItem *item = [self buttonItemForEntity:entity props:@{@"show_state": @YES} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightButton_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers lightScBasicOn];
    HADashboardConfigItem *item = [self buttonItemForEntity:entity props:@{@"show_name": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Light: Glance Card

- (NSDictionary<NSString *, HAEntity *> *)lightGlanceEntities {
    return @{
        @"light.sc_basic_on":         [HASnapshotTestHelpers lightScBasicOn],
        @"light.sc_basic_off":        [HASnapshotTestHelpers lightScBasicOff],
        @"light.sc_color_temp":       [HASnapshotTestHelpers lightScColorTemp],
        @"light.sc_rgb":              [HASnapshotTestHelpers lightScRgb]
    };
}

- (HADashboardConfigSection *)lightGlanceSection {
    return [HASnapshotTestHelpers sectionWithTitle:nil icon:nil
        entityIds:@[@"light.sc_basic_on", @"light.sc_basic_off",
                    @"light.sc_color_temp", @"light.sc_rgb"]];
}

- (void)testLightGlance_default {
    HADashboardConfigSection *section = [self lightGlanceSection];
    HADashboardConfigItem *item = [self glanceItemWithProperties:nil];
    UIView *cell = [self glanceCellWithSection:section entities:[self lightGlanceEntities] configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightGlance_showNameFalse {
    HADashboardConfigSection *section = [self lightGlanceSection];
    HADashboardConfigItem *item = [self glanceItemWithProperties:@{@"show_name": @NO}];
    UIView *cell = [self glanceCellWithSection:section entities:[self lightGlanceEntities] configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightGlance_showStateFalse {
    HADashboardConfigSection *section = [self lightGlanceSection];
    HADashboardConfigItem *item = [self glanceItemWithProperties:@{@"show_state": @NO}];
    UIView *cell = [self glanceCellWithSection:section entities:[self lightGlanceEntities] configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLightGlance_stateColorFalse {
    HADashboardConfigSection *section = [self lightGlanceSection];
    HADashboardConfigItem *item = [self glanceItemWithProperties:@{@"state_color": @NO}];
    UIView *cell = [self glanceCellWithSection:section entities:[self lightGlanceEntities] configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Switch: Tile Card

- (void)testSwitchTile_default {
    HAEntity *entity = [HASnapshotTestHelpers switchEntityOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSwitchTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers switchEntityOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSwitchTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers switchEntityOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_name": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSwitchTile_nameOverride {
    HAEntity *entity = [HASnapshotTestHelpers switchEntityOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:@"Custom Switch"];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSwitchTile_iconOverride {
    HAEntity *entity = [HASnapshotTestHelpers switchEntityOn];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"icon": @"mdi:power-plug"} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Switch: Button Card

- (void)testSwitchButton_default {
    HAEntity *entity = [HASnapshotTestHelpers switchEntityOn];
    HADashboardConfigItem *item = [self buttonItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSwitchButton_showStateTrue {
    HAEntity *entity = [HASnapshotTestHelpers switchEntityOn];
    HADashboardConfigItem *item = [self buttonItemForEntity:entity props:@{@"show_state": @YES} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Sensor: Tile Card

- (void)testSensorTile_default {
    HAEntity *entity = [HASnapshotTestHelpers sensorScTemperature];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers sensorScTemperature];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers sensorScTemperature];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_name": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorTile_iconOverride {
    HAEntity *entity = [HASnapshotTestHelpers sensorScTemperature];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"icon": @"mdi:thermometer-alert"} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Sensor: Button Card

- (void)testSensorButton_default {
    HAEntity *entity = [HASnapshotTestHelpers sensorScTemperature];
    HADashboardConfigItem *item = [self buttonItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorButton_showStateTrue {
    HAEntity *entity = [HASnapshotTestHelpers sensorScTemperature];
    HADashboardConfigItem *item = [self buttonItemForEntity:entity props:@{@"show_state": @YES} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Sensor: Glance Card

- (NSDictionary<NSString *, HAEntity *> *)sensorGlanceEntities {
    return @{
        @"sensor.sc_temperature": [HASnapshotTestHelpers sensorScTemperature],
        @"sensor.sc_humidity":    [HASnapshotTestHelpers sensorScHumidity],
        @"sensor.sc_power":       [HASnapshotTestHelpers sensorScPower],
        @"sensor.sc_battery":     [HASnapshotTestHelpers sensorScBattery]
    };
}

- (HADashboardConfigSection *)sensorGlanceSection {
    return [HASnapshotTestHelpers sectionWithTitle:nil icon:nil
        entityIds:@[@"sensor.sc_temperature", @"sensor.sc_humidity",
                    @"sensor.sc_power", @"sensor.sc_battery"]];
}

- (void)testSensorGlance_default {
    HADashboardConfigSection *section = [self sensorGlanceSection];
    HADashboardConfigItem *item = [self glanceItemWithProperties:nil];
    UIView *cell = [self glanceCellWithSection:section entities:[self sensorGlanceEntities] configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSensorGlance_showNameFalse {
    HADashboardConfigSection *section = [self sensorGlanceSection];
    HADashboardConfigItem *item = [self glanceItemWithProperties:@{@"show_name": @NO}];
    UIView *cell = [self glanceCellWithSection:section entities:[self sensorGlanceEntities] configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Binary Sensor: Tile Card

- (void)testBinarySensorTile_default {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScDoorOpen];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScDoorOpen];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScDoorOpen];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_name": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testBinarySensorTile_iconOverride {
    HAEntity *entity = [HASnapshotTestHelpers binarySensorScDoorOpen];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"icon": @"mdi:door-closed-lock"} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Climate: Tile Card

- (void)testClimateTile_default {
    HAEntity *entity = [HASnapshotTestHelpers climateScHeating];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:nil displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testClimateTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers climateScHeating];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_state": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testClimateTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers climateScHeating];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"show_name": @NO} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testClimateTile_iconOverride {
    HAEntity *entity = [HASnapshotTestHelpers climateScHeating];
    HADashboardConfigItem *item = [self tileItemForEntity:entity props:@{@"icon": @"mdi:radiator"} displayName:nil];
    UIView *cell = [self tileCellForEntity:entity configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Climate: Glance Card

- (void)testClimateGlance_default {
    HAEntity *climateHeating = [HASnapshotTestHelpers climateScHeating];
    HAEntity *climateCooling = [HASnapshotTestHelpers climateScCooling];
    HAEntity *climateAuto    = [HASnapshotTestHelpers climateScHeatCool];
    HAEntity *climateOff     = [HASnapshotTestHelpers climateScOff];
    NSDictionary *entities = @{
        @"climate.sc_heating":   climateHeating,
        @"climate.sc_cooling":   climateCooling,
        @"climate.sc_heat_cool": climateAuto,
        @"climate.sc_off":       climateOff
    };
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:nil icon:nil
        entityIds:@[@"climate.sc_heating", @"climate.sc_cooling",
                    @"climate.sc_heat_cool", @"climate.sc_off"]];
    HADashboardConfigItem *item = [self glanceItemWithProperties:nil];
    UIView *cell = [self glanceCellWithSection:section entities:entities configItem:item];
    [self verifyView:cell identifier:nil];
}

@end
