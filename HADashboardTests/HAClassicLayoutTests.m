#import <XCTest/XCTest.h>
#import "HAMasonryLayout.h"
#import "HAColumnarLayout.h"
#import "HAPanelLayout.h"
#import "HASidebarLayout.h"
#import "HALovelaceParser.h"
#import "HADashboardConfig.h"
#import "HAMarkdownCardCell.h"
#import "HATheme.h"

#pragma mark - Mock Data Source

/// Minimal data source for testing layout engines without a real view controller.
@interface HALayoutTestDataSource : NSObject <UICollectionViewDataSource, HAMasonryLayoutDelegate, HAPanelLayoutDelegate, HASidebarLayoutDelegate, HAColumnarLayoutDelegate>
@property (nonatomic, assign) NSInteger sectionCount;
@property (nonatomic, strong) NSArray<NSNumber *> *itemCounts; // items per section
@property (nonatomic, strong) NSArray<NSString *> *cardTypes;  // card type per item (flat)
@property (nonatomic, strong) NSArray<NSNumber *> *entityCounts; // entity count per item (flat)
@property (nonatomic, strong) NSArray<NSNumber *> *itemHeights;  // height per item (flat)
/// Sub-grid column span per item (flat); nil = every item spans 12
@property (nonatomic, strong) NSArray<NSNumber *> *itemGridColumns;
/// Columnar layout: column_span per section; nil = 1
@property (nonatomic, strong) NSArray<NSNumber *> *sectionSpans;
/// Leading full-width items (masonry, section 0) / sections (columnar)
@property (nonatomic, assign) NSInteger fullWidthCount;
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

- (BOOL)collectionView:(UICollectionView *)collectionView
                layout:(UICollectionViewLayout *)layout
isFullWidthItemAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 && indexPath.item < self.fullWidthCount;
}

#pragma mark - HAColumnarLayoutDelegate

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)layout
 heightForHeaderInSection:(NSInteger)section {
    return 0;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView
                     layout:(UICollectionViewLayout *)layout
  gridColumnsForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger flatIndex = indexPath.item;
    for (NSInteger sec = 0; sec < indexPath.section && sec < (NSInteger)self.itemCounts.count; sec++) {
        flatIndex += self.itemCounts[sec].integerValue;
    }
    if (flatIndex < (NSInteger)self.itemGridColumns.count) {
        return self.itemGridColumns[flatIndex].integerValue;
    }
    return 12;
}

- (BOOL)collectionView:(UICollectionView *)collectionView
                layout:(UICollectionViewLayout *)layout
    isFullWidthSection:(NSInteger)section {
    return section < self.fullWidthCount;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView
                     layout:(UICollectionViewLayout *)layout
       columnSpanForSection:(NSInteger)section {
    return section < (NSInteger)self.sectionSpans.count ? self.sectionSpans[section].integerValue : 1;
}

@end

#pragma mark - Tests

@interface HAClassicLayoutTests : XCTestCase
@property (nonatomic, strong) NSMutableArray *retainedLayoutObjects;
@end

@implementation HAClassicLayoutTests

- (void)setUp {
    [super setUp];
    self.retainedLayoutObjects = [NSMutableArray array];
}

- (void)tearDown {
    self.retainedLayoutObjects = nil;
    [super tearDown];
}

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
    XCTAssertEqualObjects(item.customProperties[@"markdown_template"], content);
    XCTAssertEqualObjects(item.customProperties[@"markdown_template_dependencies"], @[@"sensor.transit"]);

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

    // Host the cell in a real window with a root view controller. UIKit does
    // not reliably deliver traitCollectionDidChange: for overrideUserInterfaceStyle
    // changes to a view that isn't part of a window's hierarchy, and this test
    // relies on that callback firing to re-resolve the dynamic theme color.
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 120)];
    window.rootViewController = [[UIViewController alloc] init];
    [window.rootViewController.view addSubview:cell];
    [window makeKeyAndVisible];

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

    window.hidden = YES;
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

- (void)testMarkdownCard_formatsSupportedSafeHTML {
    NSString *content = @"<strong>Platform 1</strong><br><em>Next service</em> <small>updated</small><br><ha-alert alert-type=\"info\">Service update</ha-alert>";
    NSDictionary *dashboardDictionary = @{
        @"views": @[@{ @"cards": @[@{ @"type": @"markdown", @"content": content }] }]
    };
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashboardDictionary];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:1];
    HAMarkdownCardCell *cell = [[HAMarkdownCardCell alloc] initWithFrame:CGRectMake(0, 0, 320, 120)];
    [cell configureWithConfigItem:config.items.firstObject];

    NSAttributedString *rendered = [cell valueForKeyPath:@"contentLabel.attributedText"];
    XCTAssertEqualObjects(rendered.string, @"Platform 1\nNext service updated\nService update");
    NSRange strongRange = [rendered.string rangeOfString:@"Platform 1"];
    UIFont *strongFont = [rendered attribute:NSFontAttributeName atIndex:strongRange.location effectiveRange:NULL];
    XCTAssertTrue((strongFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0);
    NSRange italicRange = [rendered.string rangeOfString:@"Next service"];
    UIFont *italicFont = [rendered attribute:NSFontAttributeName atIndex:italicRange.location effectiveRange:NULL];
    XCTAssertTrue((italicFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitItalic) != 0);
    NSRange smallRange = [rendered.string rangeOfString:@"updated"];
    UIFont *smallFont = [rendered attribute:NSFontAttributeName atIndex:smallRange.location effectiveRange:NULL];
    XCTAssertLessThan(smallFont.pointSize, 13.0);
    XCTAssertFalse([rendered.string containsString:@"<"]);
}

- (void)testMarkdownCard_formatsSafeBlocksAndAlerts {
    NSString *content = @"> quoted\n1. numbered\n---\n<p>paragraph</p><div>division</div><pre>let x = 1;</pre><ha-alert alert-type=\"warning\">Careful</ha-alert>";
    NSDictionary *dashboardDictionary = @{
        @"views": @[@{ @"cards": @[@{ @"type": @"markdown", @"content": content }] }]
    };
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashboardDictionary];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:1];
    HAMarkdownCardCell *cell = [[HAMarkdownCardCell alloc] initWithFrame:CGRectMake(0, 0, 320, 240)];
    [cell configureWithConfigItem:config.items.firstObject];

    NSAttributedString *rendered = [cell valueForKeyPath:@"contentLabel.attributedText"];
    XCTAssertEqualObjects(rendered.string, @"│ quoted\n1. numbered\n────────\nparagraph\ndivision\nlet x = 1;\nCareful");
    NSRange codeRange = [rendered.string rangeOfString:@"let x = 1;"];
    UIFont *codeFont = [rendered attribute:NSFontAttributeName atIndex:codeRange.location effectiveRange:NULL];
    XCTAssertTrue([codeFont.fontName.lowercaseString containsString:@"menlo"] || [codeFont.fontName.lowercaseString containsString:@"mono"]);
    NSRange alertRange = [rendered.string rangeOfString:@"Careful"];
    XCTAssertNotNil([rendered attribute:NSBackgroundColorAttributeName atIndex:alertRange.location effectiveRange:NULL]);
    XCTAssertFalse([rendered.string containsString:@"<"]);
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

#pragma mark - Test 13: Tile Card Object Name Resolution

- (NSDictionary *)dashboardWithTileCard:(NSDictionary *)nameValue entityId:(NSString *)entityId {
    return @{
        @"views": @[@{
            @"title": @"Test",
            @"cards": @[@{
                @"type": @"tile",
                @"entity": entityId,
                @"name": nameValue
            }]
        }]
    };
}

- (void)testTileCard_objectName_area_resolvesAreaName {
    NSDictionary *dict = [self dashboardWithTileCard:@{@"type": @"area"} entityId:@"sensor.bedroom_temp"];
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject
                                                                  columns:3
                                                            entityAreaMap:@{@"sensor.bedroom_temp": @"area_bedroom"}
                                                                areaNames:@{@"area_bedroom": @"Bedroom"}
                                                          entityDeviceMap:@{}
                                                              deviceNames:@{}];
    XCTAssertEqualObjects(config.items.firstObject.displayName, @"Bedroom");
}

