#import <XCTest/XCTest.h>
#import "HALovelaceParser.h"
#import "HADashboardConfig.h"
#import "HAEntityCellFactory.h"
#import "HAClockCardCell.h"
#import "HAClockCardFormatter.h"

/// Unit coverage for the built-in HA `clock` card (GitHub #21): parser
/// recognition and grid sizing, the clock-date-format.ts port, 12/24-hour and
/// time-zone resolution, the cell's rendered text, and its tick timer
/// lifecycle (no leaks, no retain cycle).
@interface HAClockCardTests : XCTestCase
@end

@implementation HAClockCardTests

#pragma mark - Helpers

static NSDictionary *HAReporterClockCard(void) {
    return @{
        @"type": @"clock",
        @"clock_style": @"digital",
        @"clock_size": @"large",
        @"show_seconds": @YES,
        @"no_background": @YES,
        @"date_format": @[@"weekday-long", @"day-numeric", @"month-long"],
        @"face_style": @"markers",
    };
}

/// Sunday 11 October 2026, 20:06:47 in Europe/Paris.
static NSDate *HAFixedClockDate(void) {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"Europe/Paris"];
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = 2026; c.month = 10; c.day = 11; c.hour = 20; c.minute = 6; c.second = 47;
    return [calendar dateFromComponents:c];
}

- (HADashboardConfig *)sectionsConfigForCards:(NSArray *)cards {
    NSDictionary *dash = @{@"views": @[@{@"title": @"Test", @"type": @"sections",
                                          @"sections": @[@{@"cards": cards}]}]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dash];
    return [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3];
}

- (HADashboardConfig *)classicConfigForCards:(NSArray *)cards {
    NSDictionary *dash = @{@"views": @[@{@"title": @"Test", @"cards": cards}]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dash];
    return [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3];
}

- (HADashboardConfigItem *)firstItemOfType:(NSString *)type in:(HADashboardConfig *)config {
    for (HADashboardConfigItem *item in config.items) {
        if ([item.cardType isEqualToString:type]) return item;
    }
    return nil;
}

- (HAClockCardCell *)configuredCellForCard:(NSDictionary *)card language:(NSString *)language {
    NSMutableDictionary *withZone = [card mutableCopy];
    withZone[@"time_zone"] = @"Europe/Paris";
    HADashboardConfigItem *item = [self firstItemOfType:@"clock" in:[self sectionsConfigForCards:@[withZone]]];
    HAClockCardCell *cell = [[HAClockCardCell alloc] initWithFrame:CGRectMake(0, 0, 320, 120)];
    cell.fixedDate = HAFixedClockDate();
    cell.languageCodeOverride = language;
    [cell configureWithEntity:nil configItem:item];
    return cell;
}

#pragma mark - Parser

- (void)testParser_reporterConfig_isSupportedClockItem {
    HADashboardConfig *config = [self sectionsConfigForCards:@[HAReporterClockCard()]];
    XCTAssertEqual(config.items.count, 1u);
    HADashboardConfigItem *item = config.items.firstObject;
    XCTAssertEqualObjects(item.cardType, @"clock", @"type: clock must not fall through to the unsupported placeholder");
    XCTAssertNil(item.entityId);
    XCTAssertNil(item.fallbackCardType);
    NSDictionary *props = item.customProperties;
    XCTAssertEqualObjects(props[@"clock_style"], @"digital");
    XCTAssertEqualObjects(props[@"clock_size"], @"large");
    XCTAssertEqualObjects(props[@"show_seconds"], @YES);
    XCTAssertEqualObjects(props[@"no_background"], @YES);
    XCTAssertEqualObjects(props[@"face_style"], @"markers");
    NSArray *expectedParts = @[@"weekday-long", @"day-numeric", @"month-long"];
    XCTAssertEqualObjects(props[@"date_format"], expectedParts);
    XCTAssertEqualObjects([HAEntityCellFactory reuseIdentifierForEntity:nil cardType:item.cardType], @"HAClockCardCell");
}

