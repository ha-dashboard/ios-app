#import "HABaseSnapshotTestCase.h"
#import "HASnapshotTestHelpers.h"
#import "HAEntitiesCardCell.h"
#import "HABadgeRowCell.h"
#import "HAGaugeCardCell.h"
#import "HAGraphCardCell.h"
#import "HATileEntityCell.h"
#import "HAHeadingCell.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"
#import "HALovelaceParser.h"
#import "HAColumnarLayout.h"
#import "HASectionHeaderView.h"

/// Minimal columnar-layout delegate over a parsed HADashboardConfig, so a
/// snapshot can place real cells at the frames HAColumnarLayout computes
/// (heights as HADashboardViewController: heading 36, tile per config,
/// section header 36 when titled).
@interface HACompositeColumnarSource : NSObject <UICollectionViewDataSource, HAColumnarLayoutDelegate>
@property (nonatomic, strong) HADashboardConfig *config;
@end

@implementation HACompositeColumnarSource
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return (NSInteger)self.config.sections.count;
}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.config.sections[section].items.count;
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [collectionView dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:indexPath];
}
- (HADashboardConfigItem *)itemAt:(NSIndexPath *)indexPath {
    return self.config.sections[indexPath.section].items[indexPath.item];
}
- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout
 heightForItemAtIndexPath:(NSIndexPath *)indexPath itemWidth:(CGFloat)itemWidth {
    HADashboardConfigItem *item = [self itemAt:indexPath];
    if ([item.cardType isEqualToString:@"heading"]) return 36.0;
    return [HATileEntityCell preferredHeightForConfigItem:item];
}
- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout
 heightForHeaderInSection:(NSInteger)section {
    return self.config.sections[section].title.length > 0 ? 36.0 : 0.0;
}
- (NSInteger)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout
  gridColumnsForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [self itemAt:indexPath].columnSpan;
}
- (BOOL)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout
  isHeadingItemAtIndexPath:(NSIndexPath *)indexPath {
    return [[self itemAt:indexPath].cardType isEqualToString:@"heading"];
}
@end

@interface HACompositeSnapshotTests : HABaseSnapshotTestCase
@end

@implementation HACompositeSnapshotTests

#pragma mark - HAEntitiesCardCell (2 tests)