- (void)testTileCard_objectName_device_resolvesDeviceName {
    NSDictionary *dict = [self dashboardWithTileCard:@{@"type": @"device"} entityId:@"sensor.bedroom_temp"];
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject
                                                                  columns:3
                                                            entityAreaMap:@{}
                                                                areaNames:@{}
                                                          entityDeviceMap:@{@"sensor.bedroom_temp": @"device_abc"}
                                                              deviceNames:@{@"device_abc": @"Bedroom Sensor"}];
    XCTAssertEqualObjects(config.items.firstObject.displayName, @"Bedroom Sensor");
}

- (void)testTileCard_objectName_unknownType_doesNotCrash {
    NSDictionary *dict = [self dashboardWithTileCard:@{@"type": @"something_future"} entityId:@"sensor.bedroom_temp"];
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    XCTAssertNoThrow({
        (void)[HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject
                                               columns:3
                                         entityAreaMap:@{}
                                             areaNames:@{}
                                       entityDeviceMap:@{}
                                           deviceNames:@{}];
    });
}

- (void)testTileCard_objectName_noRegistryData_doesNotCrash {
    NSDictionary *dict = [self dashboardWithTileCard:@{@"type": @"area"} entityId:@"sensor.bedroom_temp"];
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    XCTAssertNoThrow({
        (void)[HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3];
    });
}

- (void)testTileCard_objectName_floor_resolvesFloorName {
    NSDictionary *dict = [self dashboardWithTileCard:@{@"type": @"floor"} entityId:@"sensor.bedroom_temp"];
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject
                                                                    columns:3
                                                              entityAreaMap:@{@"sensor.bedroom_temp": @"area_bedroom"}
                                                                  areaNames:@{@"area_bedroom": @"Bedroom"}
                                                            entityDeviceMap:@{}
                                                                deviceNames:@{}
                                                         floorNamesByAreaId:@{@"area_bedroom": @"Upstairs"}];
    XCTAssertEqualObjects(config.items.firstObject.displayName, @"Upstairs");
}

- (void)testTileCard_objectName_text_returnsLiteralText {
    NSDictionary *dict = [self dashboardWithTileCard:@{@"type": @"text", @"text": @"Hello"} entityId:@"sensor.bedroom_temp"];
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3];
    XCTAssertEqualObjects(config.items.firstObject.displayName, @"Hello");
}

#pragma mark - Test 14: Entities Card Row Name Resolution

- (NSDictionary *)dashboardWithEntitiesCardRows:(NSArray *)entities {
    return @{
        @"views": @[@{
            @"title": @"Test",
            @"cards": @[@{
                @"type": @"entities",
                @"entities": entities
            }]
        }]
    };
}

- (void)testEntitiesCardRow_objectName_area_resolvesAreaName {
    NSDictionary *dict = [self dashboardWithEntitiesCardRows:@[
        @{@"entity": @"light.bedroom", @"name": @{@"type": @"area"}}
    ]];
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject
                                                                    columns:3
                                                              entityAreaMap:@{@"light.bedroom": @"area_bedroom"}
                                                                  areaNames:@{@"area_bedroom": @"Bedroom"}
                                                            entityDeviceMap:@{}
                                                                deviceNames:@{}];
    NSDictionary<NSString *, NSString *> *nameOverrides = config.sections.firstObject.nameOverrides;
    XCTAssertEqualObjects(nameOverrides[@"light.bedroom"], @"Bedroom");
}

- (void)testEntitiesCardRow_objectName_arrayForm_joinsResolvedParts {
    NSDictionary *dict = [self dashboardWithEntitiesCardRows:@[
        @{@"entity": @"light.bedroom", @"name": @[@{@"type": @"area"}, @{@"type": @"device"}]}
    ]];
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject
                                                                    columns:3
                                                              entityAreaMap:@{@"light.bedroom": @"area_bedroom"}
                                                                  areaNames:@{@"area_bedroom": @"Bedroom"}
                                                            entityDeviceMap:@{@"light.bedroom": @"device_abc"}
                                                                deviceNames:@{@"device_abc": @"Lamp"}];
    NSDictionary<NSString *, NSString *> *nameOverrides = config.sections.firstObject.nameOverrides;
    XCTAssertEqualObjects(nameOverrides[@"light.bedroom"], @"Bedroom Lamp");
}

- (void)testEntitiesCardRow_objectName_arrayForm_withTextAndUnresolvedItem_skipsUnresolved {
    NSDictionary *dict = [self dashboardWithEntitiesCardRows:@[
        @{@"entity": @"light.bedroom", @"name": @[@{@"type": @"text", @"text": @"Main"},
                                                    @{@"type": @"area"}]}
    ]];
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    // No area registered for light.bedroom — the area part resolves to nothing
    // and is dropped, leaving just the text part.
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject
                                                                    columns:3
                                                              entityAreaMap:@{}
                                                                  areaNames:@{}
                                                            entityDeviceMap:@{}
                                                                deviceNames:@{}];
    NSDictionary<NSString *, NSString *> *nameOverrides = config.sections.firstObject.nameOverrides;
    XCTAssertEqualObjects(nameOverrides[@"light.bedroom"], @"Main");
}

- (void)testEntitiesCardRow_objectName_unknownType_fallsBackNoCrash {
    NSDictionary *dict = [self dashboardWithEntitiesCardRows:@[
        @{@"entity": @"light.bedroom", @"name": @{@"type": @"something_future"}}
    ]];
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    HADashboardConfig *config;
    XCTAssertNoThrow({
        config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3];
    });
    // Unresolved — no override stored, caller falls back to the entity's own name.
    XCTAssertNil(config.sections.firstObject.nameOverrides[@"light.bedroom"]);
}

- (void)testEntitiesCardRow_objectName_nonsenseValues_doNotCrash {
    // A number, and an array whose element is itself an array — both nonsense,
    // neither should resolve to anything or throw.
    NSDictionary *dict = [self dashboardWithEntitiesCardRows:@[
        @{@"entity": @"light.a", @"name": @42},
        @{@"entity": @"light.b", @"name": @[@[@"nested"], @{@"type": @"area"}]}
    ]];
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    HADashboardConfig *config;
    XCTAssertNoThrow({
        config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject
                                                     columns:3
                                               entityAreaMap:@{@"light.b": @"area_x"}
                                                   areaNames:@{@"area_x": @"Office"}
                                             entityDeviceMap:@{}
                                                 deviceNames:@{}];
    });
    XCTAssertNil(config.sections.firstObject.nameOverrides[@"light.a"]);
    // light.b: nested-array slot resolves to "", area slot resolves — single
    // non-empty part survives the join.
    XCTAssertEqualObjects(config.sections.firstObject.nameOverrides[@"light.b"], @"Office");
}

#pragma mark - Sections view headings (GitHub #23)

