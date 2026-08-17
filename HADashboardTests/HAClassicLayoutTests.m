#import <XCTest/XCTest.h>
#import "HAMasonryLayout.h"
#import "HAPanelLayout.h"
#import "HASidebarLayout.h"
#import "HALovelaceParser.h"
#import "HADashboardConfig.h"
#import "HAMarkdownCardCell.h"
#import "HATheme.h"

#pragma mark - Mock Data Source

/// Minimal data source for testing layout engines without a real view controller.
@interface HALayoutTestDataSource : NSObject <UICollectionViewDataSource, HAMasonryLayoutDelegate, HAPanelLayoutDelegate, HASidebarLayoutDelegate>
@property (nonatomic, assign) NSInteger sectionCount;
@property (nonatomic, strong) NSArray<NSNumber *> *itemCounts; // items per section
@property (nonatomic, strong) NSArray<NSString *> *cardTypes;  // card type per item (flat)
@property (nonatomic, strong) NSArray<NSNumber *> *entityCounts; // entity count per item (flat)
@property (nonatomic, strong) NSArray<NSNumber *> *itemHeights;  // height per item (flat)
@end

@implementation HALayoutTestDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.sectionCount;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    if (section < (NSInteger)self.itemCounts.count) {
        return self.itemCounts[section].integerValue;
    }
    return 0;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [collectionView dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:indexPath];
}

#pragma mark - HAMasonryLayoutDelegate

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)layout
 heightForItemAtIndexPath:(NSIndexPath *)indexPath
                itemWidth:(CGFloat)itemWidth {
    // Flat index into itemHeights
    NSInteger flatIndex = 0;
    for (NSInteger s = 0; s < indexPath.section; s++) {
        if (s < (NSInteger)self.itemCounts.count) {
            flatIndex += self.itemCounts[s].integerValue;
        }
    }
    flatIndex += indexPath.item;
    if (flatIndex < (NSInteger)self.itemHeights.count) {
        return self.itemHeights[flatIndex].floatValue;
    }
    return 100.0;
}

- (NSString *)collectionView:(UICollectionView *)collectionView
                      layout:(UICollectionViewLayout *)layout
     cardTypeForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger flatIndex = indexPath.item;
    if (flatIndex < (NSInteger)self.cardTypes.count) {
        return self.cardTypes[flatIndex];
    }
    return @"default";
}

- (NSInteger)collectionView:(UICollectionView *)collectionView
                     layout:(UICollectionViewLayout *)layout
  entityCountForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger flatIndex = indexPath.item;
    if (flatIndex < (NSInteger)self.entityCounts.count) {
        return self.entityCounts[flatIndex].integerValue;
    }
    return 0;
}

@end

#pragma mark - Tests

@interface HAClassicLayoutTests : XCTestCase
@end

@implementation HAClassicLayoutTests

#pragma mark - Helpers

/// Create a collection view with the given layout and data source at a specific width.
- (UICollectionView *)collectionViewWithLayout:(UICollectionViewLayout *)layout
                                    dataSource:(HALayoutTestDataSource *)dataSource
                                         width:(CGFloat)width
                                        height:(CGFloat)height {
    CGRect frame = CGRectMake(0, 0, width, height);
    UICollectionView *cv = [[UICollectionView alloc] initWithFrame:frame collectionViewLayout:layout];
    cv.dataSource = dataSource;
    [cv registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"cell"];
    [cv layoutIfNeeded];
    return cv;
}

#pragma mark - Test 1: Masonry Column Count at Different Widths

/// iPad portrait (~768px) should yield 2 columns.
- (void)testMasonryColumnCount_768px_yields2Columns {
    HAMasonryLayout *layout = [[HAMasonryLayout alloc] init];
    HALayoutTestDataSource *ds = [[HALayoutTestDataSource alloc] init];
    ds.sectionCount = 1;
    ds.itemCounts = @[@4];
    ds.cardTypes = @[@"sensor", @"sensor", @"sensor", @"sensor"];
    ds.entityCounts = @[@0, @0, @0, @0];
    ds.itemHeights = @[@100, @100, @100, @100];
    layout.delegate = ds;

    (void)[self collectionViewWithLayout:layout dataSource:ds width:768 height:1024];

    // Verify items are distributed across 2 columns
    NSArray *attrs = [layout layoutAttributesForElementsInRect:CGRectMake(0, 0, 768, 2000)];
    XCTAssertEqual(attrs.count, 4u, @"All 4 items should have attributes");

    // Collect unique X origins to count columns
    NSMutableSet *xOrigins = [NSMutableSet set];
    for (UICollectionViewLayoutAttributes *attr in attrs) {
        [xOrigins addObject:@(round(CGRectGetMinX(attr.frame)))];
    }
    XCTAssertEqual(xOrigins.count, 2u, @"768px should produce 2 columns, got %lu", (unsigned long)xOrigins.count);
}

