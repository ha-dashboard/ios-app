#import <XCTest/XCTest.h>
#import "FBSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"
#import "HAThermostatGaugeCell.h"
#import "HAVacuumEntityCell.h"
#import "HAEntitiesCardCell.h"
#import "HAHeadingCell.h"
#import "HABaseEntityCell.h"
#import "HATheme.h"

/// Column width for a 3-column iPad layout (1024pt landscape, minus padding).
/// Each column is roughly 320pt. Sub-grid items divide this by 12.
static const CGFloat kColumnWidth = 320.0;
static const CGFloat kSubGridUnit = 320.0 / 12.0; // ~26.7pt per sub-grid column

/// Standard cell heights for snapshot tests.
static const CGFloat kThermostatHeight = 280.0;
static const CGFloat kVacuumHeight = 120.0;
static const CGFloat kEntitiesRowHeight = 36.0;
static const CGFloat kHeadingExtra = 30.0; // kHeadingHeight(28) + kHeadingGap(2)
static const CGFloat kHeadingCellHeight = 40.0;

@interface HAHeadingSnapshotTests : FBSnapshotTestCase
@end

@implementation HAHeadingSnapshotTests

- (void)setUp {
    [super setUp];
#ifdef RECORD_SNAPSHOTS
    self.recordMode = YES;
#else
    self.recordMode = NO;
#endif
    self.usesDrawViewHierarchyInRect = YES;
}

/// Override to point at our source tree ReferenceImages directory.
///
/// See the matching override in HABaseSnapshotTestCase.m: set
/// HA_SNAPSHOT_RUNTIME_SUFFIX to record/compare against an OS-tagged
/// directory without touching the existing "ReferenceImages_64" set.
- (NSString *)getReferenceImageDirectoryWithDefault:(NSString *)dir {
    NSString *thisFile = @__FILE__;
    NSString *testDir = [thisFile stringByDeletingLastPathComponent];
#ifdef HA_SNAPSHOT_RUNTIME_SUFFIX
    NSString *runtimeSuffix = @HA_SNAPSHOT_RUNTIME_SUFFIX;
#else
    NSString *runtimeSuffix = @"";
#endif
    NSString *folderName = [@"ReferenceImages" stringByAppendingString:runtimeSuffix];
    return [testDir stringByAppendingPathComponent:folderName];
}

/// Override to point at our source tree FailureDiffs directory.
- (NSString *)getImageDiffDirectoryWithDefault:(NSString *)dir {
    NSString *thisFile = @__FILE__;
    NSString *testDir = [thisFile stringByDeletingLastPathComponent];
    return [testDir stringByAppendingPathComponent:@"FailureDiffs"];
}

#pragma mark - Individual Cell Tests