- (HADashboardConfig *)sectionsConfigWithCards:(NSArray *)cards {
    NSDictionary *dict = @{@"views": @[@{@"title": @"Test", @"sections": @[@{@"type": @"grid", @"cards": cards}]}]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    return [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3];
}

/// The reporter's section: the first heading is the section header, the second
/// is a full-width heading item between the two tiles, in card order.
- (void)testSectionsView_twoHeadings_secondIsStandaloneHeadingBetweenTiles {
    HADashboardConfig *config = [self sectionsConfigWithCards:@[
        @{@"type": @"heading", @"heading": @"Heading 1", @"icon": @"mdi:numeric-1"},
        @{@"type": @"tile", @"entity": @"sensor.backup_backup_manager_state"},
        @{@"type": @"heading", @"heading": @"Heading 2", @"icon": @"mdi:numeric-2"},
        @{@"type": @"tile", @"entity": @"sensor.backup_last_successful_automatic_backup"},
    ]];
    XCTAssertEqual(config.sections.count, 1u);
    HADashboardConfigSection *section = config.sections.firstObject;
    XCTAssertEqualObjects(section.title, @"Heading 1");
    XCTAssertEqualObjects(section.icon, @"mdi:numeric-1");

    NSArray<HADashboardConfigItem *> *items = section.items;
    XCTAssertEqual(items.count, 3u, @"tile, heading, tile — got %@", [items valueForKey:@"cardType"]);
    XCTAssertEqualObjects(items[0].cardType, @"tile");
    XCTAssertEqualObjects(items[0].entityId, @"sensor.backup_backup_manager_state");
    XCTAssertEqual(items[0].columnSpan, 6, @"HA tile default in sections is 6 of 12 columns");
    XCTAssertEqualObjects(items[1].cardType, @"heading");
    XCTAssertEqualObjects(items[1].displayName, @"Heading 2");
    XCTAssertEqualObjects(items[1].customProperties[@"icon"], @"mdi:numeric-2");
    XCTAssertEqual(items[1].columnSpan, 12, @"A heading spans the full section so the next tile starts a new row");
    XCTAssertEqualObjects(items[2].cardType, @"tile");
    XCTAssertEqualObjects(items[2].entityId, @"sensor.backup_last_successful_automatic_backup");
    XCTAssertEqual(items[2].columnSpan, 6);
    XCTAssertEqualObjects([config.items valueForKey:@"cardType"], (@[@"tile", @"heading", @"tile"]));
}

/// A heading that isn't the section's first card is not the section title — it renders in place.
- (void)testSectionsView_headingNotFirst_isStandaloneInPlace {
    HADashboardConfig *config = [self sectionsConfigWithCards:@[
        @{@"type": @"tile", @"entity": @"light.a"},
        @{@"type": @"heading", @"heading": @"Later", @"heading_style": @"subtitle"},
        @{@"type": @"tile", @"entity": @"light.b"},
    ]];
    HADashboardConfigSection *section = config.sections.firstObject;
    XCTAssertNil(section.title, @"Only a heading that opens the section becomes its header");
    XCTAssertEqualObjects([section.items valueForKey:@"cardType"], (@[@"tile", @"heading", @"tile"]));
    HADashboardConfigItem *heading = section.items[1];
    XCTAssertEqualObjects(heading.displayName, @"Later");
    XCTAssertEqualObjects(heading.customProperties[@"heading_style"], @"subtitle");
    XCTAssertNil(heading.customProperties[@"icon"]);
}

/// A standalone heading with the same text as the section header keeps its text,
/// and carries its own visibility conditions.
- (void)testSectionsView_standaloneHeading_keepsTextAndVisibility {
    NSArray *visibility = @[@{@"condition": @"state", @"entity": @"input_boolean.show", @"state": @"on"}];
    HADashboardConfig *config = [self sectionsConfigWithCards:@[
        @{@"type": @"heading", @"heading": @"Lights"},
        @{@"type": @"tile", @"entity": @"light.a"},
        @{@"type": @"heading", @"heading": @"Lights", @"visibility": visibility},
        @{@"type": @"tile", @"entity": @"light.b"},
    ]];
    HADashboardConfigSection *section = config.sections.firstObject;
    XCTAssertEqualObjects(section.title, @"Lights");
    HADashboardConfigItem *heading = section.items[1];
    XCTAssertEqualObjects(heading.cardType, @"heading");
    XCTAssertEqualObjects(heading.displayName, @"Lights");
    XCTAssertEqualObjects(heading.visibilityConditions, visibility);
    XCTAssertNil(section.items[2].visibilityConditions, @"The heading's visibility must not leak onto the next card");
}

/// Regression guard (CLAUDE.md "Grid headings"): a heading nested in a grid
/// card with explicit columns stays embedded in its first content item.
- (void)testSectionsView_gridHeading_staysEmbeddedHeadingIcon {
    HADashboardConfig *config = [self sectionsConfigWithCards:@[
        @{@"type": @"grid", @"grid_options": @{@"columns": @9}, @"cards": @[
            @{@"type": @"heading", @"heading": @"House Climate", @"icon": @"mdi:hvac"},
            @{@"type": @"thermostat", @"entity": @"climate.aidoo"},
        ]},
        @{@"type": @"grid", @"grid_options": @{@"columns": @3}, @"cards": @[
            @{@"type": @"heading", @"heading": @"Ribbit", @"icon": @"mdi:robot-vacuum"},
            @{@"type": @"tile", @"entity": @"vacuum.saros_10"},
        ]},
    ]];
    NSArray<HADashboardConfigItem *> *items = config.sections.firstObject.items;
    XCTAssertEqualObjects([items valueForKey:@"cardType"], (@[@"thermostat", @"tile"]));
    XCTAssertEqualObjects(items[0].displayName, @"House Climate");
    XCTAssertEqualObjects(items[0].customProperties[@"headingIcon"], @"mdi:hvac");
    XCTAssertEqualObjects(items[1].displayName, @"Ribbit");
    XCTAssertEqualObjects(items[1].customProperties[@"headingIcon"], @"mdi:robot-vacuum");
}

#pragma mark - Heading badges

/// The section's opening heading (→ section header) and a later heading
/// (→ standalone heading item) each keep their badges, normalized like
/// hui-entity-heading-badge, and an actionable heading tap_action.
- (void)testSectionsView_headingBadges_sectionHeaderAndStandalone {
    NSDictionary *navigate = @{@"action": @"navigate", @"navigation_path": @"/climate"};
    HADashboardConfig *config = [self sectionsConfigWithCards:@[
        @{@"type": @"heading", @"heading": @"Climate", @"icon": @"mdi:thermostat", @"tap_action": navigate,
          @"badges": @[
              @{@"type": @"entity", @"entity": @"sensor.a", @"color": @"red", @"state_content": @"last_changed"},
              @"sensor.b",                                                                  // bare entity id
              @{@"entity": @"sensor.c", @"show_state": @NO, @"hold_action": navigate,       // typeless → entity
                @"visibility": @[@{@"condition": @"state", @"entity": @"sun.sun", @"state": @"above_horizon"}]},
              @{@"type": @"button", @"icon": @"mdi:plus"},                                  // button badge → skipped
              @{@"type": @"entity"},                                                        // no entity → skipped
          ]},
        @{@"type": @"tile", @"entity": @"climate.a"},
        @{@"type": @"heading", @"heading": @"Later", @"tap_action": @{@"action": @"none"},
          @"badges": @[@{@"entity": @"sensor.d", @"show_icon": @NO}],
          @"entities": @[@"sensor.e"]},                                                     // legacy, appended
        @{@"type": @"tile", @"entity": @"climate.b"},
    ]];
    HADashboardConfigSection *section = config.sections.firstObject;
    XCTAssertEqualObjects(section.title, @"Climate");

    NSArray<NSDictionary *> *header = section.customProperties[HAHeadingBadgesKey];
    XCTAssertEqualObjects([header valueForKey:@"entity"], (@[@"sensor.a", @"sensor.b", @"sensor.c"]));
    XCTAssertEqualObjects([header valueForKey:@"type"], (@[@"entity", @"entity", @"entity"]));
    XCTAssertEqualObjects([header valueForKey:@"show_state"], (@[@YES, @YES, @NO]));
    XCTAssertEqualObjects([header valueForKey:@"show_icon"], (@[@YES, @YES, @YES]));
    XCTAssertEqualObjects(header[0][@"color"], @"red");
    XCTAssertEqualObjects(header[0][@"state_content"], @"last_changed");
    XCTAssertEqualObjects(header[1][@"tap_action"], (@{@"action": @"none"}), @"HA heading badge actions default to none");
    XCTAssertEqualObjects(header[1][@"double_tap_action"], (@{@"action": @"none"}));
    XCTAssertEqualObjects(header[2][@"hold_action"], navigate);
    XCTAssertNotNil(header[2][@"visibility"]);
    XCTAssertEqualObjects(section.customProperties[HAHeadingTapActionKey], navigate);

    XCTAssertEqualObjects([section.items valueForKey:@"cardType"], (@[@"tile", @"heading", @"tile"]));
    HADashboardConfigItem *later = section.items[1];
    NSArray<NSDictionary *> *laterBadges = later.customProperties[HAHeadingBadgesKey];
    XCTAssertEqualObjects([laterBadges valueForKey:@"entity"], (@[@"sensor.d", @"sensor.e"]),
                          @"Legacy heading \"entities\" are appended after \"badges\"");
    XCTAssertEqualObjects([laterBadges valueForKey:@"show_icon"], (@[@NO, @YES]));
    XCTAssertNil(later.customProperties[HAHeadingTapActionKey], @"tap_action none is not actionable");
    XCTAssertNil(section.items[0].customProperties[HAHeadingBadgesKey]);
}

/// A heading with only badges still renders (as HA does), and a heading
/// without badges carries no badge key.
- (void)testSectionsView_headingBadges_badgesOnlyHeadingAndNone {
    HADashboardConfig *config = [self sectionsConfigWithCards:@[
        @{@"type": @"heading", @"heading": @"Plain"},
        @{@"type": @"tile", @"entity": @"light.a"},
        @{@"type": @"heading", @"badges": @[@"sensor.only"]},
        @{@"type": @"tile", @"entity": @"light.b"},
    ]];
    HADashboardConfigSection *section = config.sections.firstObject;
    XCTAssertNil(section.customProperties[HAHeadingBadgesKey]);
    XCTAssertEqualObjects([section.items valueForKey:@"cardType"], (@[@"tile", @"heading", @"tile"]));
    XCTAssertNil(section.items[1].displayName);
    XCTAssertEqualObjects([section.items[1].customProperties[HAHeadingBadgesKey] valueForKey:@"entity"], (@[@"sensor.only"]));
}

/// A heading embedded above a grid's first card (headingIcon mechanism, never a
/// standalone item) keeps its badges on that card's item; packing is unchanged.
- (void)testSectionsView_gridHeadingBadges_rideOnEmbeddedHeadingItem {
    HADashboardConfig *config = [self sectionsConfigWithCards:@[
        @{@"type": @"grid", @"grid_options": @{@"columns": @9}, @"cards": @[
            @{@"type": @"heading", @"heading": @"House Climate", @"icon": @"mdi:hvac",
              @"badges": @[@"sensor.outdoor_temperature"]},
            @{@"type": @"thermostat", @"entity": @"climate.aidoo"},
            @{@"type": @"tile", @"entity": @"light.a"},
        ]},
        @{@"type": @"grid", @"grid_options": @{@"columns": @3}, @"cards": @[
            @{@"type": @"heading", @"heading": @"Ribbit", @"icon": @"mdi:robot-vacuum"},
            @{@"type": @"tile", @"entity": @"vacuum.saros_10"},
        ]},
    ]];
    NSArray<HADashboardConfigItem *> *items = config.sections.firstObject.items;
    XCTAssertEqualObjects([items valueForKey:@"cardType"], (@[@"thermostat", @"tile", @"tile"]));
    XCTAssertEqualObjects(items[0].customProperties[@"headingIcon"], @"mdi:hvac");
    XCTAssertEqualObjects([items[0].customProperties[HAHeadingBadgesKey] valueForKey:@"entity"], (@[@"sensor.outdoor_temperature"]));
    XCTAssertNil(items[1].customProperties[HAHeadingBadgesKey], @"Only the item carrying the heading gets its badges");
    XCTAssertNil(items[2].customProperties[HAHeadingBadgesKey]);
    XCTAssertEqualObjects(items[2].customProperties[@"headingIcon"], @"mdi:robot-vacuum");
}

#pragma mark - View badges (GitHub #23)

- (NSArray *)mixedBadges {
    return @[
        @"sun.sun",                                                       // legacy string → show_name YES
        @{@"entity": @"sensor.a"},                                         // legacy dict → entity badge, show_name NO
        @{@"type": @"entity", @"entity": @"sensor.b", @"name": @"Bee",
          @"show_name": @YES, @"icon": @"mdi:bee", @"color": @"red",
          @"state_content": @"last_changed", @"tap_action": @{@"action": @"toggle"}},
        @{@"type": @"state-label", @"entity": @"sensor.c", @"name": @"dropped"},
        @{@"type": @"entity", @"entity": @"sensor.d", @"display_type": @"minimal"},
        @{@"type": @"entity", @"entity": @"sensor.e", @"display_type": @"complete",
          @"visibility": @[@{@"condition": @"state", @"entity": @"sun.sun", @"state": @"above_horizon"}]},
        @{@"type": @"custom:mushroom-chip", @"entity": @"sensor.x"},       // unknown type → skipped
        @{@"type": @"entity-filter", @"entities": @[@"sensor.y"]},         // unsupported → skipped
        @{@"type": @"entity"},                                             // no entity → skipped
        @42,                                                               // malformed → skipped
    ];
}

- (void)assertMixedBadgesSection:(HADashboardConfigSection *)badges {
    XCTAssertNotNil(badges);
    XCTAssertEqualObjects(badges.cardType, @"badges");
    XCTAssertEqualObjects(badges.entityIds, (@[@"sun.sun", @"sensor.a", @"sensor.b", @"sensor.c", @"sensor.d", @"sensor.e"]));
    NSArray<NSDictionary *> *configs = badges.customProperties[@"badgeConfigs"];
    XCTAssertEqual(configs.count, 6u);
    XCTAssertEqualObjects([configs valueForKey:@"type"], (@[@"entity", @"entity", @"entity", @"entity", @"entity", @"entity"]));
    XCTAssertEqualObjects([configs valueForKey:@"show_name"], (@[@YES, @NO, @YES, @YES, @NO, @YES]));
    XCTAssertEqualObjects([configs valueForKey:@"show_state"], (@[@YES, @YES, @YES, @YES, @NO, @YES]));
    XCTAssertEqualObjects([configs valueForKey:@"show_icon"], (@[@YES, @YES, @YES, @YES, @YES, @YES]));
    XCTAssertEqualObjects(configs[2][@"icon"], @"mdi:bee");
    XCTAssertEqualObjects(configs[2][@"color"], @"red");
    XCTAssertEqualObjects(configs[2][@"state_content"], @"last_changed");
    XCTAssertEqualObjects(configs[2][@"tap_action"], (@{@"action": @"toggle"}));
    XCTAssertNil(configs[3][@"name"], @"state-label badges ignore name, like HA's hui-state-label-badge");
    XCTAssertNil(configs[4][@"display_type"], @"display_type is migrated away");
    XCTAssertNotNil(configs[5][@"visibility"]);
    XCTAssertEqualObjects(badges.nameOverrides, (@{@"sensor.b": @"Bee"}));
}

- (void)testViewBadges_sectionsView_parsesLegacyAndCurrentFormats {
    NSDictionary *dict = @{@"views": @[@{@"title": @"S", @"badges": [self mixedBadges],
                                         @"sections": @[@{@"type": @"grid", @"cards": @[@{@"type": @"tile", @"entity": @"light.a"}]}]}]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    HALovelaceView *view = dashboard.views.firstObject;
    XCTAssertEqualObjects(view.viewType, @"sections");
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:view columns:3];
    [self assertMixedBadgesSection:config.viewBadges];
    XCTAssertEqual(config.sections.count, 1u, @"The badge row is not one of the sections/columns");
}

- (void)testViewBadges_masonryView_parsesLegacyAndCurrentFormats {
    NSDictionary *dict = @{@"views": @[@{@"title": @"M", @"badges": [self mixedBadges],
                                         @"cards": @[@{@"type": @"entities", @"entities": @[@"light.a"]}]}]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dict];
    HALovelaceView *view = dashboard.views.firstObject;
    XCTAssertEqualObjects(view.viewType, @"masonry");
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:view columns:3];
    [self assertMixedBadgesSection:config.viewBadges];
}