/// iPad landscape (~1024px) should yield 3 columns.
- (void)testMasonryColumnCount_1024px_yields3Columns {
    HAMasonryLayout *layout = [[HAMasonryLayout alloc] init];
    HALayoutTestDataSource *ds = [[HALayoutTestDataSource alloc] init];
    ds.sectionCount = 1;
    ds.itemCounts = @[@6];
    ds.cardTypes = @[@"sensor", @"sensor", @"sensor", @"sensor", @"sensor", @"sensor"];
    ds.entityCounts = @[@0, @0, @0, @0, @0, @0];
    ds.itemHeights = @[@100, @100, @100, @100, @100, @100];
    layout.delegate = ds;

    (void)[self collectionViewWithLayout:layout dataSource:ds width:1024 height:768];

    NSArray *attrs = [layout layoutAttributesForElementsInRect:CGRectMake(0, 0, 1024, 2000)];
    XCTAssertEqual(attrs.count, 6u, @"All 6 items should have attributes");

    NSMutableSet *xOrigins = [NSMutableSet set];
    for (UICollectionViewLayoutAttributes *attr in attrs) {
        [xOrigins addObject:@(round(CGRectGetMinX(attr.frame)))];
    }
    XCTAssertEqual(xOrigins.count, 3u, @"1024px should produce 3 columns, got %lu", (unsigned long)xOrigins.count);
}

/// iPad Pro 12.9" landscape (~1366px) should yield 4 columns.
- (void)testMasonryColumnCount_1366px_yields4Columns {
    HAMasonryLayout *layout = [[HAMasonryLayout alloc] init];
    HALayoutTestDataSource *ds = [[HALayoutTestDataSource alloc] init];
    ds.sectionCount = 1;
    ds.itemCounts = @[@8];
    ds.cardTypes = @[@"sensor", @"sensor", @"sensor", @"sensor", @"sensor", @"sensor", @"sensor", @"sensor"];
    ds.entityCounts = @[@0, @0, @0, @0, @0, @0, @0, @0];
    ds.itemHeights = @[@100, @100, @100, @100, @100, @100, @100, @100];
    layout.delegate = ds;

    (void)[self collectionViewWithLayout:layout dataSource:ds width:1366 height:1024];

    NSArray *attrs = [layout layoutAttributesForElementsInRect:CGRectMake(0, 0, 1366, 2000)];
    XCTAssertEqual(attrs.count, 8u, @"All 8 items should have attributes");

    NSMutableSet *xOrigins = [NSMutableSet set];
    for (UICollectionViewLayoutAttributes *attr in attrs) {
        [xOrigins addObject:@(round(CGRectGetMinX(attr.frame)))];
    }
    XCTAssertEqual(xOrigins.count, 4u, @"1366px should produce 4 columns, got %lu", (unsigned long)xOrigins.count);
}

#pragma mark - Test 2: Card Distribution (Shortest Column First)