- (void)testParser_carriesAnalogOptionsAndTitle {
    HADashboardConfig *config = [self sectionsConfigForCards:@[@{
        @"type": @"clock", @"clock_style": @"analog", @"title": @"Paris",
        @"border": @YES, @"ticks": @"minute", @"face_style": @"roman",
        @"seconds_motion": @"tick", @"time_format": @"12", @"time_zone": @"Europe/Paris",
    }]];
    NSDictionary *props = [self firstItemOfType:@"clock" in:config].customProperties;
    XCTAssertEqualObjects(props[@"clock_title"], @"Paris");
    XCTAssertEqualObjects(props[@"border"], @YES);
    XCTAssertEqualObjects(props[@"ticks"], @"minute");
    XCTAssertEqualObjects(props[@"face_style"], @"roman");
    XCTAssertEqualObjects(props[@"seconds_motion"], @"tick");
    XCTAssertEqualObjects(props[@"time_format"], @"12");
    XCTAssertEqualObjects(props[@"time_zone"], @"Europe/Paris");
    XCTAssertNil(props[@"headingIcon"], @"The clock's own title is rendered inside the card, not as a grid heading");
}

- (void)testParser_sectionsGridOptions_matchHA {
    // getGridOptions(): digital large → columns 6, rows 2.
    HADashboardConfigItem *digital = [self firstItemOfType:@"clock" in:[self sectionsConfigForCards:@[HAReporterClockCard()]]];
    XCTAssertEqual(digital.columnSpan, 6);
    XCTAssertEqual(digital.rowSpan, 2);

    // analog small with a title → min_rows 3 beats rows 2.
    HADashboardConfigItem *analog = [self firstItemOfType:@"clock" in:[self sectionsConfigForCards:@[
        @{@"type": @"clock", @"clock_style": @"analog", @"title": @"Hall"}]]];
    XCTAssertEqual(analog.rowSpan, 3);

    // Explicit rows clamp to max_rows 4 (digital) and min_columns 6 (large).
    HADashboardConfigItem *clamped = [self firstItemOfType:@"clock" in:[self sectionsConfigForCards:@[
        @{@"type": @"clock", @"clock_size": @"large", @"grid_options": @{@"rows": @9, @"columns": @3}}]]];
    XCTAssertEqual(clamped.rowSpan, 4);
    XCTAssertEqual(clamped.columnSpan, 6);
}

- (void)testParser_classicView_sizesToContent {
    HADashboardConfigItem *item = [self firstItemOfType:@"clock" in:[self classicConfigForCards:@[HAReporterClockCard()]]];
    XCTAssertNotNil(item);
    XCTAssertEqual(item.rowSpan, 0, @"Masonry views size the clock to its content");
    XCTAssertEqual(item.columnSpan, 12);
}

- (void)testParser_clockWeatherCustomCard_isNotRoutedToClock {
    HADashboardConfig *config = [self sectionsConfigForCards:@[@{
        @"type": @"custom:clock-weather-card", @"entity": @"weather.home"}]];
    HADashboardConfigItem *item = config.items.firstObject;
    XCTAssertEqualObjects(item.cardType, @"custom:clock-weather-card");
    XCTAssertEqualObjects([HAEntityCellFactory reuseIdentifierForEntity:nil cardType:item.cardType], @"HAClockWeatherCell");
    XCTAssertNil([self firstItemOfType:@"clock" in:config]);
}

- (void)testParser_clockUnderGridHeading_usesHeadingIconMechanism {
    HADashboardConfig *config = [self sectionsConfigForCards:@[@{
        @"type": @"grid",
        @"grid_options": @{@"columns": @6},
        @"cards": @[
            @{@"type": @"heading", @"heading": @"Time", @"icon": @"mdi:clock-outline"},
            @{@"type": @"clock"},
        ],
    }]];
    HADashboardConfigItem *item = [self firstItemOfType:@"clock" in:config];
    XCTAssertEqualObjects(item.displayName, @"Time");
    XCTAssertEqualObjects(item.customProperties[@"headingIcon"], @"mdi:clock-outline");
}