- (void)testEntitiesCard3Rows {
    HADashboardConfigSection *section = [HASnapshotTestHelpers entitiesSectionWithLights];
    NSDictionary *entities = [HASnapshotTestHelpers livingRoomEntities];
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"light.office_3"
        cardType:@"entities" columnSpan:12 headingIcon:nil displayName:nil];
    item.entitiesSection = section;
    CGFloat height = [HAEntitiesCardCell preferredHeightForEntityCount:3 hasTitle:NO hasHeaderToggle:NO];
    UIView *cell = [self compositeCell:[HAEntitiesCardCell class]
        size:CGSizeMake(kColumnWidth, height) section:section entities:entities configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testEntitiesCard5Rows {
    HADashboardConfigSection *section = [HASnapshotTestHelpers entitiesSectionFiveRows];
    NSDictionary *entities = @{
        @"light.kitchen": [HASnapshotTestHelpers lightEntityOnBrightness],
        @"switch.in_meeting": [HASnapshotTestHelpers switchEntityOn],
        @"sensor.living_room_temperature": [HASnapshotTestHelpers sensorTemperature],
        @"cover.living_room_shutter": [HASnapshotTestHelpers coverEntityOpenShutter],
        @"lock.frontdoor": [HASnapshotTestHelpers lockLocked]
    };
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:@"light.kitchen"
        cardType:@"entities" columnSpan:12 headingIcon:nil displayName:nil];
    item.entitiesSection = section;
    CGFloat height = [HAEntitiesCardCell preferredHeightForEntityCount:5 hasTitle:YES hasHeaderToggle:NO];
    UIView *cell = [self compositeCell:[HAEntitiesCardCell class]
        size:CGSizeMake(kColumnWidth, height) section:section entities:entities configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HABadgeRowCell (2 tests)

- (void)testBadgeRow2Items {
    HADashboardConfigSection *section = [HASnapshotTestHelpers badgeSection2Items];
    NSDictionary *entities = @{
        @"sensor.living_room_temperature": [HASnapshotTestHelpers sensorTemperature],
        @"sensor.living_room_humidity": [HASnapshotTestHelpers sensorHumidity]
    };
    UIView *cell = [self compositeCell:[HABadgeRowCell class]
        size:CGSizeMake(kColumnWidth, kBadgeRowHeight) section:section entities:entities configItem:nil];
    [self verifyView:cell identifier:nil];
}

- (void)testBadgeRow4Items {
    HADashboardConfigSection *section = [HASnapshotTestHelpers badgeSection4Items];
    NSDictionary *entities = @{
        @"sensor.living_room_temperature": [HASnapshotTestHelpers sensorTemperature],
        @"sensor.living_room_humidity": [HASnapshotTestHelpers sensorHumidity],
        @"binary_sensor.hallway_motion": [HASnapshotTestHelpers binarySensorMotionOn],
        @"binary_sensor.front_door": [HASnapshotTestHelpers binarySensorDoorOff]
    };
    UIView *cell = [self compositeCell:[HABadgeRowCell class]
        size:CGSizeMake(kColumnWidth, kBadgeRowHeight) section:section entities:entities configItem:nil];
    [self verifyView:cell identifier:nil];
}

#pragma mark - View badges (GitHub #23)

/// Entities shared by the view-badge snapshots.
- (NSDictionary<NSString *, HAEntity *> *)viewBadgeEntities {
    return @{
        @"sun.sun": [HASnapshotTestHelpers entityWithId:@"sun.sun" state:@"below_horizon"
                                              attributes:@{@"friendly_name": @"Sun"}],
        @"sensor.living_room_temperature": [HASnapshotTestHelpers sensorTemperature],
        @"sensor.living_room_humidity": [HASnapshotTestHelpers sensorHumidity],
        @"binary_sensor.hallway_motion": [HASnapshotTestHelpers binarySensorMotionOn],
        @"binary_sensor.front_door": [HASnapshotTestHelpers binarySensorDoorOff],
        @"light.office_3": [HASnapshotTestHelpers lightEntityOnBrightness],
        @"lock.frontdoor": [HASnapshotTestHelpers lockLocked],
        @"person.ash": [HASnapshotTestHelpers personHome],
    };
}

/// The view's badge section exactly as the parser builds it for `badges`.
- (HADashboardConfigSection *)viewBadgeSectionForBadges:(NSArray *)badges {
    NSDictionary *dict = @{@"views": @[@{@"title": @"Home", @"badges": badges,
                                         @"sections": @[@{@"type": @"grid", @"cards": @[]}]}]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    return [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3].viewBadges;
}

- (UIView *)viewBadgeRowForBadges:(NSArray *)badges width:(CGFloat)width {
    HADashboardConfigSection *section = [self viewBadgeSectionForBadges:badges];
    XCTAssertNotNil(section);
    NSDictionary *entities = [self viewBadgeEntities];
    CGFloat height = [HABadgeRowCell preferredHeightForSection:section entities:entities width:width];
    return [self compositeCell:[HABadgeRowCell class] size:CGSizeMake(width, height)
                       section:section entities:entities configItem:nil];
}

/// The reporter's row: a single legacy sun.sun badge (name above state), centred in the row.
- (void)testViewBadgeRowSingleSun {
    UIView *row = [self viewBadgeRowForBadges:@[@"sun.sun"] width:kColumnWidth];
    [self verifyView:row identifier:nil];
}

/// Mixed HA 2024.8+ badge configs wrapping onto several centred rows in a narrow width:
/// default (icon + state), show_name, custom name/icon/colour, name-only, icon-only.
- (void)testViewBadgeRowWrapsSeveralBadges {
    NSArray *badges = @[
        @{@"type": @"entity", @"entity": @"sensor.living_room_temperature"},
        @{@"type": @"entity", @"entity": @"sensor.living_room_humidity", @"show_name": @YES},
        @"sun.sun",
        @{@"entity": @"binary_sensor.hallway_motion", @"name": @"Hall", @"show_name": @YES},
        @{@"type": @"entity", @"entity": @"light.office_3", @"icon": @"mdi:desk-lamp", @"color": @"amber"},
        @{@"type": @"entity", @"entity": @"lock.frontdoor", @"show_state": @NO, @"show_name": @YES},
        @{@"type": @"entity", @"entity": @"binary_sensor.front_door", @"show_state": @NO},
        @{@"type": @"state-label", @"entity": @"person.ash"},
    ];
    UIView *row = [self viewBadgeRowForBadges:badges width:kColumnWidth];
    XCTAssertGreaterThan(row.bounds.size.height, 36.0 + 8.0, @"8 badges must wrap onto more than one row at 320pt");
    [self verifyView:row identifier:nil];
}

#pragma mark - Sections view: two headings (GitHub #23)

/// The reporter's section: Heading 1 / tile / Heading 2 / tile, parsed and laid
/// out by HAColumnarLayout. Heading 1 becomes the section header; Heading 2 is
/// a full-width heading row between the tiles; each tile keeps HA's default
/// 6/12 span and sits alone on its row.
- (void)testSectionWithTwoHeadings {
    HADashboardConfig *config = [self sectionsConfigWithCards:@[
        @{@"type": @"heading", @"heading": @"Heading 1", @"icon": @"mdi:backup-restore"},
        @{@"type": @"tile", @"entity": @"sensor.backup_backup_manager_state"},
        @{@"type": @"heading", @"heading": @"Heading 2", @"icon": @"mdi:clock-outline"},
        @{@"type": @"tile", @"entity": @"sensor.living_room_temperature"},
    ]];
    NSDictionary *entities = @{
        @"sensor.backup_backup_manager_state": [HASnapshotTestHelpers entityWithId:@"sensor.backup_backup_manager_state"
            state:@"idle" attributes:@{@"friendly_name": @"Backup Backup Manager state", @"icon": @"mdi:backup-restore"}],
        @"sensor.living_room_temperature": [HASnapshotTestHelpers sensorTemperature],
    };
    [self verifySectionsColumn:config entities:entities];
}

/// A single-section sections view ("Backup") with the given cards, parsed.
- (HADashboardConfig *)sectionsConfigWithCards:(NSArray *)cards {
    NSDictionary *dict = @{@"views": @[@{@"title": @"Backup", @"sections": @[@{@"type": @"grid", @"cards": cards}]}]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    return [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3];
}

/// Snapshot the first section of `config` as HAColumnarLayout places it: the
/// section header (with its heading badges), heading rows (with theirs) and
/// tiles at their computed frames.
- (void)verifySectionsColumn:(HADashboardConfig *)config entities:(NSDictionary<NSString *, HAEntity *> *)entities {
    HACompositeColumnarSource *source = [[HACompositeColumnarSource alloc] init];
    source.config = config;
    HAColumnarLayout *layout = [[HAColumnarLayout alloc] init];
    layout.delegate = source;
    layout.contentInsets = UIEdgeInsetsMake(4, 8, 8, 8);
    CGFloat width = kColumnWidth + 16.0;
    UICollectionView *cv = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, width, 600) collectionViewLayout:layout];
    cv.dataSource = source;
    [cv registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"cell"];
    [cv layoutIfNeeded];

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, layout.collectionViewContentSize.height)];
    container.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];

    UICollectionViewLayoutAttributes *headerAttr =
        [layout layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                                               atIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
    XCTAssertNotNil(headerAttr, @"Heading 1 must render as the section header");
    HASectionHeaderView *header = [[HASectionHeaderView alloc] initWithFrame:headerAttr.frame];
    HADashboardConfigSection *section = config.sections.firstObject;
    [header configureWithSection:section badgeConfigs:section.customProperties[HAHeadingBadgesKey] entities:entities];
    [container addSubview:header];

    NSArray<HADashboardConfigItem *> *items = config.sections.firstObject.items;
    for (NSUInteger i = 0; i < items.count; i++) {
        HADashboardConfigItem *item = items[i];
        CGRect frame = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]].frame;
        UIView *cell;
        if ([item.cardType isEqualToString:@"heading"]) {
            HAHeadingCell *headingCell = [[HAHeadingCell alloc] initWithFrame:frame];
            [headingCell configureWithItem:item badgeConfigs:item.customProperties[HAHeadingBadgesKey] entities:entities];
            cell = headingCell;
        } else {
            cell = [self cellForEntity:entities[item.entityId] cellClass:[HATileEntityCell class]
                                  size:frame.size configItem:item];
            cell.frame = frame;
        }
        [container addSubview:cell];
    }
    [container layoutIfNeeded];
    [self verifyView:container identifier:nil];
}