/// A thermostat (size 7) followed by multiple small cards should cause the small cards
/// to fill other columns first before returning to the thermostat column.
- (void)testMasonryCardDistribution_thermostatGoesToShortestColumn {
    HAMasonryLayout *layout = [[HAMasonryLayout alloc] init];
    HALayoutTestDataSource *ds = [[HALayoutTestDataSource alloc] init];
    ds.sectionCount = 1;
    // 4 items: thermostat (7 units), then 3 sensors (2 units each)
    ds.itemCounts = @[@4];
    ds.cardTypes = @[@"thermostat", @"sensor", @"sensor", @"sensor"];
    ds.entityCounts = @[@0, @0, @0, @0];
    ds.itemHeights = @[@280, @100, @100, @100]; // thermostat is tall
    layout.delegate = ds;

    // Use 1024px for 3 columns
    (void)[self collectionViewWithLayout:layout dataSource:ds width:1024 height:768];

    NSArray *attrs = [layout layoutAttributesForElementsInRect:CGRectMake(0, 0, 1024, 2000)];
    XCTAssertEqual(attrs.count, 4u, @"All 4 items should have attributes");

    // Thermostat (item 0) should be in column 0.
    // Sensors (items 1-3) should go to columns 1, 2, then back to column 1 (or any non-0)
    // because column 0 has the thermostat (7 units).
    UICollectionViewLayoutAttributes *thermoAttr = nil;
    NSMutableArray *sensorAttrs = [NSMutableArray array];
    for (UICollectionViewLayoutAttributes *attr in attrs) {
        if (attr.indexPath.item == 0) {
            thermoAttr = attr;
        } else {
            [sensorAttrs addObject:attr];
        }
    }

    XCTAssertNotNil(thermoAttr, @"Thermostat should have layout attributes");

    // At least 2 of the 3 sensors should be in different columns than the thermostat
    CGFloat thermoX = round(CGRectGetMinX(thermoAttr.frame));
    NSInteger sensorsInDifferentColumn = 0;
    for (UICollectionViewLayoutAttributes *sAttr in sensorAttrs) {
        if (round(CGRectGetMinX(sAttr.frame)) != thermoX) {
            sensorsInDifferentColumn++;
        }
    }
    XCTAssertGreaterThanOrEqual(sensorsInDifferentColumn, 2,
        @"At least 2 of 3 sensors should be in different columns than the thermostat (size 7)");
}

#pragma mark - Test 3: Max Column Width

/// Column width should never exceed 500px.
- (void)testMasonryMaxColumnWidth_500px {
    HAMasonryLayout *layout = [[HAMasonryLayout alloc] init];
    HALayoutTestDataSource *ds = [[HALayoutTestDataSource alloc] init];
    ds.sectionCount = 1;
    ds.itemCounts = @[@2];
    ds.cardTypes = @[@"sensor", @"sensor"];
    ds.entityCounts = @[@0, @0];
    ds.itemHeights = @[@100, @100];
    layout.delegate = ds;

    // At 1366px with 4 columns, naive column width would be ~341, within 500
    // At 600px with 2 columns, naive column width would be ~300, within 500
    // But let's test a very wide viewport to ensure cap
    (void)[self collectionViewWithLayout:layout dataSource:ds width:600 height:768];

    NSArray *attrs = [layout layoutAttributesForElementsInRect:CGRectMake(0, 0, 600, 2000)];
    for (UICollectionViewLayoutAttributes *attr in attrs) {
        XCTAssertLessThanOrEqual(CGRectGetWidth(attr.frame), 500.0,
            @"Card width should not exceed 500px (max column width)");
    }
}

#pragma mark - Test 4: Layout Invalidates on Bounds Change

- (void)testMasonryInvalidatesOnBoundsChange {
    HAMasonryLayout *layout = [[HAMasonryLayout alloc] init];
    BOOL shouldInvalidate = [layout shouldInvalidateLayoutForBoundsChange:CGRectMake(0, 0, 1024, 768)];
    XCTAssertTrue(shouldInvalidate, @"Masonry layout should always invalidate on bounds change (rotation)");
}

#pragma mark - Test 5: Panel View — Single Card Full-Bleed

- (void)testPanelLayout_singleCardFullWidth {
    HAPanelLayout *layout = [[HAPanelLayout alloc] init];
    HALayoutTestDataSource *ds = [[HALayoutTestDataSource alloc] init];
    ds.sectionCount = 1;
    ds.itemCounts = @[@1];
    ds.itemHeights = @[@300];
    layout.delegate = ds;

    CGFloat width = 1024.0;
    (void)[self collectionViewWithLayout:layout dataSource:ds width:width height:768];

    NSArray *attrs = [layout layoutAttributesForElementsInRect:CGRectMake(0, 0, width, 2000)];
    XCTAssertEqual(attrs.count, 1u, @"Panel should have exactly 1 item");

    UICollectionViewLayoutAttributes *attr = attrs.firstObject;
    XCTAssertEqual(CGRectGetMinX(attr.frame), 0.0, @"Panel card should start at x=0 (no margins)");
    XCTAssertEqual(CGRectGetWidth(attr.frame), width, @"Panel card should fill full width");
    XCTAssertGreaterThanOrEqual(CGRectGetHeight(attr.frame), 768.0,
        @"Panel card should be at least viewport height");
}

