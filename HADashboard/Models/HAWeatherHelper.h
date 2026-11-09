#import <Foundation/Foundation.h>

@class HAEntity;

/// Shared weather utilities used by HAWeatherEntityCell and HAClockWeatherCell.
@interface HAWeatherHelper : NSObject

/// Maps a Home Assistant weather condition string to an MDI icon name.
+ (NSString *)mdiIconNameForCondition:(NSString *)condition;

/// Fetches forecast data for a weather entity via the modern WebSocket API,
/// falling back to legacy entity attributes for older HA versions.
/// Completion is called on the main queue. Equivalent to calling
/// +fetchForecastForEntity:forecastType:completion: with a nil forecastType.
+ (void)fetchForecastForEntity:(HAEntity *)entity
                    completion:(void(^)(NSArray *forecast, NSError *error))completion;

/// Fetches forecast data for a weather entity, honoring the weather-forecast
/// card's `forecast_type` option (daily/hourly/twice_daily/legacy).
///
/// Legacy entity attributes (pre-2023.9 HA) are tried first regardless of
/// forecastType, same as the frontend's getForecast() helper. When
/// forecastType is "legacy" and no attribute-based forecast exists, this does
/// NOT fall back to the modern service call — mirroring
/// hui-weather-forecast-card.ts's _needForecastSubscription(), which returns
/// false for "legacy" and never asks the backend for a forecast. Otherwise
/// forecastType ("daily"/"hourly"/"twice_daily") is forwarded as the
/// `weather.get_forecasts` service's `type` field; an unrecognized or nil
/// value defaults to "daily" (the pre-existing hardcoded behavior).
///
/// Note: this performs a single one-shot `get_forecasts` service call, not
/// HA's live `weather/subscribe_forecast` WebSocket subscription — forecast
/// data will not push-update between dashboard rebuilds.
+ (void)fetchForecastForEntity:(HAEntity *)entity
                   forecastType:(NSString *)forecastType
                     completion:(void(^)(NSArray *forecast, NSError *error))completion;

@end