- (void)testParser_malformedValues_areDropped {
    HADashboardConfigItem *item = [self firstItemOfType:@"clock" in:[self sectionsConfigForCards:@[@{
        @"type": @"clock", @"clock_size": @7, @"date_format": @"weekday-long",
        @"show_seconds": @"yes", @"title": @[@"x"],
    }]]];
    XCTAssertNotNil(item);
    XCTAssertNil(item.customProperties[@"clock_size"]);
    XCTAssertNil(item.customProperties[@"date_format"]);
    XCTAssertNil(item.customProperties[@"show_seconds"]);
    XCTAssertNil(item.customProperties[@"clock_title"]);
}

#pragma mark - Date parts (clock-date-format.ts)

- (void)testDateParts_reporterConfig_french {
    NSString *s = [HAClockCardFormatter dateStringForDate:HAFixedClockDate()
                                                   parts:@[@"weekday-long", @"day-numeric", @"month-long"]
                                                  locale:[HAClockCardFormatter localeForLanguageCode:@"fr"]
                                                timeZone:[NSTimeZone timeZoneWithName:@"Europe/Paris"]];
    XCTAssertEqualObjects(s, @"dimanche 11 octobre");
}

- (void)testDateParts_reporterConfig_english {
    NSString *s = [HAClockCardFormatter dateStringForDate:HAFixedClockDate()
                                                   parts:@[@"weekday-long", @"day-numeric", @"month-long"]
                                                  locale:[HAClockCardFormatter localeForLanguageCode:@"en"]
                                                timeZone:[NSTimeZone timeZoneWithName:@"Europe/Paris"]];
    XCTAssertEqualObjects(s, @"Sunday 11 October");
}

- (void)testDateParts_separatorsAreLiteralAndOnlyValuesGetSpaces {
    NSLocale *en = [HAClockCardFormatter localeForLanguageCode:@"en"];
    NSTimeZone *paris = [NSTimeZone timeZoneWithName:@"Europe/Paris"];
    NSDate *date = HAFixedClockDate();
    XCTAssertEqualObjects(([HAClockCardFormatter dateStringForDate:date
        parts:@[@"day-2-digit", @"separator-slash", @"month-2-digit", @"separator-slash", @"year-numeric"]
        locale:en timeZone:paris]), @"11/10/2026");
    XCTAssertEqualObjects(([HAClockCardFormatter dateStringForDate:date
        parts:@[@"weekday-short", @"separator-dash", @"day-numeric", @"month-short", @"separator-dot", @"year-2-digit"]
        locale:en timeZone:paris]), @"Sun-11 Oct.26");
    XCTAssertEqualObjects(([HAClockCardFormatter dateStringForDate:date
        parts:@[@"weekday-long", @"separator-new-line", @"day-numeric", @"month-numeric"]
        locale:en timeZone:paris]), @"Sunday\n11 10");
}

- (void)testDateParts_french_shortForms {
    XCTAssertEqualObjects(([HAClockCardFormatter dateStringForDate:HAFixedClockDate()
        parts:@[@"weekday-short", @"day-2-digit", @"month-short", @"year-numeric"]
        locale:[HAClockCardFormatter localeForLanguageCode:@"fr"]
        timeZone:[NSTimeZone timeZoneWithName:@"Europe/Paris"]]), @"dim. 11 oct. 2026");
}

- (void)testDateParts_timeZoneDecidesTheDay {
    // 20:06 in Paris is already Monday 12 October in Tokyo.
    XCTAssertEqualObjects(([HAClockCardFormatter dateStringForDate:HAFixedClockDate()
        parts:@[@"weekday-long", @"day-numeric"]
        locale:[HAClockCardFormatter localeForLanguageCode:@"en"]
        timeZone:[NSTimeZone timeZoneWithName:@"Asia/Tokyo"]]), @"Monday 12");
}