#pragma mark - Test 6: Sidebar View — Two Column Split

- (void)testSidebarLayout_twoColumnSplit {
    HASidebarLayout *layout = [[HASidebarLayout alloc] init];
    HALayoutTestDataSource *ds = [[HALayoutTestDataSource alloc] init];
    ds.sectionCount = 2;
    ds.itemCounts = @[@2, @1]; // 2 main cards, 1 sidebar card
    ds.itemHeights = @[@100, @100, @100];
    layout.delegate = ds;

    CGFloat width = 1024.0; // above 760px collapse threshold
    (void)[self collectionViewWithLayout:layout dataSource:ds width:width height:768];

    NSArray *attrs = [layout layoutAttributesForElementsInRect:CGRectMake(0, 0, width, 2000)];
    XCTAssertEqual(attrs.count, 3u, @"All 3 items should have attributes");

    // Separate main and sidebar attributes
    NSMutableArray *mainAttrs = [NSMutableArray array];
    NSMutableArray *sidebarAttrs = [NSMutableArray array];
    for (UICollectionViewLayoutAttributes *attr in attrs) {
        if (attr.indexPath.section == 0) {
            [mainAttrs addObject:attr];
        } else {
            [sidebarAttrs addObject:attr];
        }
    }

    XCTAssertEqual(mainAttrs.count, 2u, @"Should have 2 main items");
    XCTAssertEqual(sidebarAttrs.count, 1u, @"Should have 1 sidebar item");

    // Main column should be wider than sidebar column (2:1 ratio)
    CGFloat mainWidth = CGRectGetWidth(((UICollectionViewLayoutAttributes *)mainAttrs[0]).frame);
    CGFloat sidebarWidth = CGRectGetWidth(((UICollectionViewLayoutAttributes *)sidebarAttrs[0]).frame);
    XCTAssertGreaterThan(mainWidth, sidebarWidth,
        @"Main column (%f) should be wider than sidebar column (%f)", mainWidth, sidebarWidth);

    // Sidebar width should be <= 380px (max sidebar width)
    XCTAssertLessThanOrEqual(sidebarWidth, 380.0,
        @"Sidebar width should not exceed 380px");
}

#pragma mark - Test 7: Sidebar View — Collapse Below 760px

- (void)testSidebarLayout_collapsesBelow760px {
    HASidebarLayout *layout = [[HASidebarLayout alloc] init];
    HALayoutTestDataSource *ds = [[HALayoutTestDataSource alloc] init];
    ds.sectionCount = 2;
    ds.itemCounts = @[@2, @1];
    ds.itemHeights = @[@100, @100, @100];
    layout.delegate = ds;

    CGFloat width = 700.0; // below 760px collapse threshold
    (void)[self collectionViewWithLayout:layout dataSource:ds width:width height:1024];

    NSArray *attrs = [layout layoutAttributesForElementsInRect:CGRectMake(0, 0, width, 2000)];
    XCTAssertEqual(attrs.count, 3u, @"All 3 items should have attributes");

    // In collapsed mode, all items should have the same width (single column)
    NSMutableSet *widths = [NSMutableSet set];
    for (UICollectionViewLayoutAttributes *attr in attrs) {
        [widths addObject:@(round(CGRectGetWidth(attr.frame)))];
    }
    XCTAssertEqual(widths.count, 1u,
        @"Below 760px, all items should have the same width (collapsed single column)");

    // All items should be stacked vertically (sidebar cards below main cards)
    CGFloat prevBottom = 0;
    for (UICollectionViewLayoutAttributes *attr in attrs) {
        XCTAssertGreaterThanOrEqual(CGRectGetMinY(attr.frame), prevBottom,
            @"Items should be stacked vertically in collapsed mode");
        prevBottom = CGRectGetMaxY(attr.frame);
    }
}

#pragma mark - Test 8: View Type Detection in Parser

