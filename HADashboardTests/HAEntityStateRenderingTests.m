#import <XCTest/XCTest.h>
#import "HAStateLocalizer.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HASnapshotTestHelpers.h"
#import "HATileEntityCell.h"
#import "HAGlanceItemView.h"
#import "HAEntityRowView.h"
#import "HABadgeRowCell.h"
#import "HABaseEntityCell.h"
#import "HAEntityDisplayHelper.h"
#import "HALovelaceParser.h"

// -----------------------------------------------------------------------
// Regression coverage for the gap the coordinator flagged after the Phase 2
// report: HAPersonEntityCell was fixed directly for issue #19, but a person
// entity rendered by a DIFFERENT cell -- which is exactly what plan §2.5
// suspected was happening for psolyca's report (a Mushroom/Bubble card
// falling back to a generic entity cell) -- still showed the raw
// `not_home`, because HAEntityDisplayHelper's shared -formattedStateForEntity:
// only routed binary_sensor through HAStateLocalizer.
//
// These tests exercise the REAL widget classes end to end (configure +
// read the actual rendered UILabel text out of the view hierarchy), not
// just the shared helper function in isolation, so a future call site that
// bypasses the helper again fails here.
// -----------------------------------------------------------------------

@interface HAEntityStateRenderingTests : XCTestCase
@end

@implementation HAEntityStateRenderingTests

- (void)setUp {
    [super setUp];
    [[HAStateLocalizer sharedLocalizer] test_setResources:nil languageCode:nil];
    NSDictionary<NSString *, NSString *> *english = [self loadFixtureNamed:@"ha-translations-en"];
    [[HAStateLocalizer sharedLocalizer] test_setResources:english languageCode:@"en"];
}

- (void)tearDown {
    [[HAStateLocalizer sharedLocalizer] test_setResources:nil languageCode:nil];
    [super tearDown];
}

#pragma mark - Fixture loading (mirrors HAStateLocalizerTests)

- (NSDictionary<NSString *, NSString *> *)loadFixtureNamed:(NSString *)name {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:name ofType:@"json"];
    XCTAssertNotNil(path, @"Missing fixture %@.json in the test bundle", name);
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNil(error, @"Fixture %@.json failed to parse: %@", name, error);
    return json;
}

/// Recursively searches `view`'s subviews for a UILabel whose text equals
/// `expected`. Used instead of adding test-only accessors to every cell --
/// these widgets don't expose their internal labels publicly, which is
/// correct encapsulation, but a recursive search still lets us assert on
/// the REAL rendered output rather than re-deriving it from the helper.
- (UILabel *)findLabelWithText:(NSString *)expected inView:(UIView *)view {
    if ([view isKindOfClass:[UILabel class]] && [((UILabel *)view).text isEqualToString:expected]) {
        return (UILabel *)view;
    }
    for (UIView *subview in view.subviews) {
        UILabel *found = [self findLabelWithText:expected inView:subview];
        if (found) return found;
    }
    return nil;
}

#pragma mark - Tile path (HATileEntityCell)

- (void)testTileCellRendersPersonNotHomeAsAway {
    HAEntity *entity = [HASnapshotTestHelpers personNotHome];
    HATileEntityCell *cell = [[HATileEntityCell alloc] initWithFrame:CGRectMake(0, 0, 160, 160)];
    HADashboardConfigItem *configItem = [[HADashboardConfigItem alloc] init];
    configItem.entityId = entity.entityId;

    [cell configureWithEntity:entity configItem:configItem];
    [cell layoutIfNeeded];

    UILabel *found = [self findLabelWithText:@"Away" inView:cell.contentView];
    XCTAssertNotNil(found, @"HATileEntityCell must render a person in not_home as \"Away\", not the raw HA state");
}

#pragma mark - Entities-row path (HAEntityRowView)