- (void)testViewBadges_absentOrPanel_isNil {
    NSDictionary *noBadges = @{@"views": @[@{@"title": @"M", @"cards": @[@{@"type": @"entities", @"entities": @[@"light.a"]}]}]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:noBadges];
    XCTAssertNil([HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3].viewBadges);

    NSDictionary *onlyUnsupported = @{@"views": @[@{@"title": @"M", @"badges": @[@{@"type": @"custom:x"}],
                                                @"cards": @[@{@"type": @"entities", @"entities": @[@"light.a"]}]}]};
    dashboard = [HALovelaceParser parseDashboardFromDictionary:onlyUnsupported];
    XCTAssertNil(dashboard.views.firstObject.rawBadges);
    XCTAssertNil([HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3].viewBadges);

    NSDictionary *panel = @{@"views": @[@{@"title": @"P", @"type": @"panel", @"badges": @[@"sun.sun"],
                                          @"cards": @[@{@"type": @"entities", @"entities": @[@"light.a"]}]}]};
    dashboard = [HALovelaceParser parseDashboardFromDictionary:panel];
    XCTAssertNil([HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3].viewBadges,
                 @"HA's panel view renders no badges");
}

/// Columnar layout: a leading full-width section spans the content width above the columns.
- (void)testColumnarLayout_fullWidthLeadingSection_spansAboveColumns {
    HAColumnarLayout *layout = [[HAColumnarLayout alloc] init];
    layout.contentInsets = UIEdgeInsetsMake(4, 8, 8, 8);
    HALayoutTestDataSource *ds = [[HALayoutTestDataSource alloc] init];
    ds.sectionCount = 3;
    ds.itemCounts = @[@1, @1, @1];
    ds.itemHeights = @[@44, @100, @100];
    ds.fullWidthCount = 1;
    layout.delegate = ds;

    (void)[self collectionViewWithLayout:layout dataSource:ds width:1024 height:768];

    CGRect badges = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]].frame;
    CGRect col1 = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:1]].frame;
    CGRect col2 = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:2]].frame;
    XCTAssertEqualWithAccuracy(CGRectGetMinX(badges), 8.0, 0.5);
    XCTAssertEqualWithAccuracy(CGRectGetWidth(badges), 1024.0 - 16.0, 0.5);
    XCTAssertEqualWithAccuracy(CGRectGetMinY(badges), 4.0, 0.5);
    XCTAssertGreaterThanOrEqual(CGRectGetMinY(col1), CGRectGetMaxY(badges), @"Columns start below the badge row");
    XCTAssertEqualWithAccuracy(CGRectGetMinY(col1), CGRectGetMinY(col2), 0.5, @"Remaining sections share one row");
    XCTAssertLessThan(CGRectGetMaxX(col1), CGRectGetMinX(col2), @"Remaining sections are side-by-side columns");
    XCTAssertEqualWithAccuracy(CGRectGetWidth(col1), (1024.0 - 16.0 - 6.0) / 2.0, 1.0,
                               @"The badge section must not take a column");
}