- (void)testDateParts_normalization {
    NSArray *expected = @[@"weekday-long", @"separator-dot"];
    XCTAssertEqualObjects([HAClockCardFormatter normalizedDateParts:(@[@"weekday-long", @"bogus", @3, @"separator-dot"])], expected);
    XCTAssertEqualObjects([HAClockCardFormatter normalizedDateParts:@"weekday-long"], @[]);
    XCTAssertEqualObjects([HAClockCardFormatter normalizedDateParts:nil], @[]);
    XCTAssertEqualObjects(([HAClockCardFormatter dateStringForDate:HAFixedClockDate() parts:@[]
        locale:[HAClockCardFormatter localeForLanguageCode:@"en"] timeZone:[NSTimeZone localTimeZone]]), @"");
}

#pragma mark - Time format / time zone

- (void)testTimeFormat_useAmPm {
    NSLocale *en = [HAClockCardFormatter localeForLanguageCode:@"en"];
    NSLocale *fr = [HAClockCardFormatter localeForLanguageCode:@"fr"];
    XCTAssertTrue([HAClockCardFormatter usesTwelveHourClockForTimeFormat:@"12" languageLocale:fr]);
    XCTAssertTrue([HAClockCardFormatter usesTwelveHourClockForTimeFormat:@12 languageLocale:fr]);
    XCTAssertFalse([HAClockCardFormatter usesTwelveHourClockForTimeFormat:@"24" languageLocale:en]);
    XCTAssertFalse([HAClockCardFormatter usesTwelveHourClockForTimeFormat:@24 languageLocale:en]);
    XCTAssertTrue([HAClockCardFormatter usesTwelveHourClockForTimeFormat:@"language" languageLocale:en]);
    XCTAssertFalse([HAClockCardFormatter usesTwelveHourClockForTimeFormat:@"language" languageLocale:fr]);
    XCTAssertTrue([HAClockCardFormatter usesTwelveHourClockForTimeFormat:nil languageLocale:en], @"Unset follows the language, HA's profile default");
    XCTAssertFalse([HAClockCardFormatter usesTwelveHourClockForTimeFormat:nil languageLocale:fr]);
}

- (void)testTimeZoneResolution {
    XCTAssertEqualObjects([HAClockCardFormatter timeZoneForConfigValue:@"America/New_York"].name, @"America/New_York");
    NSString *local = [NSTimeZone localTimeZone].name;
    XCTAssertEqualObjects([HAClockCardFormatter timeZoneForConfigValue:nil].name, local);
    XCTAssertEqualObjects([HAClockCardFormatter timeZoneForConfigValue:@"server"].name, local);
    XCTAssertEqualObjects([HAClockCardFormatter timeZoneForConfigValue:@"Not/AZone"].name, local);
    XCTAssertEqualObjects([HAClockCardFormatter timeZoneForConfigValue:@42].name, local);
}

#pragma mark - Cell text

- (void)testCell_reporterConfig_french {
    HAClockCardCell *cell = [self configuredCellForCard:HAReporterClockCard() language:@"fr"];
    XCTAssertEqualObjects(cell.renderedTimeText, @"20:06");
    XCTAssertEqualObjects(cell.renderedSecondsText, @"47");
    XCTAssertNil(cell.renderedAmPmText);
    XCTAssertEqualObjects(cell.renderedDateText, @"dimanche 11 octobre");
    XCTAssertEqualObjects(cell.accessibilityLabel, @"20:06, dimanche 11 octobre");
    XCTAssertEqual(cell.contentView.layer.cornerRadius, 0, @"no_background drops the card surface");
}

- (void)testCell_reporterConfig_english_isTwelveHour {
    HAClockCardCell *cell = [self configuredCellForCard:HAReporterClockCard() language:@"en"];
    XCTAssertEqualObjects(cell.renderedTimeText, @"8:06");
    XCTAssertEqualObjects(cell.renderedSecondsText, @"47");
    XCTAssertEqualObjects(cell.renderedAmPmText, @"PM");
    XCTAssertEqualObjects(cell.renderedDateText, @"Sunday 11 October");
}