#pragma mark - Heading badges

/// Entities shared by the heading-badge snapshots.
- (NSDictionary<NSString *, HAEntity *> *)headingBadgeEntities {
    return @{
        @"sensor.living_room_temperature": [HASnapshotTestHelpers sensorTemperature],
        @"sensor.living_room_humidity": [HASnapshotTestHelpers sensorHumidity],
        @"light.kitchen": [HASnapshotTestHelpers lightEntityOnBrightness],
        @"sensor.backup_backup_manager_state": [HASnapshotTestHelpers entityWithId:@"sensor.backup_backup_manager_state"
            state:@"idle" attributes:@{@"friendly_name": @"Backup Backup Manager state", @"icon": @"mdi:backup-restore"}],
    };
}

/// A standalone heading row with two badges at the end of the line: icon +
/// state in secondary text, no pill; the light's icon takes its state colour.
- (void)testHeadingWithTwoBadges {
    HADashboardConfig *config = [self sectionsConfigWithCards:@[
        @{@"type": @"tile", @"entity": @"sensor.living_room_temperature"},
        @{@"type": @"heading", @"heading": @"Living Room", @"icon": @"mdi:sofa", @"badges": @[
            @{@"type": @"entity", @"entity": @"sensor.living_room_temperature"},
            @{@"type": @"entity", @"entity": @"light.kitchen", @"color": @"state"},
        ]},
    ]];
    HADashboardConfigItem *item = config.sections.firstObject.items[1];
    XCTAssertEqualObjects(item.cardType, @"heading");
    HAHeadingCell *cell = [[HAHeadingCell alloc] initWithFrame:CGRectMake(0, 0, kColumnWidth, kHeadingCellHeight)];
    [cell configureWithItem:item badgeConfigs:item.customProperties[HAHeadingBadgesKey] entities:[self headingBadgeEntities]];
    [cell layoutIfNeeded];
    [self verifyView:cell identifier:nil];
}