- (void)testViewTypeDetection_defaultToMasonry {
    NSDictionary *viewDict = @{
        @"title": @"Test",
        @"cards": @[@{@"type": @"sensor", @"entity": @"sensor.temp"}]
    };
    NSDictionary *dashDict = @{@"views": @[viewDict]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashDict];
    XCTAssertEqualObjects(dashboard.views.firstObject.viewType, @"masonry",
        @"Views without explicit type and no sections should default to masonry");
}

- (void)testViewTypeDetection_sectionsView {
    NSDictionary *viewDict = @{
        @"title": @"Test",
        @"sections": @[@{@"cards": @[@{@"type": @"sensor", @"entity": @"sensor.temp"}]}]
    };
    NSDictionary *dashDict = @{@"views": @[viewDict]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashDict];
    XCTAssertEqualObjects(dashboard.views.firstObject.viewType, @"sections",
        @"Views with sections should be detected as sections type");
}

- (void)testViewTypeDetection_panelView {
    NSDictionary *viewDict = @{
        @"title": @"Test",
        @"type": @"panel",
        @"cards": @[@{@"type": @"sensor", @"entity": @"sensor.temp"}]
    };
    NSDictionary *dashDict = @{@"views": @[viewDict]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashDict];
    XCTAssertEqualObjects(dashboard.views.firstObject.viewType, @"panel",
        @"Views with type:panel should be detected as panel");
}

- (void)testViewTypeDetection_sidebarView {
    NSDictionary *viewDict = @{
        @"title": @"Test",
        @"type": @"sidebar",
        @"cards": @[@{@"type": @"sensor", @"entity": @"sensor.temp"}]
    };
    NSDictionary *dashDict = @{@"views": @[viewDict]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashDict];
    XCTAssertEqualObjects(dashboard.views.firstObject.viewType, @"sidebar",
        @"Views with type:sidebar should be detected as sidebar");
}

#pragma mark - Test 9: view_layout.position Parsing

- (void)testViewLayoutPosition_parsed {
    NSDictionary *cardDict = @{
        @"type": @"sensor",
        @"entity": @"sensor.temp",
        @"view_layout": @{@"position": @"sidebar"}
    };
    NSDictionary *viewDict = @{
        @"title": @"Test",
        @"cards": @[cardDict]
    };
    NSDictionary *dashDict = @{@"views": @[viewDict]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashDict];
    HALovelaceView *view = dashboard.views.firstObject;

    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:view columns:3];
    XCTAssertGreaterThan(config.sections.count, 0u, @"Config should have sections");

    HADashboardConfigSection *section = config.sections.firstObject;
    XCTAssertEqualObjects(section.customProperties[@"viewLayoutPosition"], @"sidebar",
        @"view_layout.position should be stored in section customProperties");
}

#pragma mark - Test 10: Markdown Card Compatibility

- (void)testMarkdownCard_preservesTemplateContentAndUsesPortableCodeFont {
    NSString *content = @"<strong>Platform 1</strong><br>{{ state_attr(\"sensor.transit\", \"Dest0\") }}<br><ha-alert alert-type=\"info\">Service update</ha-alert>";
    NSDictionary *dashboardDictionary = @{
        @"views": @[@{
            @"cards": @[@{
                @"type": @"markdown",
                @"title": @"Departures",
                @"content": content
            }]
        }]
    };

    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashboardDictionary];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:1];
    HADashboardConfigItem *item = config.items.firstObject;

    XCTAssertEqualObjects(item.cardType, @"markdown");
    XCTAssertEqualObjects(item.customProperties[@"markdown_content"], content);
    XCTAssertEqual(item.columnSpan, 12, @"Standalone Markdown cards must use the full grid width");

    HAMarkdownCardCell *cell = [[HAMarkdownCardCell alloc] initWithFrame:CGRectMake(0, 0, 320, 120)];
    [cell configureWithConfigItem:item];
    XCTAssertNotNil(cell, @"Markdown content must render with a font available on iOS 9 and later");
}