/// Masonry layout: a leading full-width item spans the viewport above the columns.
- (void)testMasonryLayout_fullWidthLeadingItem_spansAboveColumns {
    HAMasonryLayout *layout = [[HAMasonryLayout alloc] init];
    HALayoutTestDataSource *ds = [[HALayoutTestDataSource alloc] init];
    ds.sectionCount = 1;
    ds.itemCounts = @[@4];
    ds.cardTypes = @[@"badges", @"sensor", @"sensor", @"sensor"];
    ds.entityCounts = @[@0, @0, @0, @0];
    ds.itemHeights = @[@44, @100, @100, @100];
    ds.fullWidthCount = 1;
    layout.delegate = ds;

    (void)[self collectionViewWithLayout:layout dataSource:ds width:1024 height:768];

    CGRect badges = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]].frame;
    XCTAssertEqualWithAccuracy(CGRectGetMinX(badges), 8.0, 0.5);
    XCTAssertEqualWithAccuracy(CGRectGetWidth(badges), 1024.0 - 16.0, 0.5);
    NSMutableSet *xOrigins = [NSMutableSet set];
    for (NSInteger i = 1; i < 4; i++) {
        CGRect frame = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]].frame;
        XCTAssertGreaterThanOrEqual(CGRectGetMinY(frame), CGRectGetMaxY(badges));
        [xOrigins addObject:@(round(CGRectGetMinX(frame)))];
    }
    XCTAssertEqual(xOrigins.count, 3u, @"The 3 cards still fill 3 columns at 1024pt");
}

#pragma mark - Sections grid min/max sizing (GitHub #25)

/// The span the parser gives the single card in a one-card sections view.
- (HADashboardConfigItem *)sectionsItemForCard:(NSDictionary *)card {
    HADashboardConfig *config = [self sectionsConfigWithCards:@[card]];
    return config.items.firstObject;
}

/// The reporter's view (GitHub #25): sections view, max_columns 4, column spans 1/2/1.
- (HALovelaceView *)reporterSectionsView {
    NSDictionary *dict = @{@"views": @[@{
        @"title": @"Home", @"type": @"sections", @"max_columns": @4,
        @"sections": @[
            @{@"type": @"grid", @"column_span": @1, @"cards": @[
                @{@"type": @"tile", @"entity": @"person.psolyca", @"grid_options": @{@"columns": @4, @"rows": @1}},
                @{@"type": @"tile", @"entity": @"sensor.sun_next_rising", @"name": @" ",
                  @"icon": @"mdi:weather-sunset-up", @"time_format": @{@"type": @"time", @"style": @"long"}},
            ]},
            @{@"type": @"grid", @"column_span": @2, @"cards": @[
                @{@"type": @"vertical-stack", @"grid_options": @{@"columns": @33, @"rows": @"auto"}, @"cards": @[
                    @{@"type": @"clock", @"clock_style": @"digital", @"clock_size": @"large", @"show_seconds": @YES,
                      @"no_background": @YES, @"date_format": @[@"weekday-long", @"day-numeric", @"month-long"],
                      @"grid_options": @{@"columns": @9, @"rows": @2}},
                    @{@"type": @"weather-forecast", @"entity": @"weather.forecast_maison", @"show_current": @YES,
                      @"show_forecast": @NO, @"forecast_type": @"daily", @"forecast_slots": @1},
                    @{@"type": @"weather-forecast", @"entity": @"weather.cleguer", @"show_current": @NO,
                      @"show_forecast": @YES, @"forecast_type": @"daily", @"forecast_slots": @4},
                ]},
            ]},
            @{@"type": @"grid", @"column_span": @1, @"cards": @[
                @{@"type": @"tile", @"entity": @"sensor.sun_next_setting", @"name": @" ",
                  @"icon": @"mdi:weather-moonset-down", @"time_format": @{@"type": @"time", @"style": @"long"}},
                @{@"type": @"tile", @"entity": @"person.solene"},
            ]},
        ]}]};
    return [HALovelaceParser parseDashboardFromDictionary:dict].views.firstObject;
}

- (void)testSectionsGrid_tileBelowMinColumns_widensToSix {
    HADashboardConfigItem *item = [self sectionsItemForCard:@{@"type": @"tile", @"entity": @"person.a",
                                                              @"grid_options": @{@"columns": @4, @"rows": @1}}];
    XCTAssertEqual(item.columnSpan, 6, @"hui-tile-card min_columns is 6");
    XCTAssertEqual(item.rowSpan, 1);
}

- (void)testSectionsGrid_verticalTile_minColumnsIsThree {
    HADashboardConfigItem *item = [self sectionsItemForCard:@{@"type": @"tile", @"entity": @"light.a", @"vertical": @YES,
                                                              @"grid_options": @{@"columns": @2}}];
    XCTAssertEqual(item.columnSpan, 3);
    item = [self sectionsItemForCard:@{@"type": @"tile", @"entity": @"light.a", @"vertical": @YES,
                                       @"grid_options": @{@"columns": @4}}];
    XCTAssertEqual(item.columnSpan, 4, @"A vertical tile may be narrower than 6");
}

