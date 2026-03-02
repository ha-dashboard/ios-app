#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HATileEntityCell.h"
#import "HAGlanceCardCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"

/// Phase 2 display configuration variant snapshot tests – Batch 2.
/// Covers: cover, lock, fan, alarm_control_panel, media_player.
@interface HADisplayConfigSnapshotTests_Batch2 : HABaseSnapshotTestCase
@end

@implementation HADisplayConfigSnapshotTests_Batch2

#pragma mark - Cover – Tile

- (void)testCoverTile_default {
    HAEntity *entity = [HASnapshotTestHelpers coverScPosition];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers coverScPosition];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_state": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers coverScPosition];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_name": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverTile_iconOverride {
    HAEntity *entity = [HASnapshotTestHelpers coverScPosition];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"icon_override": @"mdi:window-shutter"};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverTile_nameOverride {
    HAEntity *entity = [HASnapshotTestHelpers coverScPosition];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.displayName = @"Office Blinds";
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Cover – Button Card

- (void)testCoverButton_default {
    HAEntity *entity = [HASnapshotTestHelpers coverScPosition];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button-card" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testCoverButton_showStateTrue {
    HAEntity *entity = [HASnapshotTestHelpers coverScPosition];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button-card" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_state": @YES};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Lock – Tile

- (void)testLockTile_default {
    HAEntity *entity = [HASnapshotTestHelpers lockScLocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLockTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers lockScLocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_state": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLockTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers lockScLocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_name": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLockTile_iconOverride {
    HAEntity *entity = [HASnapshotTestHelpers lockScLocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"icon_override": @"mdi:lock-alert"};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Lock – Button Card

- (void)testLockButton_default {
    HAEntity *entity = [HASnapshotTestHelpers lockScLocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button-card" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testLockButton_showStateTrue {
    HAEntity *entity = [HASnapshotTestHelpers lockScLocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button-card" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_state": @YES};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Fan – Tile

- (void)testFanTile_default {
    HAEntity *entity = [HASnapshotTestHelpers fanScBasic];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testFanTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers fanScBasic];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_state": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testFanTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers fanScBasic];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_name": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testFanTile_iconOverride {
    HAEntity *entity = [HASnapshotTestHelpers fanScBasic];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"icon_override": @"mdi:fan-alert"};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Fan – Button Card

- (void)testFanButton_default {
    HAEntity *entity = [HASnapshotTestHelpers fanScBasic];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button-card" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testFanButton_showStateTrue {
    HAEntity *entity = [HASnapshotTestHelpers fanScBasic];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button-card" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_state": @YES};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Alarm – Tile

- (void)testAlarmTile_default {
    HAEntity *entity = [HASnapshotTestHelpers alarmScDisarmed];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testAlarmTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers alarmScDisarmed];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_state": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testAlarmTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers alarmScDisarmed];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_name": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Media Player – Tile

- (void)testMediaPlayerTile_default {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerScFull];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testMediaPlayerTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerScFull];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_state": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testMediaPlayerTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerScFull];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_name": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testMediaPlayerTile_iconOverride {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerScFull];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"icon_override": @"mdi:speaker-wireless"};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Media Player – Button Card

- (void)testMediaPlayerButton_default {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerScFull];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button-card" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testMediaPlayerButton_showStateTrue {
    HAEntity *entity = [HASnapshotTestHelpers mediaPlayerScFull];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button-card" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_state": @YES};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Media Player – Glance

- (void)testMediaPlayerGlance_default {
    HAEntity *entity1 = [HASnapshotTestHelpers mediaPlayerScFull];
    HAEntity *entity2 = [HASnapshotTestHelpers mediaPlayerScFull];
    HAEntity *entity3 = [HASnapshotTestHelpers mediaPlayerScFull];
    NSDictionary *entities = @{
        entity1.entityId: entity1,
        entity2.entityId: entity2,
        entity3.entityId: entity3,
    };
    NSArray *entityIds = @[entity1.entityId, entity2.entityId, entity3.entityId];
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:@"Media Players"
        icon:nil entityIds:entityIds];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entityIds.firstObject
        cardType:@"glance" columnSpan:12 headingIcon:nil displayName:nil];
    UIView *cell = [self compositeCell:[HAGlanceCardCell class]
        size:CGSizeMake(kColumnWidth, 120.0) section:section entities:entities configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testMediaPlayerGlance_showNameFalse {
    HAEntity *entity1 = [HASnapshotTestHelpers mediaPlayerScFull];
    HAEntity *entity2 = [HASnapshotTestHelpers mediaPlayerScFull];
    HAEntity *entity3 = [HASnapshotTestHelpers mediaPlayerScFull];
    NSDictionary *entities = @{
        entity1.entityId: entity1,
        entity2.entityId: entity2,
        entity3.entityId: entity3,
    };
    NSArray *entityIds = @[entity1.entityId, entity2.entityId, entity3.entityId];
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:@"Media Players"
        icon:nil entityIds:entityIds];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entityIds.firstObject
        cardType:@"glance" columnSpan:12 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_name": @NO};
    UIView *cell = [self compositeCell:[HAGlanceCardCell class]
        size:CGSizeMake(kColumnWidth, 120.0) section:section entities:entities configItem:item];
    [self verifyView:cell identifier:nil];
}

@end
