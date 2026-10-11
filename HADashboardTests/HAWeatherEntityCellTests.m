#import <XCTest/XCTest.h>
#import "HAWeatherEntityCell.h"
#import "HADashboardConfig.h"
#import "HAEntity.h"
#import "HASnapshotTestHelpers.h"

/// Covers GitHub #20: HAWeatherEntityCell honoring show_current /
/// show_forecast (and the height math in +preferredHeightForConfigItem:)
/// without relying on pixel-diff snapshots. Private layout state is read via
/// KVC (-valueForKey:), the same pattern already used by
/// HAClassicLayoutTests/HAControlSnapshotTests in this suite.
@interface HAWeatherEntityCellTests : XCTestCase
@end

@implementation HAWeatherEntityCellTests

#pragma mark - Helpers

- (HADashboardConfigItem *)itemWithCustomProperties:(NSDictionary *)props {
    HADashboardConfigItem *item = [[HADashboardConfigItem alloc] init];
    item.entityId = @"weather.home";
    item.cardType = @"weather-forecast";
    item.columnSpan = 12;
    item.rowSpan = 1;
    item.customProperties = props;
    return item;
}

- (HAWeatherEntityCell *)cellConfiguredWithEntity:(HAEntity *)entity item:(HADashboardConfigItem *)item {
    CGFloat height = [HAWeatherEntityCell preferredHeightForConfigItem:item];
    HAWeatherEntityCell *cell = [[HAWeatherEntityCell alloc] initWithFrame:CGRectMake(0, 0, 320, height)];
    [cell configureWithEntity:entity configItem:item];
    [cell layoutIfNeeded];
    return cell;
}

#pragma mark - preferredHeightForConfigItem: math

- (void)testPreferredHeight_defaults_matchesLegacyPreferredHeight {
    XCTAssertEqualWithAccuracy([HAWeatherEntityCell preferredHeightForConfigItem:nil],
                               [HAWeatherEntityCell preferredHeight], 0.01);
}

- (void)testPreferredHeight_showForecastFalse_isSmallerThanDefault {
    HADashboardConfigItem *item = [self itemWithCustomProperties:@{@"show_forecast": @NO}];
    CGFloat height = [HAWeatherEntityCell preferredHeightForConfigItem:item];
    XCTAssertLessThan(height, [HAWeatherEntityCell preferredHeight]);
}

- (void)testPreferredHeight_showCurrentFalse_isSmallerThanDefault {
    HADashboardConfigItem *item = [self itemWithCustomProperties:@{@"show_current": @NO}];
    CGFloat height = [HAWeatherEntityCell preferredHeightForConfigItem:item];
    XCTAssertLessThan(height, [HAWeatherEntityCell preferredHeight]);
}

- (void)testPreferredHeight_bothFalse_fallsBackToCurrentConditionsOnly {
    // HA never renders a fully blank card: show_current: false is overridden
    // when show_forecast is also false (hui-weather-forecast-card.ts's
    // `weather = !forecast || show_current !== false`).
    HADashboardConfigItem *bothFalse = [self itemWithCustomProperties:@{@"show_current": @NO, @"show_forecast": @NO}];
    HADashboardConfigItem *currentOnly = [self itemWithCustomProperties:@{@"show_forecast": @NO}];
    XCTAssertEqualWithAccuracy([HAWeatherEntityCell preferredHeightForConfigItem:bothFalse],
                               [HAWeatherEntityCell preferredHeightForConfigItem:currentOnly], 0.01);
}

- (void)testPreferredHeight_forecastSlots_scalesHeight {
    HADashboardConfigItem *fiveSlots = [self itemWithCustomProperties:@{@"forecast_slots": @5}];
    HADashboardConfigItem *twoSlots = [self itemWithCustomProperties:@{@"forecast_slots": @2}];
    CGFloat fiveHeight = [HAWeatherEntityCell preferredHeightForConfigItem:fiveSlots];
    CGFloat twoHeight = [HAWeatherEntityCell preferredHeightForConfigItem:twoSlots];
    XCTAssertLessThan(twoHeight, fiveHeight);
}

- (void)testPreferredHeight_forecastSlots_isClamped {
    HADashboardConfigItem *huge = [self itemWithCustomProperties:@{@"forecast_slots": @999}];
    HADashboardConfigItem *clampedEquivalent = [self itemWithCustomProperties:@{@"forecast_slots": @10}];
    XCTAssertEqualWithAccuracy([HAWeatherEntityCell preferredHeightForConfigItem:huge],
                               [HAWeatherEntityCell preferredHeightForConfigItem:clampedEquivalent], 0.01);
}

#pragma mark - Section visibility