- (void)testSectionsGrid_tileWithInlineFeatures_minColumnsIsTwelve {
    HADashboardConfigItem *item = [self sectionsItemForCard:@{
        @"type": @"tile", @"entity": @"light.a", @"features_position": @"inline",
        @"features": @[@{@"type": @"light-brightness"}], @"grid_options": @{@"columns": @6}}];
    XCTAssertEqual(item.columnSpan, 12);
    // Features below the tile keep the usual minimum of 6.
    item = [self sectionsItemForCard:@{@"type": @"tile", @"entity": @"light.a",
                                       @"features": @[@{@"type": @"light-brightness"}], @"grid_options": @{@"columns": @6}}];
    XCTAssertEqual(item.columnSpan, 6);
}

- (void)testSectionsGrid_oversizedColumns_fillTheSection {
    HADashboardConfigItem *item = [self sectionsItemForCard:@{@"type": @"tile", @"entity": @"light.a", @"grid_options": @{@"columns": @33}}];
    XCTAssertEqual(item.columnSpan, 12);
    item = [self sectionsItemForCard:@{@"type": @"tile", @"entity": @"light.a", @"grid_options": @{@"columns": @"full"}}];
    XCTAssertEqual(item.columnSpan, 12);
    HADashboardConfig *config = [self sectionsConfigWithCards:@[
        @{@"type": @"vertical-stack", @"grid_options": @{@"columns": @33}, @"cards": @[
            @{@"type": @"tile", @"entity": @"light.a"}, @{@"type": @"sensor", @"entity": @"sensor.b"}]}]];
    XCTAssertEqualObjects([config.items valueForKey:@"columnSpan"], (@[@12, @12]));
}

- (void)testSectionsGrid_cardWithoutHAMinimum_keepsConfiguredColumns {
    HADashboardConfigItem *item = [self sectionsItemForCard:@{@"type": @"gauge", @"entity": @"sensor.a",
                                                              @"grid_options": @{@"columns": @4}}];
    XCTAssertEqual(item.columnSpan, 4, @"hui-gauge-card has no getGridOptions(), so no minimum");
    XCTAssertEqualObjects([HALovelaceParser haGridOptionsForCard:@{@"type": @"markdown"}], @{});
    XCTAssertEqualObjects([HALovelaceParser haGridOptionsForCard:@{@"type": @"custom:button-card"}], @{});
}

- (void)testSectionsGrid_maxColumnsAndRowsFromConfig_clamp {
    HADashboardConfigItem *item = [self sectionsItemForCard:@{@"type": @"gauge", @"entity": @"sensor.a",
        @"grid_options": @{@"columns": @9, @"max_columns": @6, @"rows": @1, @"min_rows": @3}}];
    XCTAssertEqual(item.columnSpan, 6);
    XCTAssertEqual(item.rowSpan, 3);
    // Config min_columns overrides the card's own minimum (hui-card merge order).
    item = [self sectionsItemForCard:@{@"type": @"tile", @"entity": @"light.a",
                                       @"grid_options": @{@"columns": @3, @"min_columns": @3}}];
    XCTAssertEqual(item.columnSpan, 3);
}

- (void)testSectionsGrid_explicitRowsClampToMinRows {
    // show_current + show_forecast → min_rows 3, min_columns 5
    HADashboardConfigItem *item = [self sectionsItemForCard:@{@"type": @"weather-forecast", @"entity": @"weather.home",
                                                              @"grid_options": @{@"columns": @3, @"rows": @1}}];
    XCTAssertEqual(item.columnSpan, 5);
    XCTAssertEqual(item.rowSpan, 3);
    item = [self sectionsItemForCard:@{@"type": @"tile", @"entity": @"light.a"}];
    XCTAssertEqual(item.rowSpan, 0, @"Unconfigured rows stay auto (content height)");
}

- (void)testSectionsGrid_legacyLayoutOptions_areMigratedTimesThree {
    HADashboardConfigItem *item = [self sectionsItemForCard:@{@"type": @"gauge", @"entity": @"sensor.a",
                                                              @"layout_options": @{@"grid_columns": @2, @"grid_rows": @2}}];
    XCTAssertEqual(item.columnSpan, 6, @"layout_options used HA's former 4-column grid");
    XCTAssertEqual(item.rowSpan, 2);
    item = [self sectionsItemForCard:@{@"type": @"tile", @"entity": @"light.a", @"layout_options": @{@"grid_columns": @1}}];
    XCTAssertEqual(item.columnSpan, 6, @"3 is below the tile minimum");
    item = [self sectionsItemForCard:@{@"type": @"gauge", @"entity": @"sensor.a",
                                       @"grid_options": @{@"columns": @4}, @"layout_options": @{@"grid_columns": @4}}];
    XCTAssertEqual(item.columnSpan, 4, @"grid_options wins over layout_options");
    NSDictionary *migrated = [HALovelaceParser configGridOptionsForCard:@{@"layout_options": @{
        @"grid_columns": @"full", @"grid_min_columns": @2, @"grid_max_rows": @3}}];
    XCTAssertEqualObjects(migrated, (@{@"columns": @"full", @"min_columns": @6, @"max_rows": @3}));
}

- (void)testSectionsGrid_childrenOfGridCards_followTheirParent {
    HADashboardConfig *config = [self sectionsConfigWithCards:@[
        @{@"type": @"grid", @"grid_options": @{@"columns": @3}, @"cards": @[
            @{@"type": @"tile", @"entity": @"vacuum.a", @"grid_options": @{@"columns": @2}}]}]];
    XCTAssertEqual(config.items.firstObject.columnSpan, 3, @"HA sizes a grid card's children by the grid, not their own minimum");
}

- (void)testMasonryView_doesNotClampGridOptions {
    NSDictionary *dict = @{@"views": @[@{@"title": @"Classic", @"cards": @[
        @{@"type": @"tile", @"entity": @"person.a", @"grid_options": @{@"columns": @4}}]}]};
    HALovelaceView *view = [HALovelaceParser parseDashboardFromDictionary:dict].views.firstObject;
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:view columns:3];
    XCTAssertEqual(config.items.firstObject.columnSpan, 4, @"Masonry views ignore grid sizing");
}

- (void)testSectionsGrid_haCardTable_matchesUpstream {
    NSDictionary *(^opts)(NSDictionary *) = ^NSDictionary *(NSDictionary *card) {
        return [HALovelaceParser haGridOptionsForCard:card];
    };
    XCTAssertEqualObjects(opts(@{@"type": @"button"}), (@{@"columns": @6, @"rows": @2, @"min_columns": @2, @"min_rows": @2}));
    XCTAssertEqualObjects(opts((@{@"type": @"button", @"show_name": @NO})), (@{@"columns": @3, @"rows": @1, @"min_columns": @2, @"min_rows": @1}));
    XCTAssertEqualObjects(opts(@{@"type": @"entity"}), (@{@"columns": @6, @"rows": @2, @"min_columns": @6, @"min_rows": @2}));
    XCTAssertEqualObjects(opts((@{@"type": @"thermostat", @"features": @[@{}, @{}]})),
                          (@{@"columns": @12, @"rows": @7, @"min_columns": @6, @"min_rows": @4}));
    XCTAssertEqualObjects(opts((@{@"type": @"weather-forecast", @"show_current": @NO, @"forecast_type": @"daily"})),
                          (@{@"columns": @12, @"rows": @3, @"min_columns": @4, @"min_rows": @2}));
    XCTAssertEqualObjects(opts((@{@"type": @"tile", @"features": @[@{}, @{}, @{}], @"features_position": @"inline"})),
                          (@{@"columns": @6, @"rows": @2, @"min_columns": @12, @"min_rows": @2}));
    XCTAssertEqualObjects(opts((@{@"type": @"area", @"vertical": @YES})),
                          (@{@"columns": @6, @"rows": @4, @"min_columns": @3, @"min_rows": @4}));
    XCTAssertEqualObjects(opts((@{@"type": @"logbook", @"title": @"Log"})),
                          (@{@"columns": @12, @"rows": @6, @"min_columns": @6, @"min_rows": @4}));
    XCTAssertEqualObjects(opts(@{@"type": @"map"}), (@{@"columns": @"full", @"rows": @4, @"min_columns": @6, @"min_rows": @2}));
}

