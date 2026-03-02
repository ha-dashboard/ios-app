#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HAGlanceCardCell.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"

static const CGFloat kGlanceWidth = 320.0;

@interface HAGlanceSnapshotTests : HABaseSnapshotTestCase
@end

@implementation HAGlanceSnapshotTests

#pragma mark - Helpers

/// Create a glance card config item with the given customProperties.
- (HADashboardConfigItem *)glanceItemWithProperties:(NSDictionary *)props {
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.cardType = @"glance";
    item.columnSpan = 12;
    item.rowSpan = 1;
    item.customProperties = props;
    return item;
}

/// Create and configure a glance card cell.
- (UIView *)glanceCellWithSection:(HADashboardConfigSection *)section
                         entities:(NSDictionary<NSString *, HAEntity *> *)entities
                       configItem:(HADashboardConfigItem *)configItem
                           height:(CGFloat)height {
    CGSize size = CGSizeMake(kGlanceWidth, height);
    return [self compositeCell:[HAGlanceCardCell class]
                          size:size
                       section:section
                      entities:entities
                    configItem:configItem];
}

#pragma mark - Standard Entity Set

- (NSDictionary<NSString *, HAEntity *> *)glanceEntities {
    NSMutableDictionary *entities = [NSMutableDictionary dictionary];
    entities[@"sensor.living_room_temperature"] = [HASnapshotTestHelpers sensorTemperature];
    entities[@"sensor.living_room_humidity"]    = [HASnapshotTestHelpers sensorHumidity];
    entities[@"light.kitchen"]                  = [HASnapshotTestHelpers lightEntityOnBrightness];
    entities[@"binary_sensor.front_door"]       = [HASnapshotTestHelpers binarySensorDoorOff];
    entities[@"lock.frontdoor"]                 = [HASnapshotTestHelpers lockLocked];
    entities[@"sensor.phone_battery"]           = [HASnapshotTestHelpers sensorBattery];
    return [entities copy];
}

#pragma mark - Tests: 4 Entities

- (void)testGlance4Entities {
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:nil icon:nil
        entityIds:@[@"sensor.living_room_temperature", @"sensor.living_room_humidity",
                    @"light.kitchen", @"binary_sensor.front_door"]];
    HADashboardConfigItem *item = [self glanceItemWithProperties:@{
        @"glance_title": @"Home Overview"
    }];
    CGFloat height = [HAGlanceCardCell preferredHeightForSection:section width:kGlanceWidth configItem:item];
    UIView *cell = [self glanceCellWithSection:section entities:[self glanceEntities] configItem:item height:height];
    [self verifyView:cell identifier:@"glance4Entities"];
}

#pragma mark - Tests: 6 Entities

- (void)testGlance6Entities {
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:nil icon:nil
        entityIds:@[@"sensor.living_room_temperature", @"sensor.living_room_humidity",
                    @"light.kitchen", @"binary_sensor.front_door",
                    @"lock.frontdoor", @"sensor.phone_battery"]];
    HADashboardConfigItem *item = [self glanceItemWithProperties:@{
        @"glance_title": @"Home Overview"
    }];
    CGFloat height = [HAGlanceCardCell preferredHeightForSection:section width:kGlanceWidth configItem:item];
    UIView *cell = [self glanceCellWithSection:section entities:[self glanceEntities] configItem:item height:height];
    [self verifyView:cell identifier:@"glance6Entities"];
}

#pragma mark - Tests: Custom Columns

- (void)testGlance3Columns {
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:nil icon:nil
        entityIds:@[@"sensor.living_room_temperature", @"sensor.living_room_humidity",
                    @"light.kitchen", @"binary_sensor.front_door",
                    @"lock.frontdoor", @"sensor.phone_battery"]];
    HADashboardConfigItem *item = [self glanceItemWithProperties:@{
        @"glance_title": @"3 Columns",
        @"columns": @3
    }];
    CGFloat height = [HAGlanceCardCell preferredHeightForSection:section width:kGlanceWidth configItem:item];
    UIView *cell = [self glanceCellWithSection:section entities:[self glanceEntities] configItem:item height:height];
    [self verifyView:cell identifier:@"glance3Columns"];
}

#pragma mark - Tests: show_name=NO

- (void)testGlanceNoName {
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:nil icon:nil
        entityIds:@[@"sensor.living_room_temperature", @"sensor.living_room_humidity",
                    @"light.kitchen", @"binary_sensor.front_door"]];
    HADashboardConfigItem *item = [self glanceItemWithProperties:@{
        @"show_name": @NO
    }];
    CGFloat height = [HAGlanceCardCell preferredHeightForSection:section width:kGlanceWidth configItem:item];
    UIView *cell = [self glanceCellWithSection:section entities:[self glanceEntities] configItem:item height:height];
    [self verifyView:cell identifier:@"glanceNoName"];
}

#pragma mark - Tests: show_state=NO

- (void)testGlanceNoState {
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:nil icon:nil
        entityIds:@[@"sensor.living_room_temperature", @"sensor.living_room_humidity",
                    @"light.kitchen", @"binary_sensor.front_door"]];
    HADashboardConfigItem *item = [self glanceItemWithProperties:@{
        @"show_state": @NO
    }];
    CGFloat height = [HAGlanceCardCell preferredHeightForSection:section width:kGlanceWidth configItem:item];
    UIView *cell = [self glanceCellWithSection:section entities:[self glanceEntities] configItem:item height:height];
    [self verifyView:cell identifier:@"glanceNoState"];
}

#pragma mark - Tests: state_color=YES (active entities)

- (void)testGlanceStateColor {
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:nil icon:nil
        entityIds:@[@"light.kitchen", @"lock.frontdoor",
                    @"sensor.living_room_temperature", @"binary_sensor.front_door"]];
    HADashboardConfigItem *item = [self glanceItemWithProperties:@{
        @"state_color": @YES,
        @"glance_title": @"State Colors"
    }];
    CGFloat height = [HAGlanceCardCell preferredHeightForSection:section width:kGlanceWidth configItem:item];
    UIView *cell = [self glanceCellWithSection:section entities:[self glanceEntities] configItem:item height:height];
    [self verifyView:cell identifier:@"glanceStateColor"];
}

@end