- (void)testCell_timeFormat24_overridesEnglish_andHidesSecondsWhenOff {
    HAClockCardCell *cell = [self configuredCellForCard:@{@"type": @"clock", @"time_format": @"24"} language:@"en"];
    XCTAssertEqualObjects(cell.renderedTimeText, @"20:06");
    XCTAssertNil(cell.renderedSecondsText);
    XCTAssertNil(cell.renderedAmPmText);
    XCTAssertNil(cell.renderedDateText);
}

#pragma mark - Narrow widths

- (HAClockCardCell *)laidOutCellForCard:(NSDictionary *)card language:(NSString *)language width:(CGFloat)width {
    HAClockCardCell *cell = [self configuredCellForCard:card language:language];
    cell.frame = CGRectMake(0, 0, width, 120);
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
    return cell;
}

/// YES if every visible label in `view`'s subtree shows its full text.
- (void)assertNoTruncatedTimeIn:(HAClockCardCell *)cell {
    for (UIView *row in cell.contentView.subviews) {
        NSMutableArray *stack = [NSMutableArray arrayWithObject:row];
        while (stack.count) {
            UIView *v = stack.lastObject; [stack removeLastObject];
            [stack addObjectsFromArray:v.subviews];
            if (![v isKindOfClass:[UILabel class]] || v.hidden) continue;
            UILabel *label = (UILabel *)v;
            if (label.numberOfLines != 1 || label.adjustsFontSizeToFitWidth || label.text.length == 0) continue;
            CGFloat needed = [label sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width;
            XCTAssertLessThanOrEqual(needed, ceil(label.bounds.size.width) + 0.5, @"'%@' is truncated", label.text);
        }
    }
}

- (void)testNarrow_digitalLarge12h_scalesTimeGroupUniformly {
    HAClockCardCell *cell = [self laidOutCellForCard:@{
        @"type": @"clock", @"clock_size": @"large", @"show_seconds": @YES, @"time_format": @"12",
        @"date_format": @[@"weekday-long", @"day-numeric", @"month-long"],
    } language:@"en" width:115];
    XCTAssertLessThan(cell.timeScale, 1.0);
    XCTAssertGreaterThanOrEqual(cell.timeScale, 0.4);
    [self assertNoTruncatedTimeIn:cell];
}

- (void)testReporterLayout_rendersAtFullSizeWhenItFits {
    // GitHub #21 config: 24h "20:06" + "47" at HA's full large size is ~216pt
    // wide in SF; with 16pt padding each side it fits a 260pt cell unscaled.
    HAClockCardCell *cell = [self laidOutCellForCard:HAReporterClockCard() language:@"fr" width:260];
    XCTAssertEqual(cell.timeScale, 1.0, @"Fits at HA's full size, so no scaling");
    [self assertNoTruncatedTimeIn:cell];
}

- (void)testReporterLayout_210pt_shrinksSlightlyWithoutTruncation {
    // A ~210pt cell leaves 178pt: too narrow for the full-size group, so it
    // scales uniformly (just under 0.85) instead of truncating.
    HAClockCardCell *cell = [self laidOutCellForCard:HAReporterClockCard() language:@"fr" width:210];
    XCTAssertLessThan(cell.timeScale, 1.0);
    XCTAssertGreaterThan(cell.timeScale, 0.75);
    [self assertNoTruncatedTimeIn:cell];
}

- (void)testNarrow_scaleRecoversWhenWidened {
    HAClockCardCell *cell = [self laidOutCellForCard:HAReporterClockCard() language:@"en" width:115];
    XCTAssertLessThan(cell.timeScale, 1.0);
    cell.frame = CGRectMake(0, 0, 320, 120);
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
    XCTAssertEqual(cell.timeScale, 1.0);
}

- (void)testPreferredHeight {
    HADashboardConfigItem *analogMedium = [[HADashboardConfigItem alloc] init];
    analogMedium.customProperties = @{@"clock_style": @"analog", @"clock_size": @"medium"};
    XCTAssertEqual([HAClockCardCell preferredHeightForConfigItem:analogMedium width:320], 192.0, @"16pt padding x2 + 160pt dial");

    HADashboardConfigItem *digitalSmall = [[HADashboardConfigItem alloc] init];
    digitalSmall.customProperties = @{};
    CGFloat small = [HAClockCardCell preferredHeightForConfigItem:digitalSmall width:320];
    XCTAssertLessThanOrEqual(small, 56.0, @"Default digital clock fits HA's single 56pt grid row");
}

#pragma mark - Timer lifecycle

- (void)testTicking_followsWindowAndDisplayState {
    HADashboardConfigItem *item = [self firstItemOfType:@"clock" in:[self sectionsConfigForCards:@[HAReporterClockCard()]]];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 400, 400)];
    HAClockCardCell *cell = [[HAClockCardCell alloc] initWithFrame:CGRectMake(0, 0, 320, 120)];
    [cell configureWithEntity:nil configItem:item];
    XCTAssertFalse(cell.isTicking, @"No timer while the cell is not in a window");

    [window addSubview:cell];
    XCTAssertTrue(cell.isTicking);

    [cell endTicking];
    XCTAssertFalse(cell.isTicking, @"didEndDisplayingCell stops the timer");
    [cell beginTicking];
    XCTAssertTrue(cell.isTicking);

    [cell prepareForReuse];
    XCTAssertFalse(cell.isTicking, @"Reuse always tears the timer down");
    [cell beginTicking];
    XCTAssertFalse(cell.isTicking, @"An unconfigured (reused) cell never ticks");

    [cell configureWithEntity:nil configItem:item];
    XCTAssertTrue(cell.isTicking);
    [cell removeFromSuperview];
    XCTAssertFalse(cell.isTicking, @"Leaving the window stops the timer");
}