/// GitHub #25: section 1's two tiles are both half width and fill the section;
/// the span-2 section's vertical stack (columns: 33) fills its section.
- (void)testSectionsGrid_reporterView_parsesLikeHA {
    HALovelaceView *view = [self reporterSectionsView];
    XCTAssertEqual(view.maxColumns, 4);
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:view columns:3];
    XCTAssertEqual(config.sections.count, 3u);

    NSArray<HADashboardConfigItem *> *first = config.sections[0].items;
    XCTAssertEqualObjects([first valueForKey:@"columnSpan"], (@[@6, @6]));
    XCTAssertEqual(first[0].columnSpan + first[1].columnSpan, 12, @"The two tiles fill section 1");

    NSArray<HADashboardConfigItem *> *middle = config.sections[1].items;
    XCTAssertEqualObjects([middle valueForKey:@"cardType"], (@[@"clock", @"weather-forecast", @"weather-forecast"]));
    XCTAssertEqual(config.sections[1].columnSpan, 2);
    XCTAssertEqualObjects([middle valueForKey:@"columnSpan"], (@[@24, @24, @24]),
                          @"columns: 33 clamps to the span-2 section's full 24-column grid");
    XCTAssertEqual(config.sections[0].columnSpan, 1);
    XCTAssertEqual(config.sections[2].columnSpan, 1);

    XCTAssertEqualObjects([config.sections[2].items valueForKey:@"columnSpan"], (@[@6, @6]));
}

/// Lays a parsed sections config out in HAColumnarLayout with the dashboard's
/// real geometry (HADashboardViewController -applyLayoutForSectionsView:).
- (HAColumnarLayout *)columnarLayoutForConfig:(HADashboardConfig *)config
                                   maxColumns:(NSInteger)maxColumns
                                        width:(CGFloat)width {
    NSMutableArray<NSNumber *> *counts = [NSMutableArray array];
    NSMutableArray<NSNumber *> *spans = [NSMutableArray array];
    NSMutableArray<NSNumber *> *sectionSpans = [NSMutableArray array];
    for (HADashboardConfigSection *section in config.sections) {
        [counts addObject:@(section.items.count)];
        [sectionSpans addObject:@(MAX(section.columnSpan, 1))];
        for (HADashboardConfigItem *item in section.items) [spans addObject:@(item.columnSpan)];
    }
    HAColumnarLayout *layout = [[HAColumnarLayout alloc] init];
    layout.contentInsets = UIEdgeInsetsMake(4, 8, 8, 8);
    layout.interColumnSpacing = 6;
    layout.interItemSpacing = 6;
    layout.maxColumns = maxColumns;
    HALayoutTestDataSource *ds = [[HALayoutTestDataSource alloc] init];
    ds.sectionCount = (NSInteger)config.sections.count;
    ds.itemCounts = counts;
    ds.itemGridColumns = spans;
    ds.sectionSpans = sectionSpans;
    layout.delegate = ds;
    UICollectionView *cv = [self collectionViewWithLayout:layout dataSource:ds width:width height:768];
    // The layout's delegate and collection view are weak: keep both alive for the test.
    [self.retainedLayoutObjects addObjectsFromArray:@[ds, cv]];
    return layout;
}

static CGRect HAItemFrame(HAColumnarLayout *layout, NSInteger section, NSInteger item) {
    return [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:section]].frame;
}

/// GitHub #25 at iPad landscape and portrait widths: four columns (the app's
/// 180pt minimum column width allows 4 down to ~754pt), so the 1/2/1 spans
/// fill one row as 1/4 + 1/2 + 1/4, and section 1's tiles fill their column.
- (void)testSectionsGrid_reporterView_columnarLayoutAt1024And768 {
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:[self reporterSectionsView] columns:3];
    for (NSNumber *widthValue in @[@1024, @768, @1366, @1180, @1133]) {
        CGFloat width = widthValue.doubleValue;
        HAColumnarLayout *layout = [self columnarLayoutForConfig:config maxColumns:4 width:width];
        CGFloat column = floor((width - 16.0 - 3 * 6.0) / 4.0);

        CGRect person = HAItemFrame(layout, 0, 0), sun = HAItemFrame(layout, 0, 1);
        CGRect clock = HAItemFrame(layout, 1, 0), forecast = HAItemFrame(layout, 1, 2);
        CGRect setting = HAItemFrame(layout, 2, 0), solene = HAItemFrame(layout, 2, 1);

        XCTAssertEqualWithAccuracy(CGRectGetMinX(person), 8.0, 0.5, @"%@", widthValue);
        XCTAssertEqualWithAccuracy(CGRectGetMinY(person), CGRectGetMinY(sun), 0.5, @"%@", widthValue);
        XCTAssertEqualWithAccuracy(CGRectGetWidth(person), CGRectGetWidth(sun), 0.5, @"%@", widthValue);
        XCTAssertEqualWithAccuracy(CGRectGetMaxX(sun), 8.0 + column, 1.0, @"Section 1 is one column wide at %@", widthValue);

        XCTAssertEqualWithAccuracy(CGRectGetMinX(clock), 8.0 + column + 6.0, 0.5, @"%@", widthValue);
        XCTAssertEqualWithAccuracy(CGRectGetWidth(clock), 2 * column + 6.0, 0.5, @"Section 2 spans two columns at %@", widthValue);
        XCTAssertEqualWithAccuracy(CGRectGetWidth(forecast), CGRectGetWidth(clock), 0.5);
        XCTAssertEqualWithAccuracy(CGRectGetMinY(clock), CGRectGetMinY(person), 0.5, @"One section row at %@", widthValue);

        XCTAssertEqualWithAccuracy(CGRectGetMinX(setting), 8.0 + 3 * (column + 6.0), 0.5, @"%@", widthValue);
        XCTAssertEqualWithAccuracy(CGRectGetMaxX(solene), 8.0 + 4 * column + 3 * 6.0, 1.0, @"Section 3 ends at the right edge at %@", widthValue);
        XCTAssertEqualWithAccuracy(CGRectGetMinY(setting), CGRectGetMinY(person), 0.5);
    }
}

/// Fewer columns than spans: HA clamps each span to the column count and
/// places sections in order, wrapping when the next one doesn't fit and
/// leaving the gap behind it empty (grid-auto-flow: row).
- (void)testColumnarLayout_spanClampsAndWrapsLikeHA {
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:[self reporterSectionsView] columns:3];

    // 600pt: 3 columns. [1][2 ] on the first row, [1] alone on the second.
    HAColumnarLayout *layout = [self columnarLayoutForConfig:config maxColumns:4 width:600];
    CGFloat column = floor((600 - 16.0 - 2 * 6.0) / 3.0);
    CGRect s1 = HAItemFrame(layout, 0, 0), s2 = HAItemFrame(layout, 1, 0), s3 = HAItemFrame(layout, 2, 0);
    XCTAssertEqualWithAccuracy(CGRectGetMinY(s1), CGRectGetMinY(s2), 0.5);
    XCTAssertEqualWithAccuracy(CGRectGetWidth(s2), 2 * column + 6.0, 0.5);
    XCTAssertGreaterThan(CGRectGetMinY(s3), CGRectGetMaxY(s2));
    XCTAssertEqualWithAccuracy(CGRectGetMinX(s3), 8.0, 0.5);

    // 450pt: 2 columns. Section 2 can't fit beside section 1 and takes the
    // whole next row; section 3 starts a third row.
    layout = [self columnarLayoutForConfig:config maxColumns:4 width:450];
    column = floor((450 - 16.0 - 6.0) / 2.0);
    s1 = HAItemFrame(layout, 0, 0); s2 = HAItemFrame(layout, 1, 0); s3 = HAItemFrame(layout, 2, 0);
    XCTAssertEqualWithAccuracy(CGRectGetMinX(s2), 8.0, 0.5);
    XCTAssertEqualWithAccuracy(CGRectGetWidth(s2), 2 * column + 6.0, 0.5);
    XCTAssertGreaterThan(CGRectGetMinY(s2), CGRectGetMaxY(s1));
    XCTAssertGreaterThan(CGRectGetMinY(s3), CGRectGetMaxY(s2));

    // One column (iPhone width): every span collapses to 1; the stack's 24
    // columns clamp to the column, section 1's tiles stay half width.
    layout = [self columnarLayoutForConfig:config maxColumns:4 width:320];
    s1 = HAItemFrame(layout, 0, 0); s2 = HAItemFrame(layout, 1, 0);
    XCTAssertEqualWithAccuracy(CGRectGetWidth(s2), 320 - 16.0, 0.5);
    XCTAssertEqualWithAccuracy(CGRectGetWidth(s1), floor((320 - 16.0) / 2.0 - 4.0), 0.5);

    // max_columns smaller than a span: the span is clamped, the section fills the row.
    NSDictionary *dict = @{@"views": @[@{@"type": @"sections", @"max_columns": @2, @"sections": @[
        @{@"type": @"grid", @"column_span": @3, @"cards": @[@{@"type": @"tile", @"entity": @"light.a"}]}]}]};
    HADashboardConfig *wide = [HALovelaceParser dashboardConfigFromView:
                               [HALovelaceParser parseDashboardFromDictionary:dict].views.firstObject columns:3];
    XCTAssertEqual(wide.sections.firstObject.columnSpan, 2, @"column_span never exceeds max_columns");
    layout = [self columnarLayoutForConfig:wide maxColumns:2 width:1024];
    XCTAssertEqualWithAccuracy(CGRectGetWidth(HAItemFrame(layout, 0, 0)),
                               floor((1024 - 16.0) / 4.0 - 4.0), 0.5, @"A default tile is 6 of the section's 24 columns");
}

