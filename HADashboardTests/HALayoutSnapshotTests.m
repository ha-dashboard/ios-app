#import <XCTest/XCTest.h>
#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HALovelaceParser.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"
#import "HAThermostatGaugeCell.h"
#import "HAVacuumEntityCell.h"
#import "HAEntitiesCardCell.h"
#import "HALightEntityCell.h"
#import "HASwitchEntityCell.h"
#import "HASensorEntityCell.h"
#import "HABaseEntityCell.h"
#import "HAHeadingCell.h"
#import "HAColumnarLayout.h"

/// Feeds a parsed sections config to HAColumnarLayout with fixed per-card
/// heights, so a snapshot shows exactly where the layout puts each card.
@interface HAWireframeLayoutSource : NSObject <UICollectionViewDataSource, HAColumnarLayoutDelegate>
@property (nonatomic, strong) HADashboardConfig *config;
@end

@implementation HAWireframeLayoutSource

- (HADashboardConfigItem *)itemAt:(NSIndexPath *)indexPath {
    return self.config.sections[indexPath.section].items[indexPath.item];
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return (NSInteger)self.config.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.config.sections[section].items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [collectionView dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:indexPath];
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout
 heightForItemAtIndexPath:(NSIndexPath *)indexPath itemWidth:(CGFloat)itemWidth {
    HADashboardConfigItem *item = [self itemAt:indexPath];
    if (item.rowSpan > 0) return item.rowSpan * 56.0 + (item.rowSpan - 1) * 6.0;
    if ([item.cardType isEqualToString:@"weather-forecast"]) return 110.0;
    return 56.0;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout
 heightForHeaderInSection:(NSInteger)section {
    return 0;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout
  gridColumnsForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [self itemAt:indexPath].columnSpan;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout
       columnSpanForSection:(NSInteger)section {
    return MAX(self.config.sections[section].columnSpan, 1);
}

@end

/// Integration tests that render full dashboard sections from Lovelace JSON configs
/// and side-by-side cell compositions at various column ratios.
@interface HALayoutSnapshotTests : HABaseSnapshotTestCase
@end

@implementation HALayoutSnapshotTests

#pragma mark - Helpers

/// Load a JSON dictionary from a path relative to the project root.
/// Uses __FILE__ to locate the project directory at compile time.
- (NSDictionary *)loadJSONFromProjectPath:(NSString *)relativePath {
    NSString *thisFile = @__FILE__;
    NSString *testDir = [thisFile stringByDeletingLastPathComponent];
    NSString *projectRoot = [testDir stringByDeletingLastPathComponent];
    NSString *fullPath = [projectRoot stringByAppendingPathComponent:relativePath];
    NSData *data = [NSData dataWithContentsOfFile:fullPath];
    if (!data) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

#pragma mark - Test 1: Side-by-Side 9+3 Thermostat + Vacuum

/// Two cells side-by-side: thermostat(9-col) + vacuum(3-col) = 12.
/// Regression test: verifies the living-room pattern renders correctly
/// with headings above each cell in both Gradient and Light themes.
- (void)testSideBySide_9plus3_Thermostat_Vacuum {
    CGFloat totalWidth = kColumnWidth;
    CGFloat thermoWidth = floor(totalWidth * 9.0 / 12.0);
    CGFloat vacuumWidth = totalWidth - thermoWidth;
    CGFloat rowHeight = kThermostatHeight + kHeadingExtra;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, totalWidth, rowHeight)];
    container.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];

    // Thermostat at (0, 0) -- 9/12 width
    HAThermostatGaugeCell *thermoCell = [[HAThermostatGaugeCell alloc]
        initWithFrame:CGRectMake(0, 0, thermoWidth, rowHeight)];
    HAEntity *thermoEntity = [[HASnapshotTestHelpers livingRoomEntities] objectForKey:@"climate.aidoo"];
    HADashboardConfigItem *thermoItem = [HASnapshotTestHelpers itemWithEntityId:@"climate.aidoo"
        cardType:@"thermostat" columnSpan:9 headingIcon:@"mdi:hvac" displayName:@"House Climate"];
    [thermoCell configureWithEntity:thermoEntity configItem:thermoItem];
    [thermoCell layoutIfNeeded];
    [container addSubview:thermoCell];

    // Vacuum at (thermoWidth, 0) -- 3/12 width
    HAVacuumEntityCell *vacuumCell = [[HAVacuumEntityCell alloc]
        initWithFrame:CGRectMake(thermoWidth, 0, vacuumWidth, rowHeight)];
    HAEntity *vacuumEntity = [[HASnapshotTestHelpers livingRoomEntities] objectForKey:@"vacuum.saros_10"];
    HADashboardConfigItem *vacuumItem = [HASnapshotTestHelpers itemWithEntityId:@"vacuum.saros_10"
        cardType:@"vacuum" columnSpan:3 headingIcon:@"mdi:robot-vacuum" displayName:@"Ribbit"];
    [vacuumCell configureWithEntity:vacuumEntity configItem:vacuumItem];
    [vacuumCell layoutIfNeeded];
    [container addSubview:vacuumCell];

    [self verifyView:container identifier:@"9plus3_thermostat_vacuum"];
}

#pragma mark - Test 2: Side-by-Side 6+6 Two Lights

/// Two light cells side-by-side at 6-col each: one on, one off.
/// Verifies equal-width layout with contrasting entity states.
- (void)testSideBySide_6plus6_TwoLights {
    CGFloat totalWidth = kColumnWidth;
    CGFloat halfWidth = floor(totalWidth * 6.0 / 12.0);
    CGFloat rowHeight = kStandardCellHeight;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, totalWidth, rowHeight)];
    container.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];

    // Light ON at (0, 0)
    HAEntity *lightOn = [HASnapshotTestHelpers lightEntityOnBrightness];
    HADashboardConfigItem *lightOnItem = [HASnapshotTestHelpers itemWithEntityId:lightOn.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *lightOnCell = [self cellForEntity:lightOn cellClass:[HALightEntityCell class]
        size:CGSizeMake(halfWidth, rowHeight) configItem:lightOnItem];
    lightOnCell.frame = CGRectMake(0, 0, halfWidth, rowHeight);
    [container addSubview:lightOnCell];

    // Light OFF at (halfWidth, 0)
    HAEntity *lightOff = [HASnapshotTestHelpers lightEntityOff];
    HADashboardConfigItem *lightOffItem = [HASnapshotTestHelpers itemWithEntityId:lightOff.entityId
        cardType:@"light" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *lightOffCell = [self cellForEntity:lightOff cellClass:[HALightEntityCell class]
        size:CGSizeMake(halfWidth, rowHeight) configItem:lightOffItem];
    lightOffCell.frame = CGRectMake(halfWidth, 0, halfWidth, rowHeight);
    [container addSubview:lightOffCell];

    [self verifyView:container identifier:@"6plus6_two_lights"];
}

#pragma mark - Test 3: Full-Width Sensor 12-col

/// Single HASensorEntityCell at full 12-col width.
/// Verifies sensors render correctly at the widest possible cell size.
- (void)testFullWidthSensor_12col {
    CGFloat totalWidth = kColumnWidth;
    CGFloat rowHeight = kStandardCellHeight;

    HAEntity *sensor = [HASnapshotTestHelpers sensorTemperature];
    HADashboardConfigItem *sensorItem = [HASnapshotTestHelpers itemWithEntityId:sensor.entityId
        cardType:@"sensor" columnSpan:12 headingIcon:nil displayName:nil];

    UIView *cell = [self cellForEntity:sensor cellClass:[HASensorEntityCell class]
        size:CGSizeMake(totalWidth, rowHeight) configItem:sensorItem];

    [self verifyView:cell identifier:@"12col_sensor"];
}

#pragma mark - Test 4: Three Columns 4+4+4

/// Three cells at 4-col each: sensor, switch, light.
/// Verifies narrow 3-across layout renders without overlap or truncation.
- (void)testThreeColumn_4_4_4 {
    CGFloat totalWidth = kColumnWidth;
    CGFloat thirdWidth = floor(totalWidth * 4.0 / 12.0);
    CGFloat rowHeight = kStandardCellHeight;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, totalWidth, rowHeight)];
    container.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];

    // Sensor at (0, 0)
    HAEntity *sensor = [HASnapshotTestHelpers sensorTemperature];
    HADashboardConfigItem *sensorItem = [HASnapshotTestHelpers itemWithEntityId:sensor.entityId
        cardType:@"sensor" columnSpan:4 headingIcon:nil displayName:nil];
    UIView *sensorCell = [self cellForEntity:sensor cellClass:[HASensorEntityCell class]
        size:CGSizeMake(thirdWidth, rowHeight) configItem:sensorItem];
    sensorCell.frame = CGRectMake(0, 0, thirdWidth, rowHeight);
    [container addSubview:sensorCell];

    // Switch at (thirdWidth, 0)
    HAEntity *sw = [HASnapshotTestHelpers switchEntityOn];
    HADashboardConfigItem *swItem = [HASnapshotTestHelpers itemWithEntityId:sw.entityId
        cardType:@"switch" columnSpan:4 headingIcon:nil displayName:nil];
    UIView *swCell = [self cellForEntity:sw cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(thirdWidth, rowHeight) configItem:swItem];
    swCell.frame = CGRectMake(thirdWidth, 0, thirdWidth, rowHeight);
    [container addSubview:swCell];

    // Light at (2 * thirdWidth, 0)
    HAEntity *light = [HASnapshotTestHelpers lightEntityOnBrightness];
    HADashboardConfigItem *lightItem = [HASnapshotTestHelpers itemWithEntityId:light.entityId
        cardType:@"light" columnSpan:4 headingIcon:nil displayName:nil];
    UIView *lightCell = [self cellForEntity:light cellClass:[HALightEntityCell class]
        size:CGSizeMake(thirdWidth, rowHeight) configItem:lightItem];
    lightCell.frame = CGRectMake(2 * thirdWidth, 0, thirdWidth, rowHeight);
    [container addSubview:lightCell];

    [self verifyView:container identifier:@"4_4_4_three_column"];
}