- (void)testShowForecastFalse_hidesForecastContainerContent {
    HAEntity *entity = [HASnapshotTestHelpers weatherSunny];
    HADashboardConfigItem *item = [self itemWithCustomProperties:@{@"show_forecast": @NO}];
    HAWeatherEntityCell *cell = [self cellConfiguredWithEntity:entity item:item];

    UIView *forecastContainer = [cell valueForKey:@"forecastContainer"];
    XCTAssertEqual(forecastContainer.subviews.count, (NSUInteger)0, @"show_forecast: false must not render forecast rows");

    NSLayoutConstraint *forecastHeightConstraint = [cell valueForKey:@"forecastHeightConstraint"];
    XCTAssertEqualWithAccuracy(forecastHeightConstraint.constant, 0, 0.01);

    UILabel *conditionSymbol = [cell valueForKey:@"conditionSymbol"];
    XCTAssertFalse(conditionSymbol.hidden, @"current conditions must still show when forecast is off");
}

- (void)testShowCurrentFalse_hidesCurrentConditionsWhenForecastShown {
    HAEntity *entity = [HASnapshotTestHelpers weatherSunny];
    HADashboardConfigItem *item = [self itemWithCustomProperties:@{@"show_current": @NO}];
    HAWeatherEntityCell *cell = [self cellConfiguredWithEntity:entity item:item];

    UILabel *conditionSymbol = [cell valueForKey:@"conditionSymbol"];
    UILabel *tempLabel = [cell valueForKey:@"tempLabel"];
    UILabel *detailsLabel = [cell valueForKey:@"detailsLabel"];
    XCTAssertTrue(conditionSymbol.hidden);
    XCTAssertTrue(tempLabel.hidden);
    XCTAssertTrue(detailsLabel.hidden);

    NSNumber *forecastTopWhenCurrentShownActive = [[cell valueForKey:@"forecastTopWhenCurrentShown"] valueForKey:@"active"];
    NSNumber *forecastTopWhenCurrentHiddenActive = [[cell valueForKey:@"forecastTopWhenCurrentHidden"] valueForKey:@"active"];
    XCTAssertFalse(forecastTopWhenCurrentShownActive.boolValue);
    XCTAssertTrue(forecastTopWhenCurrentHiddenActive.boolValue);
}

- (void)testShowCurrentFalseAndShowForecastFalse_forcesCurrentConditionsVisible {
    HAEntity *entity = [HASnapshotTestHelpers weatherSunny];
    HADashboardConfigItem *item = [self itemWithCustomProperties:@{@"show_current": @NO, @"show_forecast": @NO}];
    HAWeatherEntityCell *cell = [self cellConfiguredWithEntity:entity item:item];

    UILabel *conditionSymbol = [cell valueForKey:@"conditionSymbol"];
    XCTAssertFalse(conditionSymbol.hidden, @"card must never render fully blank");
}

#pragma mark - round_temperature

- (void)testRoundTemperatureFalse_showsOneDecimalPlace {
    HAEntity *entity = [HASnapshotTestHelpers weatherSunny]; // temperature: -5
    HADashboardConfigItem *item = [self itemWithCustomProperties:@{@"round_temperature": @NO}];
    HAWeatherEntityCell *cell = [self cellConfiguredWithEntity:entity item:item];

    UILabel *tempLabel = [cell valueForKey:@"tempLabel"];
    XCTAssertTrue([tempLabel.text containsString:@"."], @"round_temperature: false should show a decimal, got %@", tempLabel.text);
}

- (void)testRoundTemperatureDefault_showsWholeDegrees {
    HAEntity *entity = [HASnapshotTestHelpers weatherSunny];
    HADashboardConfigItem *item = [self itemWithCustomProperties:@{}];
    HAWeatherEntityCell *cell = [self cellConfiguredWithEntity:entity item:item];

    UILabel *tempLabel = [cell valueForKey:@"tempLabel"];
    XCTAssertFalse([tempLabel.text containsString:@"."], @"default should keep the existing whole-degree rendering, got %@", tempLabel.text);
}

#pragma mark - secondary_info_attribute

- (void)testSecondaryInfoAttribute_showsOnlyThatAttribute {
    HAEntity *entity = [HASnapshotTestHelpers weatherSunny]; // has humidity + wind_speed + pressure
    HADashboardConfigItem *item = [self itemWithCustomProperties:@{@"secondary_info_attribute": @"wind_speed"}];
    HAWeatherEntityCell *cell = [self cellConfiguredWithEntity:entity item:item];

    UILabel *detailsLabel = [cell valueForKey:@"detailsLabel"];
    XCTAssertTrue([detailsLabel.text containsString:@"Wind"]);
    XCTAssertFalse([detailsLabel.text containsString:@"Humidity"]);
    XCTAssertFalse([detailsLabel.text containsString:@"Pressure"]);
}

@end
