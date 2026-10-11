#import "HAWeatherHelper.h"
#import "HALog.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"

@implementation HAWeatherHelper

#pragma mark - Weather Condition to MDI Icon Mapping

+ (NSString *)mdiIconNameForCondition:(NSString *)condition {
    if (!condition) return @"weather-cloudy";
    static NSDictionary *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"clear-night":      @"weather-night",
            @"cloudy":           @"weather-cloudy",
            @"fog":              @"weather-fog",
            @"hail":             @"weather-hail",
            @"lightning":        @"weather-lightning",
            @"lightning-rainy":  @"weather-lightning-rainy",
            @"partlycloudy":     @"weather-partly-cloudy",
            @"pouring":          @"weather-pouring",
            @"rainy":            @"weather-rainy",
            @"snowy":            @"weather-snowy",
            @"snowy-rainy":      @"weather-snowy-rainy",
            @"sunny":            @"weather-sunny",
            @"windy":            @"weather-windy",
            @"windy-variant":    @"weather-windy-variant",
            @"exceptional":      @"alert-circle-outline",
        };
    });
    NSString *iconName = map[condition];
    return iconName ?: @"weather-cloudy";
}

#pragma mark - Forecast Fetch

+ (void)fetchForecastForEntity:(HAEntity *)entity
                    completion:(void(^)(NSArray *forecast, NSError *error))completion {
    [self fetchForecastForEntity:entity forecastType:nil completion:completion];
}

+ (void)fetchForecastForEntity:(HAEntity *)entity
                   forecastType:(NSString *)forecastType
                     completion:(void(^)(NSArray *forecast, NSError *error))completion {
    if (!entity || !completion) return;

    // First try legacy entity attributes path (pre-2023.9 HA) — same priority
    // HA's own getForecast() gives attribute-based forecasts.
    NSArray *legacyForecast = [entity weatherForecast];
    if (legacyForecast.count > 0) {
        if ([NSThread isMainThread]) {
            completion(legacyForecast, nil);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(legacyForecast, nil);
            });
        }
        return;
    }

    if ([forecastType isEqualToString:@"legacy"]) {
        // forecast_type: legacy explicitly opts out of the modern service call
        // (mirrors _needForecastSubscription() in hui-weather-forecast-card.ts).
        // No attribute-based forecast was found above, so there is none to show.
        if ([NSThread isMainThread]) {
            completion(nil, nil);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, nil);
            });
        }
        return;
    }

    static NSSet<NSString *> *modernForecastTypes = nil;
    if (!modernForecastTypes) {
        modernForecastTypes = [NSSet setWithArray:@[@"daily", @"hourly", @"twice_daily"]];
    }
    NSString *serviceForecastType = [modernForecastTypes containsObject:forecastType] ? forecastType : @"daily";

    // Modern HA: call weather.get_forecasts service with return_response
    NSDictionary *command = @{
        @"type": @"call_service",
        @"domain": @"weather",
        @"service": @"get_forecasts",
        @"target": @{@"entity_id": entity.entityId},
        @"service_data": @{@"type": serviceForecastType},
        @"return_response": @YES
    };

    NSString *currentEntityId = entity.entityId;

    [[HAConnectionManager sharedManager] sendCommand:command completion:^(id result, NSError *error) {
        if (error) {
            HALogE(@"weather", @"Forecast fetch failed: %@", error.localizedDescription);
            if (completion) completion(nil, error);
            return;
        }

        // Response format: { "response": { "weather.entity_id": { "forecast": [...] } } }
        NSArray *forecast = nil;
        if ([result isKindOfClass:[NSDictionary class]]) {
            NSDictionary *response = result[@"response"];
            if ([response isKindOfClass:[NSDictionary class]]) {
                for (NSString *key in response) {
                    NSDictionary *entityForecast = response[key];
                    if ([entityForecast isKindOfClass:[NSDictionary class]]) {
                        forecast = entityForecast[@"forecast"];
                        if ([forecast isKindOfClass:[NSArray class]]) break;
                    }
                }
            }
            if (!forecast) forecast = result[@"forecast"];
        }

        if ([forecast isKindOfClass:[NSArray class]] && forecast.count > 0) {
            if (completion) completion(forecast, nil);
        } else {
            HALogW(@"weather", @"No forecast data in response: %@", result);
            if (completion) completion(nil, nil);
        }
    }];
}

@end