#pragma mark - Test 5: Mixed Widths 8+4

/// Entities card at 8-col + sensor at 4-col.
/// Verifies mixed composite and standard cells share a row correctly.
- (void)testMixedWidths_8plus4 {
    CGFloat totalWidth = kColumnWidth;
    CGFloat entWidth = floor(totalWidth * 8.0 / 12.0);
    CGFloat sensorWidth = totalWidth - entWidth;
    NSInteger entityCount = 3;
    CGFloat rowHeight = MAX(entityCount * kEntitiesRowHeight + kHeadingExtra, kStandardCellHeight);

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, totalWidth, rowHeight)];
    container.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];

    // Entities card at (0, 0) -- 8/12 width
    HADashboardConfigSection *section = [HASnapshotTestHelpers entitiesSectionWithLights];
    HADashboardConfigItem *entItem = [HASnapshotTestHelpers itemWithEntityId:@"light.office_3"
        cardType:@"entities" columnSpan:8 headingIcon:@"mdi:ceiling-light-multiple" displayName:@"Lights"];
    entItem.entitiesSection = section;
    NSDictionary *entities = [HASnapshotTestHelpers livingRoomEntities];
    UIView *entCell = [self compositeCell:[HAEntitiesCardCell class]
        size:CGSizeMake(entWidth, rowHeight)
        section:section entities:entities configItem:entItem];
    entCell.frame = CGRectMake(0, 0, entWidth, rowHeight);
    [container addSubview:entCell];

    // Sensor at (entWidth, 0) -- 4/12 width
    HAEntity *sensor = [HASnapshotTestHelpers sensorTemperature];
    HADashboardConfigItem *sensorItem = [HASnapshotTestHelpers itemWithEntityId:sensor.entityId
        cardType:@"sensor" columnSpan:4 headingIcon:nil displayName:nil];
    UIView *sensorCell = [self cellForEntity:sensor cellClass:[HASensorEntityCell class]
        size:CGSizeMake(sensorWidth, rowHeight) configItem:sensorItem];
    sensorCell.frame = CGRectMake(entWidth, 0, sensorWidth, rowHeight);
    [container addSubview:sensorCell];

    [self verifyView:container identifier:@"8plus4_entities_sensor"];
}