/// Thermostat cell at 9/12 column width with "House Climate" heading above.
/// Verifies the headingIcon renders correctly on HABaseEntityCell subclass.
- (void)testThermostatWithHeading_9col {
    CGFloat width = floor(kSubGridUnit * 9);
    CGFloat height = kThermostatHeight + kHeadingExtra;

    HAThermostatGaugeCell *cell = [[HAThermostatGaugeCell alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    HAEntity *entity = [HASnapshotTestHelpers entityWithId:@"climate.aidoo"
        state:@"heat"
        attributes:@{
            @"friendly_name": @"Aidoo",
            @"current_temperature": @22.0,
            @"temperature": @22.0,
            @"hvac_action": @"idle",
            @"hvac_modes": @[@"off", @"heat", @"cool", @"auto"],
            @"temperature_unit": @"\u00B0C"
        }];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"climate.aidoo"
        cardType:@"thermostat" columnSpan:9 headingIcon:@"mdi:hvac" displayName:@"House Climate"];

    [cell configureWithEntity:entity configItem:item];
    [cell layoutIfNeeded];

    FBSnapshotVerifyView(cell, nil);
}

/// Vacuum cell at 3/12 column width with "Ribbit" heading.
/// Verifies heading fits in narrow cells without truncation.
- (void)testVacuumWithHeading_3col {
    CGFloat width = floor(kSubGridUnit * 3);
    CGFloat height = kVacuumHeight + kHeadingExtra;

    HAVacuumEntityCell *cell = [[HAVacuumEntityCell alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    HAEntity *entity = [HASnapshotTestHelpers entityWithId:@"vacuum.saros_10"
        state:@"docked"
        attributes:@{
            @"friendly_name": @"Ribbit",
            @"battery_level": @100,
            @"status": @"Docked"
        }];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"vacuum.saros_10"
        cardType:@"vacuum" columnSpan:3 headingIcon:@"mdi:robot-vacuum" displayName:@"Ribbit"];

    [cell configureWithEntity:entity configItem:item];
    [cell layoutIfNeeded];

    FBSnapshotVerifyView(cell, nil);
}

/// Entities card at 8/12 width with "Lights" heading above, 3 entity rows.
/// Verifies heading-above on HAEntitiesCardCell (composite card).
- (void)testEntitiesCardWithHeading_8col {
    CGFloat width = floor(kSubGridUnit * 8);
    NSInteger entityCount = 3;
    CGFloat height = (entityCount * kEntitiesRowHeight) + kHeadingExtra;

    HAEntitiesCardCell *cell = [[HAEntitiesCardCell alloc] initWithFrame:CGRectMake(0, 0, width, height)];

    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:nil
        icon:@"mdi:ceiling-light-multiple"
        entityIds:@[@"light.office_3", @"light.downstairs", @"light.upstairs"]];

    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"light.office_3"
        cardType:@"entities" columnSpan:8 headingIcon:@"mdi:ceiling-light-multiple" displayName:@"Lights"];
    item.entitiesSection = section;

    NSDictionary *entities = [HASnapshotTestHelpers livingRoomEntities];
    [cell configureWithSection:section entities:entities configItem:item];
    [cell layoutIfNeeded];

    FBSnapshotVerifyView(cell, nil);
}

/// Entities card without heading — just an internal title.
/// Verifies no heading appears above the card.
- (void)testEntitiesCardWithoutHeading {
    CGFloat width = kColumnWidth;
    NSInteger entityCount = 3;
    CGFloat titleHeight = 30.0;
    CGFloat height = (entityCount * kEntitiesRowHeight) + titleHeight;

    HAEntitiesCardCell *cell = [[HAEntitiesCardCell alloc] initWithFrame:CGRectMake(0, 0, width, height)];

    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:@"Spa Controls"
        icon:nil
        entityIds:@[@"light.office_3", @"light.downstairs", @"light.upstairs"]];

    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"light.office_3"
        cardType:@"entities" columnSpan:12 headingIcon:nil displayName:nil];
    item.entitiesSection = section;

    NSDictionary *entities = [HASnapshotTestHelpers livingRoomEntities];
    [cell configureWithSection:section entities:entities configItem:item];
    [cell layoutIfNeeded];

    FBSnapshotVerifyView(cell, nil);
}

/// Standalone HAHeadingCell at full width with icon.
/// For grids without explicit columns (e.g., Printy).
- (void)testHeadingCellStandalone_12col {
    CGFloat width = kColumnWidth;

    HAHeadingCell *cell = [[HAHeadingCell alloc] initWithFrame:CGRectMake(0, 0, width, kHeadingCellHeight)];

    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.cardType = @"heading";
    item.displayName = @"Printy";
    item.columnSpan = 12;
    item.customProperties = @{@"icon": @"mdi:printer-3d"};

    [cell configureWithItem:item];
    [cell layoutIfNeeded];

    FBSnapshotVerifyView(cell, nil);
}

#pragma mark - Layout Regression Tests

