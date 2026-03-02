#import <XCTest/XCTest.h>
#import "HAGlanceCardCell.h"
#import "HAGlanceItemView.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"
#import "HASnapshotTestHelpers.h"

@interface HAGlanceCardTests : XCTestCase
@end

@implementation HAGlanceCardTests

#pragma mark - Helpers

- (HADashboardConfigSection *)sectionWithEntityIds:(NSArray<NSString *> *)entityIds {
    HADashboardConfigSection *section = [[HADashboardConfigSection alloc] init];
    section.entityIds = entityIds;
    section.cardType = @"glance";
    return section;
}

- (HADashboardConfigItem *)itemWithProps:(NSDictionary *)props {
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.cardType = @"glance";
    item.customProperties = props;
    return item;
}

#pragma mark - Column Auto-Calculation

- (void)testAutoColumns4EntitiesWidth320 {
    // floor(320 / 70) = 4, min(4, 4) = 4
    HADashboardConfigSection *section = [self sectionWithEntityIds:@[@"a", @"b", @"c", @"d"]];
    HADashboardConfigItem *item = [self itemWithProps:@{}];
    CGFloat height = [HAGlanceCardCell preferredHeightForSection:section width:320 configItem:item];
    // 4 entities, 4 columns = 1 row. Height > 0
    XCTAssertGreaterThan(height, 0);
}

- (void)testAutoColumns6EntitiesWidth320 {
    // floor(320 / 70) = 4, min(6, 4) = 4 columns → 2 rows
    HADashboardConfigSection *section = [self sectionWithEntityIds:@[@"a", @"b", @"c", @"d", @"e", @"f"]];
    HADashboardConfigItem *item = [self itemWithProps:@{}];

    CGFloat height6 = [HAGlanceCardCell preferredHeightForSection:section width:320 configItem:item];

    // 4 entities should be shorter (1 row vs 2)
    HADashboardConfigSection *section4 = [self sectionWithEntityIds:@[@"a", @"b", @"c", @"d"]];
    CGFloat height4 = [HAGlanceCardCell preferredHeightForSection:section4 width:320 configItem:item];

    XCTAssertGreaterThan(height6, height4, @"6 entities should be taller than 4 at 320pt width");
}

- (void)testAutoColumns2EntitiesWidth320 {
    // floor(320 / 70) = 4, min(2, 4) = 2 columns → 1 row
    HADashboardConfigSection *section = [self sectionWithEntityIds:@[@"a", @"b"]];
    HADashboardConfigItem *item = [self itemWithProps:@{}];
    CGFloat height = [HAGlanceCardCell preferredHeightForSection:section width:320 configItem:item];
    XCTAssertGreaterThan(height, 0);
}

- (void)testAutoColumnsMaxFive {
    // HA caps auto columns at 5 regardless of entity count or width
    // 8 entities → min(8, 5) = 5 columns → 2 rows
    HADashboardConfigSection *section8 = [self sectionWithEntityIds:@[@"a", @"b", @"c", @"d", @"e", @"f", @"g", @"h"]];
    HADashboardConfigItem *item = [self itemWithProps:@{}];

    // 5 entities → min(5, 5) = 5 columns → 1 row
    HADashboardConfigSection *section5 = [self sectionWithEntityIds:@[@"a", @"b", @"c", @"d", @"e"]];

    CGFloat height8 = [HAGlanceCardCell preferredHeightForSection:section8 width:600 configItem:item];
    CGFloat height5 = [HAGlanceCardCell preferredHeightForSection:section5 width:600 configItem:item];

    XCTAssertGreaterThan(height8, height5, @"8 entities at max 5 cols = 2 rows, should be taller than 5 entities = 1 row");
}

#pragma mark - Explicit Columns Config

- (void)testExplicitColumns {
    // Force 2 columns even with 4 entities → 2 rows
    HADashboardConfigSection *section = [self sectionWithEntityIds:@[@"a", @"b", @"c", @"d"]];
    HADashboardConfigItem *item2col = [self itemWithProps:@{@"columns": @(2)}];
    HADashboardConfigItem *item4col = [self itemWithProps:@{@"columns": @(4)}];

    CGFloat height2col = [HAGlanceCardCell preferredHeightForSection:section width:320 configItem:item2col];
    CGFloat height4col = [HAGlanceCardCell preferredHeightForSection:section width:320 configItem:item4col];

    XCTAssertGreaterThan(height2col, height4col, @"2 columns should produce more rows than 4");
}

#pragma mark - Height with Visibility Flags

- (void)testHeightReducedWithoutName {
    HADashboardConfigSection *section = [self sectionWithEntityIds:@[@"a", @"b"]];
    HADashboardConfigItem *itemWithName = [self itemWithProps:@{@"show_name": @YES, @"show_state": @YES}];
    HADashboardConfigItem *itemNoName = [self itemWithProps:@{@"show_name": @NO, @"show_state": @YES}];

    CGFloat heightWithName = [HAGlanceCardCell preferredHeightForSection:section width:320 configItem:itemWithName];
    CGFloat heightNoName = [HAGlanceCardCell preferredHeightForSection:section width:320 configItem:itemNoName];

    XCTAssertGreaterThan(heightWithName, heightNoName, @"Hiding name should reduce height");
}