#pragma mark - Test 6: Parsed Living Room Config

/// Parses the living-room Lovelace JSON through HALovelaceParser and verifies the
/// resulting HADashboardConfig has expected structure. This is a parse-only validation
/// (no snapshot) -- it ensures the parser produces items from a real HA config file.
- (void)testParsedLivingRoomConfig {
    NSDictionary *json = [self loadJSONFromProjectPath:@"docs/audit/ha-config-living-room.json"];
    if (!json) {
        // Skip if file not available in test environment
        return;
    }

    // Parse the full dashboard
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:json];
    XCTAssertNotNil(dashboard, @"Dashboard should parse successfully");
    XCTAssertGreaterThan(dashboard.views.count, 0, @"Dashboard should have at least one view");

    // Convert the first view to our native config
    HALovelaceView *view = [dashboard viewAtIndex:0];
    XCTAssertNotNil(view, @"First view should exist");
    XCTAssertEqualObjects(view.title, @"Living Room", @"First view should be Living Room");
    XCTAssertEqual(view.maxColumns, 3, @"Living Room view should have maxColumns=3");

    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:view columns:3];
    XCTAssertNotNil(config, @"Config should be created from view");
    XCTAssertGreaterThan(config.items.count, 0, @"Parsed config should have items");
    XCTAssertGreaterThan(config.sections.count, 0, @"Parsed config should have sections");

    // Verify all entity IDs can be extracted
    NSArray<NSString *> *allEntityIds = [config allEntityIds];
    XCTAssertGreaterThan(allEntityIds.count, 0, @"Config should reference at least one entity");

    // Verify the thermostat entity is present (it's the primary card)
    BOOL hasThermostat = NO;
    for (NSString *eid in allEntityIds) {
        if ([eid containsString:@"climate."]) {
            hasThermostat = YES;
            break;
        }
    }
    XCTAssertTrue(hasThermostat, @"Living room config should include a climate entity");
}