- (void)testTicking_fixedDateNeverSchedulesTimer {
    HAClockCardCell *cell = [self configuredCellForCard:HAReporterClockCard() language:@"fr"];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 400, 400)];
    [window addSubview:cell];
    XCTAssertFalse(cell.isTicking);
    [cell removeFromSuperview];
}

- (void)testTicking_timerDoesNotRetainCell {
    HADashboardConfigItem *item = [self firstItemOfType:@"clock" in:[self sectionsConfigForCards:@[HAReporterClockCard()]]];
    __weak HAClockCardCell *weakCell = nil;
    __weak UIWindow *weakWindow = nil;
    @autoreleasepool {
        UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 400, 400)];
        HAClockCardCell *cell = [[HAClockCardCell alloc] initWithFrame:CGRectMake(0, 0, 320, 120)];
        [cell configureWithEntity:nil configItem:item];
        [window addSubview:cell];
        XCTAssertTrue(cell.isTicking);
        weakCell = cell;
        weakWindow = window;
        // Drop every reference while the timer is still armed: only a
        // timer → cell retain could keep the cell alive now.
    }
    XCTAssertNil(weakWindow);
    XCTAssertNil(weakCell, @"Cell leaked: the armed tick timer must not retain it");
}

- (void)testTicking_advancesToNextSecond {
    HADashboardConfigItem *item = [self firstItemOfType:@"clock" in:[self sectionsConfigForCards:@[HAReporterClockCard()]]];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 400, 400)];
    HAClockCardCell *cell = [[HAClockCardCell alloc] initWithFrame:CGRectMake(0, 0, 320, 120)];
    [cell configureWithEntity:nil configItem:item];
    [window addSubview:cell];
    NSString *first = cell.renderedSecondsText;
    XCTAssertNotNil(first);

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.5];
    while ([cell.renderedSecondsText isEqualToString:first] && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    XCTAssertNotEqualObjects(cell.renderedSecondsText, first, @"The tick timer should update the seconds within ~1s");
    XCTAssertTrue(cell.isTicking, @"Each tick re-arms the timer");
    [cell removeFromSuperview];
}

@end