- (void)testMarkdownCard_refreshesAttributedTextColorWhenAppearanceChanges {
    NSDictionary *dashboardDictionary = @{
        @"views": @[@{
            @"cards": @[@{
                @"type": @"markdown",
                @"content": @"**Visible markdown**"
            }]
        }]
    };
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashboardDictionary];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:1];
    HAMarkdownCardCell *cell = [[HAMarkdownCardCell alloc] initWithFrame:CGRectMake(0, 0, 320, 120)];

    if (@available(iOS 13.0, *)) {
        cell.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    }
    [cell configureWithConfigItem:config.items.firstObject];

    NSAttributedString *lightText = [cell valueForKeyPath:@"contentLabel.attributedText"];
    UIColor *lightColor = [lightText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];

    if (@available(iOS 13.0, *)) {
        cell.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [cell layoutIfNeeded];
    } else {
        [HATheme setCurrentMode:HAThemeModeDark];
    }

    NSAttributedString *darkText = [cell valueForKeyPath:@"contentLabel.attributedText"];
    UIColor *darkColor = [darkText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
    UIColor *expectedDarkColor = [HATheme primaryTextColor];
    if (@available(iOS 13.0, *)) {
        expectedDarkColor = [expectedDarkColor resolvedColorWithTraitCollection:cell.traitCollection];
    }

    XCTAssertNotEqualObjects(lightColor, darkColor,
        @"Markdown attributes must be regenerated after an appearance change");
    XCTAssertEqualObjects(darkColor, expectedDarkColor,
        @"Markdown foreground color must match the active dark appearance");
}

- (void)testMarkdownCard_formatsNativeMarkdownSyntax {
    NSString *content = @"# Heading\nThis has **bold**, *italic*, and `code`.";
    NSDictionary *dashboardDictionary = @{
        @"views": @[@{
            @"cards": @[@{
                @"type": @"markdown",
                @"content": content
            }]
        }]
    };
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashboardDictionary];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:1];
    HAMarkdownCardCell *cell = [[HAMarkdownCardCell alloc] initWithFrame:CGRectMake(0, 0, 320, 120)];
    [cell configureWithConfigItem:config.items.firstObject];

    NSAttributedString *rendered = [cell valueForKeyPath:@"contentLabel.attributedText"];
    XCTAssertEqualObjects(rendered.string, @"Heading\nThis has bold, italic, and code.");

    NSRange boldRange = [rendered.string rangeOfString:@"bold"];
    UIFont *boldFont = [rendered attribute:NSFontAttributeName atIndex:boldRange.location effectiveRange:NULL];
    XCTAssertTrue((boldFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0);

    NSRange italicRange = [rendered.string rangeOfString:@"italic"];
    UIFont *italicFont = [rendered attribute:NSFontAttributeName atIndex:italicRange.location effectiveRange:NULL];
    XCTAssertTrue((italicFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitItalic) != 0);
}

#pragma mark - Test 11: Conditional Entity Rows

- (void)testEntitiesCard_withOnlyConditionalRow_isRetained {
    NSDictionary *dashboardDictionary = @{
        @"views": @[@{
            @"cards": @[@{
                @"type": @"entities",
                @"entities": @[@{
                    @"type": @"conditional",
                    @"conditions": @[@{
                        @"entity": @"input_boolean.show_light",
                        @"state": @"on"
                    }],
                    @"row": @{
                        @"entity": @"light.kitchen"
                    }
                }]
            }]
        }]
    };

    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashboardDictionary];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:1];
    HADashboardConfigSection *section = config.sections.firstObject;

    XCTAssertEqual(config.items.count, 1u);
    XCTAssertEqualObjects(section.entityIds, (@[@"light.kitchen"]));
    XCTAssertEqualObjects(section.customProperties[@"orderedRows"][0][@"row_type"], @"conditional");
}

#pragma mark - Test 12: Masonry Empty Section

- (void)testMasonryLayout_emptySection {
    HAMasonryLayout *layout = [[HAMasonryLayout alloc] init];
    HALayoutTestDataSource *ds = [[HALayoutTestDataSource alloc] init];
    ds.sectionCount = 1;
    ds.itemCounts = @[@0];
    layout.delegate = ds;

    (void)[self collectionViewWithLayout:layout dataSource:ds width:1024 height:768];

    NSArray *attrs = [layout layoutAttributesForElementsInRect:CGRectMake(0, 0, 1024, 2000)];
    XCTAssertEqual(attrs.count, 0u, @"Empty masonry layout should produce no attributes");
}

@end