#pragma mark - Test 8: Sections column_span wireframe (GitHub #25)

/// The GitHub #25 reporter's view (max_columns 4; sections spanning 1, 2 and
/// 1 columns) laid out by HAColumnarLayout at iPad landscape width with the
/// dashboard's real insets and spacing. Each card is drawn as a labelled box
/// (type and sub-grid span) inside its section's outline, so the reference
/// shows the 1/4 + 1/2 + 1/4 section split and the card widths within them.
- (void)testSectionsColumnSpan_reporterViewWireframe_1024 {
    NSDictionary *dict = @{@"views": @[@{@"title": @"Home", @"type": @"sections", @"max_columns": @4, @"sections": @[
        @{@"type": @"grid", @"column_span": @1, @"cards": @[
            @{@"type": @"tile", @"entity": @"person.psolyca", @"grid_options": @{@"columns": @4, @"rows": @1}},
            @{@"type": @"tile", @"entity": @"sensor.sun_next_rising", @"name": @" "}]},
        @{@"type": @"grid", @"column_span": @2, @"cards": @[
            @{@"type": @"vertical-stack", @"grid_options": @{@"columns": @33, @"rows": @"auto"}, @"cards": @[
                @{@"type": @"clock", @"clock_size": @"large", @"grid_options": @{@"columns": @9, @"rows": @2}},
                @{@"type": @"weather-forecast", @"entity": @"weather.forecast_maison", @"show_forecast": @NO},
                @{@"type": @"weather-forecast", @"entity": @"weather.cleguer", @"show_current": @NO}]}]},
        @{@"type": @"grid", @"column_span": @1, @"cards": @[
            @{@"type": @"tile", @"entity": @"sensor.sun_next_setting", @"name": @" "},
            @{@"type": @"tile", @"entity": @"person.solene"}]}]}]};
    HALovelaceView *view = [HALovelaceParser parseDashboardFromDictionary:dict].views.firstObject;
    HAWireframeLayoutSource *source = [[HAWireframeLayoutSource alloc] init];
    source.config = [HALovelaceParser dashboardConfigFromView:view columns:3];

    // Same geometry as HADashboardViewController -applyLayoutForSectionsView:
    HAColumnarLayout *layout = [[HAColumnarLayout alloc] init];
    layout.contentInsets = UIEdgeInsetsMake(4, 8, 8, 8);
    layout.interColumnSpacing = 6;
    layout.interItemSpacing = 6;
    layout.maxColumns = view.maxColumns;
    layout.delegate = source;
    UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, 1024, 400) collectionViewLayout:layout];
    cv.dataSource = source;
    [cv registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"cell"];
    [cv layoutIfNeeded];

    CGSize content = layout.collectionViewContentSize;
    UIView *canvas = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1024, content.height)];
    canvas.backgroundColor = [UIColor colorWithWhite:0.93 alpha:1.0];
    for (NSInteger section = 0; section < (NSInteger)source.config.sections.count; section++) {
        CGRect outline = CGRectNull;
        NSInteger count = (NSInteger)source.config.sections[section].items.count;
        for (NSInteger i = 0; i < count; i++) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:i inSection:section];
            outline = CGRectUnion(outline, [layout layoutAttributesForItemAtIndexPath:indexPath].frame);
        }
        UIView *sectionView = [[UIView alloc] initWithFrame:CGRectInset(outline, -2, -2)];
        sectionView.layer.borderColor = [UIColor colorWithRed:0.20 green:0.45 blue:0.85 alpha:1.0].CGColor;
        sectionView.layer.borderWidth = 2;
        [canvas addSubview:sectionView];
        for (NSInteger i = 0; i < count; i++) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:i inSection:section];
            HADashboardConfigItem *item = [source itemAt:indexPath];
            UILabel *box = [[UILabel alloc] initWithFrame:[layout layoutAttributesForItemAtIndexPath:indexPath].frame];
            box.backgroundColor = [UIColor whiteColor];
            box.textColor = [UIColor blackColor];
            box.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
            box.textAlignment = NSTextAlignmentCenter;
            box.text = [NSString stringWithFormat:@"%@ · %ld/%ld", item.cardType, (long)item.columnSpan,
                        (long)(12 * MAX(source.config.sections[section].columnSpan, 1))];
            [canvas addSubview:box];
        }
    }

    [self verifyView:canvas identifier:@"sections_column_span_reporter_1024"];
}

