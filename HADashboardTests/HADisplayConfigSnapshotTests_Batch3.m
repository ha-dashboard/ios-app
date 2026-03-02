#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HATileEntityCell.h"
#import "HAGlanceCardCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"

/// Phase 2 display configuration variant snapshot tests - Batch 3.
/// Domains: vacuum, humidifier, person, scene, script, button entity.
@interface HADisplayConfigSnapshotTests_Batch3 : HABaseSnapshotTestCase
@end

@implementation HADisplayConfigSnapshotTests_Batch3

#pragma mark - Vacuum Tile

- (void)testVacuumTile_default {
    HAEntity *entity = [HASnapshotTestHelpers vacuumScDocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testVacuumTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers vacuumScDocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_state": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testVacuumTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers vacuumScDocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_name": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testVacuumTile_iconOverride {
    HAEntity *entity = [HASnapshotTestHelpers vacuumScDocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"icon": @"mdi:broom"};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Vacuum Button Card

- (void)testVacuumButton_default {
    HAEntity *entity = [HASnapshotTestHelpers vacuumScDocked];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Humidifier Tile

- (void)testHumidifierTile_default {
    HAEntity *entity = [HASnapshotTestHelpers humidifierScOn];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testHumidifierTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers humidifierScOn];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_state": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testHumidifierTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers humidifierScOn];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_name": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Person Tile

- (void)testPersonTile_default {
    HAEntity *entity = [HASnapshotTestHelpers personScHome];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testPersonTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers personScHome];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_state": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testPersonTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers personScHome];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_name": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testPersonTile_iconOverride {
    HAEntity *entity = [HASnapshotTestHelpers personScHome];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"icon": @"mdi:face-man"};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Person Glance

- (void)testPersonGlance_default {
    HAEntity *home = [HASnapshotTestHelpers personScHome];
    HAEntity *away = [HASnapshotTestHelpers personScAway];
    HAEntity *zone = [HASnapshotTestHelpers personScZone];
    NSDictionary *entityDict = @{
        home.entityId: home,
        away.entityId: away,
        zone.entityId: zone
    };
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:@"People"
        icon:@"mdi:account-group" entityIds:@[home.entityId, away.entityId, zone.entityId]];
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.cardType = @"glance";
    item.columnSpan = 12;
    item.rowSpan = 1;
    UIView *cell = [self compositeCell:[HAGlanceCardCell class]
        size:CGSizeMake(kColumnWidth, 120.0) section:section entities:entityDict configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testPersonGlance_showStateFalse {
    HAEntity *home = [HASnapshotTestHelpers personScHome];
    HAEntity *away = [HASnapshotTestHelpers personScAway];
    HAEntity *zone = [HASnapshotTestHelpers personScZone];
    NSDictionary *entityDict = @{
        home.entityId: home,
        away.entityId: away,
        zone.entityId: zone
    };
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:@"People"
        icon:@"mdi:account-group" entityIds:@[home.entityId, away.entityId, zone.entityId]];
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.cardType = @"glance";
    item.columnSpan = 12;
    item.rowSpan = 1;
    item.customProperties = @{@"show_state": @NO};
    UIView *cell = [self compositeCell:[HAGlanceCardCell class]
        size:CGSizeMake(kColumnWidth, 120.0) section:section entities:entityDict configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Scene Tile

- (void)testSceneTile_default {
    HAEntity *entity = [HASnapshotTestHelpers sceneSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSceneTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers sceneSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_name": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSceneTile_iconOverride {
    HAEntity *entity = [HASnapshotTestHelpers sceneSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"icon": @"mdi:movie-open"};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Scene Button Card

- (void)testSceneButton_default {
    HAEntity *entity = [HASnapshotTestHelpers sceneSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testSceneButton_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers sceneSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_name": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Script Tile

- (void)testScriptTile_default {
    HAEntity *entity = [HASnapshotTestHelpers scriptSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testScriptTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers scriptSc];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_name": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Button Entity Tile

- (void)testButtonEntityTile_default {
    HAEntity *entity = [HASnapshotTestHelpers buttonDefault];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testButtonEntityTile_showStateFalse {
    HAEntity *entity = [HASnapshotTestHelpers buttonDefault];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_state": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testButtonEntityTile_showNameFalse {
    HAEntity *entity = [HASnapshotTestHelpers buttonDefault];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    item.customProperties = @{@"show_name": @NO};
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - Button Entity Button Card

- (void)testButtonEntityButton_default {
    HAEntity *entity = [HASnapshotTestHelpers buttonDefault];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"button" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(floor(kSubGridUnit * 6), kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

@end
