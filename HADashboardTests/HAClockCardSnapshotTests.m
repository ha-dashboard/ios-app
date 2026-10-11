#import "HABaseSnapshotTestCase.h"
#import "HALovelaceParser.h"
#import "HADashboardConfig.h"
#import "HABaseEntityCell.h"
#import "HAClockCardCell.h"

/// Snapshot coverage for the built-in HA `clock` card (GitHub #21), digital
/// and analog. Every cell renders a fixed instant (Sunday 11 October 2026,
/// 20:06:47) in a fixed zone (Europe/Paris) and an explicit language, and the
/// cell's own timer is disabled by the fixedDate hook, so references are
/// deterministic. Cards go through the real parser in a sections view so the
/// rendered height includes HA's getGridOptions() rows like the dashboard.
@interface HAClockCardSnapshotTests : HABaseSnapshotTestCase
@end

@implementation HAClockCardSnapshotTests

static NSDate *HASnapshotClockDate(void) {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"Europe/Paris"];
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = 2026; c.month = 10; c.day = 11; c.hour = 20; c.minute = 6; c.second = 47;
    return [calendar dateFromComponents:c];
}

/// The reporter's card from GitHub #21.
static NSDictionary *HAReporterCard(void) {
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

- (UIView *)clockCellForCard:(NSDictionary *)card language:(NSString *)language {
    return [self clockCellForCards:@[card] language:language width:kColumnWidth];
}

- (UIView *)clockCellForCard:(NSDictionary *)card language:(NSString *)language width:(CGFloat)width {
    return [self clockCellForCards:@[card] language:language width:width];
}

- (UIView *)clockCellForCards:(NSArray *)cards language:(NSString *)language width:(CGFloat)width {
    NSMutableArray *zoned = [NSMutableArray array];
    for (NSDictionary *card in cards) {
        NSMutableDictionary *c = [card mutableCopy];
        if ([c[@"type"] isEqual:@"clock"] && !c[@"time_zone"]) c[@"time_zone"] = @"Europe/Paris";
        if ([c[@"type"] isEqual:@"grid"]) {
            NSMutableArray *children = [NSMutableArray array];
            for (NSDictionary *child in c[@"cards"]) {
                NSMutableDictionary *m = [child mutableCopy];
                if ([m[@"type"] isEqual:@"clock"]) m[@"time_zone"] = @"Europe/Paris";
                [children addObject:m];
            }
            c[@"cards"] = children;
        }
        [zoned addObject:c];
    }
    NSDictionary *dash = @{@"views": @[@{@"title": @"Clock", @"type": @"sections",
                                          @"sections": @[@{@"cards": zoned}]}]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dash];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3];
    HADashboardConfigItem *item = nil;
    for (HADashboardConfigItem *candidate in config.items) {
        if ([candidate.cardType isEqualToString:@"clock"]) { item = candidate; break; }
    }
    XCTAssertNotNil(item);

    // Same height rule as HADashboardViewController -heightForItemAtIndexPath:.
    BOOL hasHeading = item.customProperties[@"headingIcon"] != nil && item.displayName.length > 0;
    CGFloat headingExtra = hasHeading ? [HABaseEntityCell headingHeight] : 0;
    CGFloat height = [HAClockCardCell preferredHeightForConfigItem:item width:width] + headingExtra;
    if (item.rowSpan > 0) {
        height = MAX(height, item.rowSpan * 56.0 + (item.rowSpan - 1) * 6.0 + headingExtra);
    }

    HAClockCardCell *cell = [[HAClockCardCell alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    cell.fixedDate = HASnapshotClockDate();
    cell.languageCodeOverride = language;
    [cell configureWithEntity:nil configItem:item];
    [cell layoutIfNeeded];
    return cell;
}

#pragma mark - Digital

- (void)testDigitalReporterConfig_fr {
    [self verifyView:[self clockCellForCard:HAReporterCard() language:@"fr"] identifier:nil];
}

- (void)testDigitalReporterConfig_en {
    [self verifyView:[self clockCellForCard:HAReporterCard() language:@"en"] identifier:nil];
}

- (void)testDigitalSmallDefault {
    [self verifyView:[self clockCellForCard:@{@"type": @"clock"} language:@"fr"] identifier:nil];
}

- (void)testDigitalSmallSecondsAndDate {
    [self verifyView:[self clockCellForCard:@{
        @"type": @"clock", @"clock_size": @"small", @"show_seconds": @YES,
        @"date_format": @[@"day-2-digit", @"separator-slash", @"month-2-digit", @"separator-slash", @"year-numeric"],
    } language:@"fr"] identifier:nil];
}

- (void)testDigitalSmallTwelveHourWithSeconds {
    [self verifyView:[self clockCellForCard:@{
        @"type": @"clock", @"show_seconds": @YES, @"time_format": @"12",
    } language:@"en"] identifier:nil];
}

- (void)testDigitalMediumTitleTwoLineDate {
    [self verifyView:[self clockCellForCard:@{
        @"type": @"clock", @"clock_size": @"medium", @"title": @"Cuisine", @"time_format": @"24",
        @"date_format": @[@"weekday-long", @"separator-new-line", @"day-numeric", @"month-long", @"year-numeric"],
    } language:@"fr"] identifier:nil];
}

- (void)testDigitalLargeWithBackgroundNoSeconds {
    [self verifyView:[self clockCellForCard:@{
        @"type": @"clock", @"clock_size": @"large",
        @"date_format": @[@"weekday-short", @"day-numeric", @"month-short"],
    } language:@"en"] identifier:nil];
}

- (void)testDigitalUnderGridHeading {
    [self verifyView:[self clockCellForCard:@{
        @"type": @"grid", @"grid_options": @{@"columns": @12},
        @"cards": @[
            @{@"type": @"heading", @"heading": @"Heure", @"icon": @"mdi:clock-outline"},
            @{@"type": @"clock", @"clock_size": @"medium", @"show_seconds": @YES},
        ],
    } language:@"fr"] identifier:nil];
}

#pragma mark - Narrow cells (iPad Mini, max_columns 4, default 6/12 span ≈ 115pt)

- (void)testDigitalNarrowLargeTwelveHourSecondsDate {
    // Must scale the whole time group down uniformly, never truncate "8:06".
    [self verifyView:[self clockCellForCard:@{
        @"type": @"clock", @"clock_size": @"large", @"show_seconds": @YES, @"time_format": @"12",
        @"date_format": @[@"weekday-long", @"day-numeric", @"month-long"],
    } language:@"en" width:115.0] identifier:nil];
}

- (void)testAnalogNarrowMediumNumbersUprightMinuteTicksDate {
    // Dial shrinks below the 160pt nominal; numerals, strokes, hands and the
    // date must shrink with it instead of colliding.
    [self verifyView:[self clockCellForCard:@{
        @"type": @"clock", @"clock_style": @"analog", @"clock_size": @"medium",
        @"face_style": @"numbers_upright", @"ticks": @"minute", @"show_seconds": @YES,
        @"date_format": @[@"weekday-short", @"day-numeric"],
    } language:@"en" width:115.0] identifier:nil];
}

#pragma mark - Analog

- (void)testAnalogSmallMarkersHourTicks {
    [self verifyView:[self clockCellForCard:@{
        @"type": @"clock", @"clock_style": @"analog", @"clock_size": @"small",
        @"show_seconds": @YES, @"face_style": @"markers",
        @"date_format": @[@"day-numeric", @"month-short"],
    } language:@"fr"] identifier:nil];
}

- (void)testAnalogMediumNumbersUprightQuarterBorder {
    [self verifyView:[self clockCellForCard:@{
        @"type": @"clock", @"clock_style": @"analog", @"clock_size": @"medium",
        @"face_style": @"numbers_upright", @"ticks": @"quarter", @"border": @YES,
    } language:@"en"] identifier:nil];
}

- (void)testAnalogLargeRomanMinuteTicks {
    [self verifyView:[self clockCellForCard:@{
        @"type": @"clock", @"clock_style": @"analog", @"clock_size": @"large",
        @"face_style": @"roman", @"ticks": @"minute", @"show_seconds": @YES, @"seconds_motion": @"tick",
        @"date_format": @[@"weekday-long", @"day-numeric", @"month-long"],
    } language:@"fr"] identifier:nil];
}

- (void)testAnalogLargeNumbersUprightHourTicksNoBackground {
    [self verifyView:[self clockCellForCard:@{
        @"type": @"clock", @"clock_style": @"analog", @"clock_size": @"large",
        @"face_style": @"numbers_upright", @"no_background": @YES, @"show_seconds": @YES,
    } language:@"en"] identifier:nil];
}

- (void)testAnalogSmallNoTicksTitleLongDate {
    [self verifyView:[self clockCellForCard:@{
        @"type": @"clock", @"clock_style": @"analog", @"title": @"Paris", @"ticks": @"none",
        @"date_format": @[@"weekday-long", @"day-numeric"],
    } language:@"fr"] identifier:nil];
}

@end