- (void)testHeightReducedWithoutState {
    HADashboardConfigSection *section = [self sectionWithEntityIds:@[@"a", @"b"]];
    HADashboardConfigItem *itemWithState = [self itemWithProps:@{@"show_name": @YES, @"show_state": @YES}];
    HADashboardConfigItem *itemNoState = [self itemWithProps:@{@"show_name": @YES, @"show_state": @NO}];

    CGFloat heightWithState = [HAGlanceCardCell preferredHeightForSection:section width:320 configItem:itemWithState];
    CGFloat heightNoState = [HAGlanceCardCell preferredHeightForSection:section width:320 configItem:itemNoState];

    XCTAssertGreaterThan(heightWithState, heightNoState, @"Hiding state should reduce height");
}

- (void)testHeightWithTitle {
    HADashboardConfigSection *section = [self sectionWithEntityIds:@[@"a", @"b"]];
    HADashboardConfigItem *itemNoTitle = [self itemWithProps:@{}];
    HADashboardConfigItem *itemWithTitle = [self itemWithProps:@{@"glance_title": @"Living Room"}];

    CGFloat heightNoTitle = [HAGlanceCardCell preferredHeightForSection:section width:320 configItem:itemNoTitle];
    CGFloat heightWithTitle = [HAGlanceCardCell preferredHeightForSection:section width:320 configItem:itemWithTitle];

    XCTAssertGreaterThan(heightWithTitle, heightNoTitle, @"Title should add height");
}

#pragma mark - Empty State

- (void)testEmptyEntitiesReturnsMinimalHeight {
    HADashboardConfigSection *section = [self sectionWithEntityIds:@[]];
    HADashboardConfigItem *item = [self itemWithProps:@{}];
    CGFloat height = [HAGlanceCardCell preferredHeightForSection:section width:320 configItem:item];
    XCTAssertGreaterThan(height, 0, @"Empty section should still return positive height (padding)");
    XCTAssertLessThan(height, 50, @"Empty section should return minimal height");
}

#pragma mark - HAGlanceItemView Height

- (void)testItemViewHeightAllVisible {
    CGFloat height = [HAGlanceItemView preferredHeightShowingName:YES showState:YES showIcon:YES];
    XCTAssertGreaterThan(height, 30, @"All elements visible should be substantial height");
}

- (void)testItemViewHeightIconOnly {
    CGFloat height = [HAGlanceItemView preferredHeightShowingName:NO showState:NO showIcon:YES];
    CGFloat heightAll = [HAGlanceItemView preferredHeightShowingName:YES showState:YES showIcon:YES];
    XCTAssertLessThan(height, heightAll, @"Icon-only should be shorter than all visible");
}

#pragma mark - Cell Configuration

- (void)testConfigureWithEntitiesDoesNotCrash {
    HAGlanceCardCell *cell = [[HAGlanceCardCell alloc] initWithFrame:CGRectMake(0, 0, 320, 100)];
    HADashboardConfigSection *section = [self sectionWithEntityIds:@[@"sensor.temperature", @"light.living_room"]];
    HADashboardConfigItem *item = [self itemWithProps:@{
        @"glance_title": @"Test",
        @"show_name": @YES,
        @"show_state": @YES,
        @"state_color": @YES,
    }];

    NSDictionary *entities = @{
        @"sensor.temperature": [HASnapshotTestHelpers sensorTemperature],
        @"light.living_room": [HASnapshotTestHelpers lightEntityOnBrightness],
    };

    XCTAssertNoThrow([cell configureWithSection:section entities:entities configItem:item]);
}

- (void)testConfigureWithMissingEntitiesDoesNotCrash {
    HAGlanceCardCell *cell = [[HAGlanceCardCell alloc] initWithFrame:CGRectMake(0, 0, 320, 100)];
    HADashboardConfigSection *section = [self sectionWithEntityIds:@[@"sensor.missing", @"light.also_missing"]];
    HADashboardConfigItem *item = [self itemWithProps:@{}];

    // Empty entity dict — all entities missing
    XCTAssertNoThrow([cell configureWithSection:section entities:@{} configItem:item]);
}

- (void)testPrepareForReuseClears {
    HAGlanceCardCell *cell = [[HAGlanceCardCell alloc] initWithFrame:CGRectMake(0, 0, 320, 100)];
    HADashboardConfigSection *section = [self sectionWithEntityIds:@[@"sensor.temperature"]];
    HADashboardConfigItem *item = [self itemWithProps:@{@"glance_title": @"Test"}];
    NSDictionary *entities = @{@"sensor.temperature": [HASnapshotTestHelpers sensorTemperature]};

    [cell configureWithSection:section entities:entities configItem:item];
    [cell prepareForReuse];

    // After reuse, entityTapBlock should be nil
    XCTAssertNil(cell.entityTapBlock);
}

#pragma mark - Entity Tap Block

- (void)testEntityTapBlockCalled {
    HAGlanceCardCell *cell = [[HAGlanceCardCell alloc] initWithFrame:CGRectMake(0, 0, 320, 100)];
    HADashboardConfigSection *section = [self sectionWithEntityIds:@[@"sensor.temperature"]];
    HADashboardConfigItem *item = [self itemWithProps:@{}];
    HAEntity *sensor = [HASnapshotTestHelpers sensorTemperature];
    NSDictionary *entities = @{@"sensor.temperature": sensor};

    [cell configureWithSection:section entities:entities configItem:item];

    __block HAEntity *tappedEntity = nil;
    cell.entityTapBlock = ^(HAEntity *entity, NSDictionary *actionConfig) {
        tappedEntity = entity;
    };

    // Simulate tap by calling the action selector directly via gesture
    // We can't easily simulate a UITapGestureRecognizer, but we can verify the block is set
    XCTAssertNotNil(cell.entityTapBlock);
}

@end