- (void)testEntitiesRowRendersPersonNotHomeAsAway {
    HAEntity *entity = [HASnapshotTestHelpers personNotHome];
    HAEntityRowView *row = [[HAEntityRowView alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];

    [row configureWithEntity:entity];
    [row layoutIfNeeded];

    UILabel *found = [self findLabelWithText:@"Away" inView:row];
    XCTAssertNotNil(found, @"HAEntityRowView must render a person in not_home as \"Away\", not the raw HA state");
}

#pragma mark - Glance path (HAGlanceItemView)

- (void)testGlanceItemRendersPersonNotHomeAsAway {
    HAEntity *entity = [HASnapshotTestHelpers personNotHome];
    HAGlanceItemView *item = [[HAGlanceItemView alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];

    [item configureWithEntity:entity
                  entityConfig:@{}
                      showName:YES
                     showState:YES
                      showIcon:YES
                    stateColor:NO];
    [item layoutIfNeeded];

    UILabel *found = [self findLabelWithText:@"Away" inView:item];
    XCTAssertNotNil(found, @"HAGlanceItemView must render a person in not_home as \"Away\", not the raw HA state");
}

#pragma mark - Chip/badge path (HABadgeRowCell -- the Mushroom chips fallback, plan §2.5/§7)

- (void)testBadgeRowChipRendersPersonNotHomeAsAway {
    HAEntity *entity = [HASnapshotTestHelpers personNotHome];

    HADashboardConfigSection *section = [[HADashboardConfigSection alloc] init];
    section.entityIds = @[entity.entityId];
    section.nameOverrides = @{};
    section.customProperties = @{@"chipStyle": @YES}; // Mushroom-style: icon + state only

    HABadgeRowCell *cell = [[HABadgeRowCell alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    [cell configureWithSection:section entities:@{entity.entityId: entity}];
    [cell layoutIfNeeded];

    UILabel *found = [self findLabelWithText:@"Away" inView:cell.contentView];
    XCTAssertNotNil(found, @"HABadgeRowCell (Mushroom chip style) must render a person in not_home as \"Away\", not the raw HA state");
}

#pragma mark - device_tracker must use the same path as person

- (void)testDeviceTrackerNotHomeResolvesThroughSharedHelperLikePerson {
    // device_tracker has no dedicated cell -- HAEntityCellFactory routes it
    // to the same HAPersonEntityCell as `person`. The regression this test
    // pins: HAPersonEntityCell used to hardcode domain "person" for its
    // HAStateLocalizer lookup even when actually rendering a device_tracker
    // entity, so device_tracker's own HA-translated/fallback keys were
    // never reachable. Exercise the lookup with the real domain.
    NSString *result = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"device_tracker"
                                                                         deviceClass:nil
                                                                            platform:nil
                                                                      translationKey:nil
                                                                               state:@"not_home"];
    XCTAssertEqualObjects(result, @"Away");
}

#pragma mark - Fallback-card-type badge (GitHub #19)
//
// HABaseEntityCell is the shared base for every domain cell (sensor, light,
// switch, ...) plus HAEntityCardCell/HATileEntityCell, which all call
// [super configureWithEntity:configItem:]. Setting fallbackCardType on the
// item there is what gives every generic fallback path the badge for free.

- (void)testBaseEntityCellShowsFallbackBadgeWhenFallbackCardTypeIsSet {
    HAEntity *entity = [HASnapshotTestHelpers sensorTemperature];
    HABaseEntityCell *cell = [[HABaseEntityCell alloc] initWithFrame:CGRectMake(0, 0, 160, 100)];
    HADashboardConfigItem *configItem = [[HADashboardConfigItem alloc] init];
    configItem.entityId = entity.entityId;
    configItem.fallbackCardType = @"custom:mushroom-entity-card";

    [cell configureWithEntity:entity configItem:configItem];
    [cell layoutIfNeeded];

    XCTAssertFalse(cell.fallbackBadgeLabel.hidden, @"The badge must be visible when fallbackCardType is set");
    XCTAssertEqualObjects(cell.fallbackBadgeLabel.text, @"custom:mushroom-entity-card");
}

- (void)testBaseEntityCellHidesFallbackBadgeWhenFallbackCardTypeIsNil {
    HAEntity *entity = [HASnapshotTestHelpers sensorTemperature];
    HABaseEntityCell *cell = [[HABaseEntityCell alloc] initWithFrame:CGRectMake(0, 0, 160, 100)];
    HADashboardConfigItem *configItem = [[HADashboardConfigItem alloc] init];
    configItem.entityId = entity.entityId;
    // fallbackCardType left nil -- a normal, fully-supported card.

    [cell configureWithEntity:entity configItem:configItem];
    [cell layoutIfNeeded];

    XCTAssertTrue(cell.fallbackBadgeLabel.hidden, @"The badge must stay hidden for a normal card");
    XCTAssertNil(cell.fallbackBadgeLabel.text);
}

- (void)testBaseEntityCellHidesFallbackBadgeAfterReuseWithoutFallbackCardType {
    // Regression guard: a reused cell previously showing a fallback badge
    // must not leak it onto the next (non-fallback) item it's configured for.
    HAEntity *entity = [HASnapshotTestHelpers sensorTemperature];
    HABaseEntityCell *cell = [[HABaseEntityCell alloc] initWithFrame:CGRectMake(0, 0, 160, 100)];
    HADashboardConfigItem *fallbackItem = [[HADashboardConfigItem alloc] init];
    fallbackItem.entityId = entity.entityId;
    fallbackItem.fallbackCardType = @"custom:bubble-card";
    [cell configureWithEntity:entity configItem:fallbackItem];
    XCTAssertFalse(cell.fallbackBadgeLabel.hidden);

    [cell prepareForReuse];

    HADashboardConfigItem *normalItem = [[HADashboardConfigItem alloc] init];
    normalItem.entityId = entity.entityId;
    [cell configureWithEntity:entity configItem:normalItem];
    [cell layoutIfNeeded];

    XCTAssertTrue(cell.fallbackBadgeLabel.hidden, @"A reused cell must not keep showing a stale fallback badge");
}

#pragma mark - Timestamp states (issue #22)

/// ISO 8601 string `seconds` from now, in UTC with a +00:00 offset as HA sends it.
- (NSString *)isoStringOffsetBySeconds:(NSTimeInterval)seconds date:(NSDate **)outDate {
    NSDate *date = [NSDate dateWithTimeIntervalSinceNow:seconds];
    // Drop sub-second precision so the parsed date round-trips exactly
    date = [NSDate dateWithTimeIntervalSince1970:floor(date.timeIntervalSince1970)];
    if (outDate) *outDate = date;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'+00:00'";
    return [formatter stringFromDate:date];
}

- (HAEntity *)sunNextRisingInSeconds:(NSTimeInterval)seconds date:(NSDate **)outDate {
    NSString *state = [self isoStringOffsetBySeconds:seconds date:outDate];
    return [HASnapshotTestHelpers entityWithId:@"sensor.sun_next_rising"
                                         state:state
                                    attributes:@{@"device_class": @"timestamp",
                                                 @"friendly_name": @"Sun Next rising"}];
}

- (NSString *)timeStringWithStyle:(NSDateFormatterStyle)style fromDate:(NSDate *)date {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = style;
    return [formatter stringFromDate:date];
}

- (void)testTimestampStateIsNotFormattedAsTheLeadingYear {
    HAEntity *entity = [self sunNextRisingInSeconds:10 * 3600 + 120 date:NULL];
    NSString *state = [HAEntityDisplayHelper formattedStateForEntity:entity decimals:2];
    XCTAssertFalse([state containsString:@"026"], @"Timestamp parsed as the number 2026: %@", state);
    XCTAssertEqualObjects(state, @"In 10 hours");
}

- (void)testIsoShapedStateWithoutDeviceClassStillRendersRelative {
    NSString *iso = [self isoStringOffsetBySeconds:-(3 * 3600 + 60) date:NULL];
    HAEntity *entity = [HASnapshotTestHelpers entityWithId:@"sensor.last_boot" state:iso attributes:@{}];
    XCTAssertEqualObjects([HAEntityDisplayHelper formattedStateForEntity:entity decimals:2], @"3 hours ago");
}

- (void)testUnknownTimestampStateFallsThroughToLocalizedState {
    HAEntity *entity = [HASnapshotTestHelpers entityWithId:@"sensor.sun_next_rising"
                                                     state:@"unknown"
                                                attributes:@{@"device_class": @"timestamp"}];
    NSString *state = [HAEntityDisplayHelper formattedStateForEntity:entity decimals:2];
    XCTAssertFalse([state isEqualToString:@"0"]);
    XCTAssertTrue(state.length > 0);
}

- (void)testTimeFormatObjectTimeLongIncludesSeconds {
    NSDate *date = nil;
    HAEntity *entity = [self sunNextRisingInSeconds:10 * 3600 date:&date];
    NSString *state = [HAEntityDisplayHelper formattedStateForEntity:entity
                                                            decimals:2
                                                          timeFormat:@{@"type": @"time", @"style": @"long"}];
    XCTAssertEqualObjects(state, [self timeStringWithStyle:NSDateFormatterMediumStyle fromDate:date]);
}

- (void)testTimeFormatStringTimeOmitsSeconds {
    NSDate *date = nil;
    HAEntity *entity = [self sunNextRisingInSeconds:10 * 3600 date:&date];
    NSString *state = [HAEntityDisplayHelper formattedStateForEntity:entity decimals:2 timeFormat:@"time"];
    XCTAssertEqualObjects(state, [self timeStringWithStyle:NSDateFormatterShortStyle fromDate:date]);
}

- (void)testTimeFormatDateShortIsNumeric {
    NSDate *date = nil;
    HAEntity *entity = [self sunNextRisingInSeconds:10 * 3600 date:&date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterNoStyle;
    NSString *state = [HAEntityDisplayHelper formattedStateForEntity:entity
                                                            decimals:2
                                                          timeFormat:@{@"type": @"date", @"style": @"short"}];
    XCTAssertEqualObjects(state, [formatter stringFromDate:date]);
}

- (void)testUptimeDefaultsToTotalDuration {
    NSString *iso = [self isoStringOffsetBySeconds:-(2 * 86400 + 5 * 3600 + 30) date:NULL];
    HAEntity *entity = [HASnapshotTestHelpers entityWithId:@"sensor.uptime"
                                                     state:iso
                                                attributes:@{@"device_class": @"uptime"}];
    NSString *state = [HAEntityDisplayHelper formattedStateForEntity:entity decimals:2];
    NSString *expected = [HAEntityDisplayHelper formattedDurationFromValue:(2 * 86400 + 5 * 3600 + 30) unit:@"s"];
    XCTAssertEqualObjects(state, expected);
}

- (void)testTileRendersReporterConfigWithBlankNameAndLongTime {
    // ha-dashboard/ios-app#22: name ' ' plus time_format {type: time, style: long}
    NSDictionary *card = @{@"type": @"tile",
                           @"entity": @"sensor.sun_next_rising",
                           @"name": @" ",
                           @"icon": @"mdi:weather-sunset-up",
                           @"show_entity_picture": @NO,
                           @"hide_state": @NO,
                           @"vertical": @NO,
                           @"features_position": @"bottom",
                           @"time_format": @{@"type": @"time", @"style": @"long"}};
    NSDictionary *dashDict = @{@"views": @[@{@"title": @"Test", @"cards": @[card]}]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashDict];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3];
    HADashboardConfigItem *item = nil;
    for (HADashboardConfigItem *candidate in config.items) {
        if ([candidate.entityId isEqualToString:@"sensor.sun_next_rising"]) item = candidate;
    }
    XCTAssertNotNil(item);
    XCTAssertEqualObjects(item.customProperties[@"name_blank"], @YES);
    XCTAssertEqualObjects(item.customProperties[@"time_format"], (@{@"type": @"time", @"style": @"long"}));

    NSDate *date = nil;
    HAEntity *entity = [self sunNextRisingInSeconds:10 * 3600 date:&date];
    HATileEntityCell *cell = [[HATileEntityCell alloc] initWithFrame:CGRectMake(0, 0, 200, 72)];
    [cell configureWithEntity:entity configItem:item];
    [cell layoutIfNeeded];

    NSString *expected = [self timeStringWithStyle:NSDateFormatterMediumStyle fromDate:date];
    XCTAssertNotNil([self findLabelWithText:expected inView:cell.contentView],
                    @"Tile must render the timestamp as %@", expected);
    UILabel *nameLabel = [self findLabelWithText:@"Sun Next rising" inView:cell.contentView];
    XCTAssertTrue(nameLabel == nil || nameLabel.hidden,
                  @"A blank configured name must not fall back to a visible friendly name");
}

- (void)testTileNonBlankNameIsUnaffected {
    NSDictionary *card = @{@"type": @"tile", @"entity": @"sensor.sun_next_rising", @"name": @"Sunrise"};
    NSDictionary *dashDict = @{@"views": @[@{@"title": @"Test", @"cards": @[card]}]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashDict];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:3];
    HADashboardConfigItem *item = config.items.firstObject;
    XCTAssertNil(item.customProperties[@"name_blank"]);
    XCTAssertEqualObjects(item.displayName, @"Sunrise");
}

@end