/// A section whose opening heading (the section header) has two badges and a
/// later heading has one, laid out by HAColumnarLayout: the header's and the
/// standalone heading's icons, titles and badges line up.
- (void)testSectionHeadingsWithBadges {
    HADashboardConfig *config = [self sectionsConfigWithCards:@[
        @{@"type": @"heading", @"heading": @"Heading 1", @"icon": @"mdi:backup-restore", @"badges": @[
            @"sensor.living_room_temperature",
            @{@"entity": @"sensor.living_room_humidity", @"icon": @"mdi:water-percent"},
        ]},
        @{@"type": @"tile", @"entity": @"sensor.backup_backup_manager_state"},
        @{@"type": @"heading", @"heading": @"Heading 2", @"icon": @"mdi:clock-outline", @"badges": @[
            @{@"entity": @"light.kitchen", @"color": @"state", @"show_state": @NO},
        ]},
        @{@"type": @"tile", @"entity": @"sensor.living_room_temperature"},
    ]];
    [self verifySectionsColumn:config entities:[self headingBadgeEntities]];
}

#pragma mark - HAGaugeCardCell (4 tests)

- (void)testGauge50Percent {
    HAEntity *entity = [HASnapshotTestHelpers sensorTemperature];
    HADashboardConfigItem *item = [HASnapshotTestHelpers gaugeCardItem50Percent];
    UIView *cell = [self cellForEntity:entity cellClass:[HAGaugeCardCell class]
        size:CGSizeMake(kColumnWidth, kGaugeCardHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testGauge0Percent {
    HAEntity *entity = [HASnapshotTestHelpers sensorTemperature];
    HADashboardConfigItem *item = [HASnapshotTestHelpers gaugeCardItem0Percent];
    UIView *cell = [self cellForEntity:entity cellClass:[HAGaugeCardCell class]
        size:CGSizeMake(kColumnWidth, kGaugeCardHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testGauge100Percent {
    HAEntity *entity = [HASnapshotTestHelpers sensorTemperature];
    HADashboardConfigItem *item = [HASnapshotTestHelpers gaugeCardItem100Percent];
    UIView *cell = [self cellForEntity:entity cellClass:[HAGaugeCardCell class]
        size:CGSizeMake(kColumnWidth, kGaugeCardHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testGaugeSeverity {
    HAEntity *entity = [HASnapshotTestHelpers sensorTemperature];
    HADashboardConfigItem *item = [HASnapshotTestHelpers gaugeCardItemSeverity];
    UIView *cell = [self cellForEntity:entity cellClass:[HAGaugeCardCell class]
        size:CGSizeMake(kColumnWidth, kGaugeCardHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HAGraphCardCell (2 tests)

- (void)testGraphSingle {
    HAEntity *entity = [HASnapshotTestHelpers sensorTemperature];
    HADashboardConfigItem *item = [HASnapshotTestHelpers graphCardSingleEntity];
    HAGraphCardCell *graphCell = [[HAGraphCardCell alloc] initWithFrame:CGRectMake(0, 0, kColumnWidth, kGraphCardHeight)];
    [graphCell configureWithEntity:entity item:item];
    [graphCell layoutIfNeeded];
    [self verifyView:graphCell identifier:nil];
}

- (void)testGraphMulti {
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:@"Environment"
        icon:@"mdi:thermometer"
        entityIds:@[
            @"sensor.living_room_temperature",
            @"sensor.living_room_humidity",
            @"sensor.office_illuminance"
        ]];
    NSDictionary *entities = @{
        @"sensor.living_room_temperature": [HASnapshotTestHelpers sensorTemperature],
        @"sensor.living_room_humidity": [HASnapshotTestHelpers sensorHumidity],
        @"sensor.office_illuminance": [HASnapshotTestHelpers sensorIlluminance]
    };
    HAGraphCardCell *graphCell = [[HAGraphCardCell alloc] initWithFrame:CGRectMake(0, 0, kColumnWidth, kGraphCardHeight)];
    [graphCell configureWithSection:section entities:entities];
    [graphCell layoutIfNeeded];
    [self verifyView:graphCell identifier:nil];
}

#pragma mark - HAGaugeCardCell — Narrow (1 test)

- (void)testGaugeNarrowTextScaling {
    // Small gauge card (like vplants dashboard): text must scale to fit inside arc
    HAEntity *entity = [HASnapshotTestHelpers sensorHumidity]; // 57%
    HADashboardConfigItem *item = [HASnapshotTestHelpers gaugeCardItem50Percent];
    CGFloat narrowWidth = floor(kSubGridUnit * 4); // ~107pt — narrow column
    UIView *cell = [self cellForEntity:entity cellClass:[HAGaugeCardCell class]
        size:CGSizeMake(narrowWidth, kGaugeCardHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HAGraphCardCell — Multi-Axis (1 test)

- (void)testGraphMultiAxis {
    // 3 entities with different units: °C, %, lx — should produce 3 Y-axis groups
    HADashboardConfigSection *section = [HASnapshotTestHelpers sectionWithTitle:@"Environment"
        icon:@"mdi:thermometer"
        entityIds:@[
            @"sensor.living_room_temperature",
            @"sensor.living_room_humidity",
            @"sensor.office_illuminance"
        ]];
    section.customProperties = @{@"hours_to_show": @24};
    NSDictionary *entities = @{
        @"sensor.living_room_temperature": [HASnapshotTestHelpers sensorTemperature],
        @"sensor.living_room_humidity": [HASnapshotTestHelpers sensorHumidity],
        @"sensor.office_illuminance": [HASnapshotTestHelpers sensorIlluminance]
    };
    HAGraphCardCell *graphCell = [[HAGraphCardCell alloc] initWithFrame:CGRectMake(0, 0, kColumnWidth, kGraphCardHeight)];
    [graphCell configureWithSection:section entities:entities];
    [graphCell layoutIfNeeded];
    [self verifyView:graphCell identifier:nil];
}

#pragma mark - HAGraphCardCell — With Axis Labels (1 test)

- (void)testGraphSingleWithAxisLabels {
    // Single entity graph: verify Y-axis and X-axis labels render
    HAEntity *entity = [HASnapshotTestHelpers sensorTemperature];
    HADashboardConfigItem *item = [HASnapshotTestHelpers graphCardSingleEntity];
    HAGraphCardCell *graphCell = [[HAGraphCardCell alloc] initWithFrame:CGRectMake(0, 0, kColumnWidth, kGraphCardHeight)];
    [graphCell configureWithEntity:entity item:item];
    [graphCell layoutIfNeeded];
    [self verifyView:graphCell identifier:nil];
}

#pragma mark - HATileEntityCell (2 tests)

- (void)testTileLight {
    HAEntity *entity = [HASnapshotTestHelpers lightEntityOnBrightness];
    CGFloat width = floor(kSubGridUnit * 6);
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(width, kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

- (void)testTileSwitch {
    HAEntity *entity = [HASnapshotTestHelpers switchEntityOn];
    CGFloat width = floor(kSubGridUnit * 6);
    HADashboardConfigItem *item = [HASnapshotTestHelpers itemWithEntityId:entity.entityId
        cardType:@"tile" columnSpan:6 headingIcon:nil displayName:nil];
    UIView *cell = [self cellForEntity:entity cellClass:[HATileEntityCell class]
        size:CGSizeMake(width, kTileHeight) configItem:item];
    [self verifyView:cell identifier:nil];
}

#pragma mark - HAHeadingCell (2 tests)

- (void)testHeadingWithIcon {
    HAHeadingCell *cell = [[HAHeadingCell alloc] initWithFrame:CGRectMake(0, 0, kColumnWidth, kHeadingCellHeight)];
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.cardType = @"heading";
    item.displayName = @"Living Room";
    item.columnSpan = 12;
    item.customProperties = @{@"icon": @"mdi:sofa"};
    [cell configureWithItem:item];
    [cell layoutIfNeeded];
    [self verifyView:cell identifier:nil];
}

- (void)testHeadingNoIcon {
    HAHeadingCell *cell = [[HAHeadingCell alloc] initWithFrame:CGRectMake(0, 0, kColumnWidth, kHeadingCellHeight)];
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.cardType = @"heading";
    item.displayName = @"Living Room";
    item.columnSpan = 12;
    item.customProperties = @{};
    [cell configureWithItem:item];
    [cell layoutIfNeeded];
    [self verifyView:cell identifier:nil];
}

/// heading_style: subtitle — smaller, secondary-coloured text (hui-heading-card .subtitle).
- (void)testHeadingSubtitleStyle {
    HAHeadingCell *cell = [[HAHeadingCell alloc] initWithFrame:CGRectMake(0, 0, kColumnWidth, kHeadingCellHeight)];
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.cardType = @"heading";
    item.displayName = @"Heading 2";
    item.columnSpan = 12;
    item.customProperties = @{@"icon": @"mdi:clock-outline", @"heading_style": @"subtitle"};
    [cell configureWithItem:item];
    [cell layoutIfNeeded];
    [self verifyView:cell identifier:nil];
}

@end