- (HADashboardConfig *)spanTwoConfigWithCards:(NSArray *)cards {
    NSDictionary *dict = @{@"views": @[@{@"type": @"sections", @"max_columns": @4, @"sections": @[
        @{@"type": @"grid", @"column_span": @2, @"cards": cards},
        @{@"type": @"grid", @"cards": @[@{@"type": @"tile", @"entity": @"light.x"}]},
        @{@"type": @"grid", @"cards": @[@{@"type": @"tile", @"entity": @"light.y"}]}]}]};
    return [HALovelaceParser dashboardConfigFromView:
            [HALovelaceParser parseDashboardFromDictionary:dict].views.firstObject columns:3];
}

/// A column_span 2 section has a 24-column grid: default tiles sit four per row.
- (void)testColumnarLayout_spanTwoSection_fitsFourDefaultTilesPerRow {
    HADashboardConfig *config = [self spanTwoConfigWithCards:@[
        @{@"type": @"tile", @"entity": @"light.a"}, @{@"type": @"tile", @"entity": @"light.b"},
        @{@"type": @"tile", @"entity": @"light.c"}, @{@"type": @"tile", @"entity": @"light.d"}]];
    XCTAssertEqualObjects([config.sections[0].items valueForKey:@"columnSpan"], (@[@6, @6, @6, @6]));
    HAColumnarLayout *layout = [self columnarLayoutForConfig:config maxColumns:4 width:1024];
    CGFloat sectionWidth = 2 * floor((1024 - 16.0 - 18.0) / 4.0) + 6.0;
    for (NSInteger i = 0; i < 4; i++) {
        CGRect frame = HAItemFrame(layout, 0, i);
        XCTAssertEqualWithAccuracy(CGRectGetMinY(frame), CGRectGetMinY(HAItemFrame(layout, 0, 0)), 0.5, @"tile %ld", (long)i);
        XCTAssertEqualWithAccuracy(CGRectGetWidth(frame), floor(sectionWidth / 4.0 - 4.0), 0.5, @"tile %ld", (long)i);
    }
    XCTAssertEqualWithAccuracy(CGRectGetMaxX(HAItemFrame(layout, 0, 3)), 8.0 + sectionWidth, 1.0);
}

/// In a span-2 section "columns: 12" is one view column (half the section);
/// "full", oversized values, a map's default and a heading span all of it.
- (void)testColumnarLayout_spanTwoSection_fullVersusTwelve {
    HADashboardConfig *config = [self spanTwoConfigWithCards:@[
        @{@"type": @"gauge", @"entity": @"sensor.a", @"grid_options": @{@"columns": @12}},
        @{@"type": @"gauge", @"entity": @"sensor.b", @"grid_options": @{@"columns": @"full"}},
        @{@"type": @"gauge", @"entity": @"sensor.c", @"grid_options": @{@"columns": @40}},
        @{@"type": @"gauge", @"entity": @"sensor.d"},
        @{@"type": @"heading", @"heading": @"Later"},
        @{@"type": @"map", @"entities": @[@"person.a"]},
        @{@"type": @"vertical-stack", @"grid_options": @{@"columns": @"full"},
          @"cards": @[@{@"type": @"tile", @"entity": @"light.a"}]},
    ]];
    NSArray<HADashboardConfigItem *> *items = config.sections[0].items;
    XCTAssertEqualObjects([items valueForKey:@"cardType"],
                          (@[@"gauge", @"gauge", @"gauge", @"gauge", @"heading", @"map", @"tile"]));
    XCTAssertEqualObjects([items valueForKey:@"columnSpan"], (@[@12, @24, @24, @12, @24, @24, @24]));

    HAColumnarLayout *layout = [self columnarLayoutForConfig:config maxColumns:4 width:1024];
    CGFloat sectionWidth = 2 * floor((1024 - 16.0 - 18.0) / 4.0) + 6.0;
    XCTAssertEqualWithAccuracy(CGRectGetWidth(HAItemFrame(layout, 0, 0)), floor(sectionWidth / 2.0 - 4.0), 0.5);
    XCTAssertEqualWithAccuracy(CGRectGetWidth(HAItemFrame(layout, 0, 1)), sectionWidth, 0.5);
    XCTAssertEqualWithAccuracy(CGRectGetWidth(HAItemFrame(layout, 0, 6)), sectionWidth, 0.5);

    // In a span-1 section "full" and 12 are the same thing.
    HADashboardConfig *single = [self sectionsConfigWithCards:@[
        @{@"type": @"gauge", @"entity": @"sensor.b", @"grid_options": @{@"columns": @"full"}},
        @{@"type": @"heading", @"heading": @"Later"}]];
    XCTAssertEqualObjects([single.sections[0].items valueForKey:@"columnSpan"], (@[@12, @12]));
}

/// Sections views use each card type's own HA default width.
- (void)testSectionsGrid_haDefaultColumns {
    XCTAssertEqual(([self sectionsItemForCard:@{@"type": @"entity", @"entity": @"sensor.a"}].columnSpan), 6);
    XCTAssertEqual(([self sectionsItemForCard:@{@"type": @"statistic", @"entity": @"sensor.a"}].columnSpan), 6);
    XCTAssertEqual(([self sectionsItemForCard:@{@"type": @"area", @"area": @"kitchen"}].columnSpan), 6);
    XCTAssertEqual(([self sectionsItemForCard:(@{@"type": @"button", @"entity": @"light.a", @"show_name": @NO})].columnSpan), 3);
    XCTAssertEqual(([self sectionsItemForCard:@{@"type": @"button", @"entity": @"light.a"}].columnSpan), 6);
    XCTAssertEqual(([self sectionsItemForCard:@{@"type": @"tile", @"entity": @"light.a"}].columnSpan), 6);
    XCTAssertEqual(([self sectionsItemForCard:@{@"type": @"gauge", @"entity": @"sensor.a"}].columnSpan), 12);
    // Masonry views keep their own defaults.
    NSDictionary *dict = @{@"views": @[@{@"title": @"Classic", @"cards": @[@{@"type": @"entity", @"entity": @"sensor.a"}]}]};
    HADashboardConfig *classic = [HALovelaceParser dashboardConfigFromView:
                                  [HALovelaceParser parseDashboardFromDictionary:dict].views.firstObject columns:3];
    XCTAssertEqual(classic.items.firstObject.columnSpan, 12);
}

@end