/// Two cells side-by-side: thermostat(9) + vacuum(3) = 12.
/// Living-room pattern: "House Climate" and "Ribbit" must be on the SAME row.
/// This is the critical regression test — converting headingIcon to standalone
/// items with columnSpan=12 breaks this layout.
- (void)testSideBySideLayout_9plus3 {
    CGFloat totalWidth = kColumnWidth;
    CGFloat thermoWidth = floor(totalWidth * 9.0 / 12.0);
    CGFloat vacuumWidth = totalWidth - thermoWidth;
    CGFloat rowHeight = kThermostatHeight + kHeadingExtra;

    // Container view simulating one row of the sub-grid
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, totalWidth, rowHeight)];
    container.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];

    // Thermostat at (0, 0) — 9/12 width
    HAThermostatGaugeCell *thermoCell = [[HAThermostatGaugeCell alloc]
        initWithFrame:CGRectMake(0, 0, thermoWidth, rowHeight)];
    HAEntity *thermoEntity = [[HASnapshotTestHelpers livingRoomEntities] objectForKey:@"climate.aidoo"];
    HADashboardConfigItem *thermoItem = [HASnapshotTestHelpers itemWithEntityId:@"climate.aidoo"
        cardType:@"thermostat" columnSpan:9 headingIcon:@"mdi:hvac" displayName:@"House Climate"];
    [thermoCell configureWithEntity:thermoEntity configItem:thermoItem];
    [thermoCell layoutIfNeeded];
    [container addSubview:thermoCell];

    // Vacuum at (thermoWidth, 0) — 3/12 width
    HAVacuumEntityCell *vacuumCell = [[HAVacuumEntityCell alloc]
        initWithFrame:CGRectMake(thermoWidth, 0, vacuumWidth, rowHeight)];
    HAEntity *vacuumEntity = [[HASnapshotTestHelpers livingRoomEntities] objectForKey:@"vacuum.saros_10"];
    HADashboardConfigItem *vacuumItem = [HASnapshotTestHelpers itemWithEntityId:@"vacuum.saros_10"
        cardType:@"vacuum" columnSpan:3 headingIcon:@"mdi:robot-vacuum" displayName:@"Ribbit"];
    [vacuumCell configureWithEntity:vacuumEntity configItem:vacuumItem];
    [vacuumCell layoutIfNeeded];
    [container addSubview:vacuumCell];

    FBSnapshotVerifyView(container, nil);
}

/// Two cells side-by-side: entities(8) + vacuum(4) = 12.
/// Landing pattern: "Lights" entities card and "Ribbit" vacuum must share a row.
- (void)testSideBySideLayout_8plus4 {
    CGFloat totalWidth = kColumnWidth;
    CGFloat entWidth = floor(totalWidth * 8.0 / 12.0);
    CGFloat vacWidth = totalWidth - entWidth;
    NSInteger entityCount = 3;
    CGFloat rowHeight = MAX(entityCount * kEntitiesRowHeight, kVacuumHeight) + kHeadingExtra;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, totalWidth, rowHeight)];
    container.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];

    // Entities card at (0, 0) — 8/12 width
    HAEntitiesCardCell *entCell = [[HAEntitiesCardCell alloc]
        initWithFrame:CGRectMake(0, 0, entWidth, rowHeight)];
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:nil
        icon:@"mdi:ceiling-light-multiple"
        entityIds:@[@"light.office_3", @"light.downstairs", @"light.upstairs"]];
    HADashboardConfigItem *entItem = [HASnapshotTestHelpers itemWithEntityId:@"light.office_3"
        cardType:@"entities" columnSpan:8 headingIcon:@"mdi:ceiling-light-multiple" displayName:@"Lights"];
    entItem.entitiesSection = section;
    NSDictionary *entities = [HASnapshotTestHelpers livingRoomEntities];
    [entCell configureWithSection:section entities:entities configItem:entItem];
    [entCell layoutIfNeeded];
    [container addSubview:entCell];

    // Vacuum at (entWidth, 0) — 4/12 width
    HAVacuumEntityCell *vacCell = [[HAVacuumEntityCell alloc]
        initWithFrame:CGRectMake(entWidth, 0, vacWidth, rowHeight)];
    HAEntity *vacEntity = [entities objectForKey:@"vacuum.saros_10"];
    HADashboardConfigItem *vacItem = [HASnapshotTestHelpers itemWithEntityId:@"vacuum.saros_10"
        cardType:@"vacuum" columnSpan:4 headingIcon:@"mdi:robot-vacuum" displayName:@"Ribbit"];
    [vacCell configureWithEntity:vacEntity configItem:vacItem];
    [vacCell layoutIfNeeded];
    [container addSubview:vacCell];

    FBSnapshotVerifyView(container, nil);
}

@end