#pragma mark - Test 7: Minimal Section -- 2 Entities

/// Two standard cells side-by-side at 6-col each: sensor + switch.
/// Verifies the simplest possible two-entity section layout.
- (void)testMinimalSection_2Entities {
    CGFloat totalWidth = kColumnWidth;
    CGFloat halfWidth = floor(totalWidth * 6.0 / 12.0);
    CGFloat rowHeight = kStandardCellHeight;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, totalWidth, rowHeight)];
    container.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];

    // Sensor at (0, 0)
    HAEntity *sensor = [HASnapshotTestHelpers sensorTemperature];
    HADashboardConfigItem *sensorItem = [HASnapshotTestHelpers itemWithEntityId:sensor.entityId
        cardType:@"sensor" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *sensorCell = [self cellForEntity:sensor cellClass:[HASensorEntityCell class]
        size:CGSizeMake(halfWidth, rowHeight) configItem:sensorItem];
    sensorCell.frame = CGRectMake(0, 0, halfWidth, rowHeight);
    [container addSubview:sensorCell];

    // Switch at (halfWidth, 0)
    HAEntity *sw = [HASnapshotTestHelpers switchEntityOn];
    HADashboardConfigItem *swItem = [HASnapshotTestHelpers itemWithEntityId:sw.entityId
        cardType:@"switch" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *swCell = [self cellForEntity:sw cellClass:[HASwitchEntityCell class]
        size:CGSizeMake(halfWidth, rowHeight) configItem:swItem];
    swCell.frame = CGRectMake(halfWidth, 0, halfWidth, rowHeight);
    [container addSubview:swCell];

    [self verifyView:container identifier:@"minimal_2entities"];
}

@end
