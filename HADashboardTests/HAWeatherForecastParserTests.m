#import <XCTest/XCTest.h>
#import "HALovelaceParser.h"
#import "HADashboardConfig.h"

/// Covers GitHub #20: the weather-forecast card's show_current / show_forecast
/// toggles (and the cheap-to-forward forecast_type / forecast_slots /
/// secondary_info_attribute / round_temperature options) must survive
/// parsing into HADashboardConfigItem.customProperties, with HA's documented
/// defaults (both true) when the config omits them.
@interface HAWeatherForecastParserTests : XCTestCase
@end

@implementation HAWeatherForecastParserTests

#pragma mark - Helpers

- (HADashboardConfigItem *)itemForWeatherCard:(NSDictionary *)card {
    NSDictionary *viewDict = @{@"title": @"Test", @"cards": @[card]};
    NSDictionary *dashDict = @{@"views": @[viewDict]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:dashDict];
    HALovelaceView *view = dashboard.views.firstObject;
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:view columns:3];
    return config.items.firstObject;
}

#pragma mark - Defaults

- (void)testDefaults_noOptionsSet_customPropertiesOmitShowFlags {
    HADashboardConfigItem *item = [self itemForWeatherCard:@{
        @"type": @"weather-forecast",
        @"entity": @"weather.home"
    }];
    XCTAssertNotNil(item);
    // Absent from customProperties means "use HA's default (true)" — the
    // cell/height-calc treat a missing key as true, not the parser.
    XCTAssertNil(item.customProperties[@"show_current"]);
    XCTAssertNil(item.customProperties[@"show_forecast"]);
    XCTAssertNil(item.customProperties[@"forecast_type"]);
    XCTAssertNil(item.customProperties[@"forecast_slots"]);
    XCTAssertNil(item.customProperties[@"secondary_info_attribute"]);
    XCTAssertNil(item.customProperties[@"round_temperature"]);
}

#pragma mark - show_current / show_forecast

- (void)testShowForecastExplicitlyFalse_isPreserved {
    HADashboardConfigItem *item = [self itemForWeatherCard:@{
        @"type": @"weather-forecast",
        @"entity": @"weather.home",
        @"show_forecast": @NO
    }];
    XCTAssertEqualObjects(item.customProperties[@"show_forecast"], @NO);
    XCTAssertNil(item.customProperties[@"show_current"]);
}

- (void)testShowCurrentExplicitlyFalse_isPreserved {
    HADashboardConfigItem *item = [self itemForWeatherCard:@{
        @"type": @"weather-forecast",
        @"entity": @"weather.home",
        @"show_current": @NO
    }];
    XCTAssertEqualObjects(item.customProperties[@"show_current"], @NO);
    XCTAssertNil(item.customProperties[@"show_forecast"]);
}

- (void)testShowCurrentExplicitlyTrue_isPreserved {
    // Explicit true (redundant with the default) must still round-trip —
    // the parser shouldn't special-case "true" away.
    HADashboardConfigItem *item = [self itemForWeatherCard:@{
        @"type": @"weather-forecast",
        @"entity": @"weather.home",
        @"show_current": @YES,
        @"show_forecast": @YES
    }];
    XCTAssertEqualObjects(item.customProperties[@"show_current"], @YES);
    XCTAssertEqualObjects(item.customProperties[@"show_forecast"], @YES);
}

#pragma mark - forecast_type / forecast_slots / secondary_info_attribute / round_temperature

- (void)testForecastType_isForwarded {
    HADashboardConfigItem *item = [self itemForWeatherCard:@{
        @"type": @"weather-forecast",
        @"entity": @"weather.home",
        @"forecast_type": @"hourly"
    }];
    XCTAssertEqualObjects(item.customProperties[@"forecast_type"], @"hourly");
}

- (void)testForecastSlots_isForwarded {
    HADashboardConfigItem *item = [self itemForWeatherCard:@{
        @"type": @"weather-forecast",
        @"entity": @"weather.home",
        @"forecast_slots": @3
    }];
    XCTAssertEqualObjects(item.customProperties[@"forecast_slots"], @3);
}

- (void)testSecondaryInfoAttribute_isForwarded {
    HADashboardConfigItem *item = [self itemForWeatherCard:@{
        @"type": @"weather-forecast",
        @"entity": @"weather.home",
        @"secondary_info_attribute": @"wind_speed"
    }];
    XCTAssertEqualObjects(item.customProperties[@"secondary_info_attribute"], @"wind_speed");
}

- (void)testRoundTemperatureFalse_isForwarded {
    HADashboardConfigItem *item = [self itemForWeatherCard:@{
        @"type": @"weather-forecast",
        @"entity": @"weather.home",
        @"round_temperature": @NO
    }];
    XCTAssertEqualObjects(item.customProperties[@"round_temperature"], @NO);
}

#pragma mark - Non weather-forecast cards are unaffected

- (void)testNonWeatherCard_doesNotGainWeatherCustomProperties {
    HADashboardConfigItem *item = [self itemForWeatherCard:@{
        @"type": @"tile",
        @"entity": @"light.kitchen",
        @"show_current": @NO // only meaningful on weather-forecast; must be ignored here
    }];
    XCTAssertNil(item.customProperties[@"show_current"]);
}

@end
