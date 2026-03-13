#import "HAAutoLayout.h"
#import "HAClockWeatherCell.h"
#import "HADateUtils.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HAConnectionManager.h"
#import "LOTAnimationView.h"
#import "HAWeatherHelper.h"
#import "UIFont+HACompat.h"

/// Top content height: padding(12) + max(icon 80, text chain ~96) = ~110pt
static const CGFloat kTopContentHeight = 110.0;
/// Spacing between top content and forecast
static const CGFloat kForecastGap = 8.0;
/// Per-row height including inter-row spacing (28pt bar + 2pt gap)
static const CGFloat kForecastRowHeight = 30.0;
/// Bottom padding below forecast
static const CGFloat kBottomPadding = 12.0;

@interface HAClockWeatherCell ()
@property (nonatomic, strong) LOTAnimationView *lottieView;      // animated weather icon
@property (nonatomic, strong) UILabel *weatherIconLabel;          // MDI fallback
@property (nonatomic, copy)   NSString *currentWeatherIcon;       // currently loaded icon name
@property (nonatomic, strong) UILabel *conditionLabel;
@property (nonatomic, strong) UILabel *humidityLabel;
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *forecastLabel;   // kept for attributed text fallback
@property (nonatomic, strong) UIView *forecastBarView;  // container for visual forecast bar
@property (nonatomic, strong) NSLayoutConstraint *forecastHeightConstraint;
@property (nonatomic, strong) NSTimer *clockTimer;
@property (nonatomic, strong) NSDateFormatter *clockFormatter;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, copy)   NSDictionary *cardConfig;
@end

@implementation HAClockWeatherCell

+ (CGFloat)preferredHeight {
    return [self preferredHeightForForecastRows:5];
}

+ (CGFloat)preferredHeightForForecastRows:(NSInteger)rows {
    if (rows <= 0) rows = 5;
    CGFloat forecastHeight = kForecastRowHeight * rows;
    return kTopContentHeight + kForecastGap + forecastHeight + kBottomPadding;
}

#pragma mark - Setup

- (void)setupSubviews {
    [super setupSubviews];

    // Hide the default name/state labels from HABaseEntityCell
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    CGFloat padding = 12.0;
    CGFloat iconSize = 80.0;

    // Lottie animated weather icon (from clock-weather-card)
    // Placeholder view — actual LOTAnimationView is created in loadWeatherIconForCondition:
    // since LOTAnimationView needs the animation name at init time
    self.lottieView = nil; // created lazily

    // MDI fallback label (shown if no Lottie JSON available)
    self.weatherIconLabel = [[UILabel alloc] init];
    self.weatherIconLabel.font = [HAIconMapper mdiFontOfSize:50];
    self.weatherIconLabel.textColor = [HATheme primaryTextColor];
    self.weatherIconLabel.textAlignment = NSTextAlignmentCenter;
    self.weatherIconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.weatherIconLabel];

    // Condition text (top-right): "Rainy, 7C"
    self.conditionLabel = [[UILabel alloc] init];
    self.conditionLabel.font = [UIFont ha_systemFontOfSize:15 weight:HAFontWeightMedium];
    self.conditionLabel.textColor = [HATheme primaryTextColor];
    self.conditionLabel.numberOfLines = 1;
    self.conditionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.conditionLabel];

    // Humidity (below condition)
    self.humidityLabel = [[UILabel alloc] init];
    self.humidityLabel.font = [UIFont systemFontOfSize:12];
    self.humidityLabel.textColor = [HATheme secondaryTextColor];
    self.humidityLabel.numberOfLines = 1;
    self.humidityLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.humidityLabel];

    // Clock (large digital)
    self.clockLabel = [[UILabel alloc] init];
    self.clockLabel.font = [UIFont ha_monospacedDigitSystemFontOfSize:44 weight:HAFontWeightLight];
    self.clockLabel.textColor = [HATheme primaryTextColor];
    self.clockLabel.textAlignment = NSTextAlignmentLeft;
    self.clockLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.clockLabel];

    // Date (below clock)
    self.dateLabel = [[UILabel alloc] init];
    self.dateLabel.font = [UIFont systemFontOfSize:13];
    self.dateLabel.textColor = [HATheme secondaryTextColor];
    self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.dateLabel];

    // Forecast bar container (bottom) — subviews added dynamically in renderForecast:
    self.forecastBarView = [[UIView alloc] init];
    self.forecastBarView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.forecastBarView];

    // --- Layout ---

    // Weather icon (MDI fallback / Lottie placeholder position)
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.weatherIconLabel attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.weatherIconLabel attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.weatherIconLabel attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:iconSize]),
        HACon([NSLayoutConstraint constraintWithItem:self.weatherIconLabel attribute:NSLayoutAttributeHeight
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:iconSize]),
    ]);

    // Condition label: right of icon, aligned to top
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.conditionLabel attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.weatherIconLabel attribute:NSLayoutAttributeTrailing multiplier:1 constant:8]),
        HACon([NSLayoutConstraint constraintWithItem:self.conditionLabel attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.conditionLabel attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]),
    ]);

    // Humidity: below condition
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.humidityLabel attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.conditionLabel attribute:NSLayoutAttributeLeading multiplier:1 constant:0]),
        HACon([NSLayoutConstraint constraintWithItem:self.humidityLabel attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.humidityLabel attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.conditionLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:2]),
    ]);

    // Clock: right of icon, below humidity
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.clockLabel attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.conditionLabel attribute:NSLayoutAttributeLeading multiplier:1 constant:0]),
        HACon([NSLayoutConstraint constraintWithItem:self.clockLabel attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.clockLabel attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.humidityLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:4]),
    ]);

    // Date: below clock
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.dateLabel attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.conditionLabel attribute:NSLayoutAttributeLeading multiplier:1 constant:0]),
        HACon([NSLayoutConstraint constraintWithItem:self.dateLabel attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.dateLabel attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.clockLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:0]),
    ]);

    // Forecast bar: pinned to bottom, must not overlap date label or icon
    self.forecastHeightConstraint = HAMakeConstraint([self.forecastBarView.heightAnchor constraintEqualToConstant:28.0]);
    NSLayoutConstraint *forecastBelowDate = HAMakeConstraint([self.forecastBarView.topAnchor constraintGreaterThanOrEqualToAnchor:self.dateLabel.bottomAnchor constant:kForecastGap]);
    NSLayoutConstraint *forecastBelowIcon = HAMakeConstraint([self.forecastBarView.topAnchor constraintGreaterThanOrEqualToAnchor:self.weatherIconLabel.bottomAnchor constant:kForecastGap]);
    HAActivateConstraints(@[
        HACon([self.forecastBarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]),
        HACon([self.forecastBarView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding]),
        HACon([self.forecastBarView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding]),
        HACon(self.forecastHeightConstraint),
        HACon(forecastBelowDate),
        HACon(forecastBelowIcon),
    ]);

    // Initialize formatters
    self.clockFormatter = [[NSDateFormatter alloc] init];
    self.dateFormatter = [[NSDateFormatter alloc] init];
}

#pragma mark - Configure

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.cardConfig = configItem.customProperties;

    // Configure clock format (default 24h)
    NSNumber *timeFormat = self.cardConfig[@"time_format"];
    BOOL is24h = (!timeFormat || [timeFormat integerValue] == 24);
    [self.clockFormatter setDateFormat:is24h ? @"HH:mm" : @"h:mm a"];

    // Configure date format
    NSString *datePattern = self.cardConfig[@"date_pattern"];
    if (!datePattern) datePattern = @"EEE, d.MM.yy";
    // Convert clock-weather-card date_pattern to NSDateFormatter pattern:
    // "ccc" -> "EEE" (short day name), already compatible
    // Replace "ccc" with "EEE" for NSDateFormatter
    NSString *nsDatePattern = [datePattern stringByReplacingOccurrencesOfString:@"ccc" withString:@"EEE"];
    [self.dateFormatter setDateFormat:nsDatePattern];

    // Configure locale
    NSString *localeStr = self.cardConfig[@"locale"];
    if (localeStr) {
        NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:
            [localeStr stringByReplacingOccurrencesOfString:@"-" withString:@"_"]];
        self.clockFormatter.locale = locale;
        self.dateFormatter.locale = locale;
    }

    if (!entity) return;

    // Weather icon from condition — try animated PNG sequence first, MDI fallback
    NSString *condition = [entity weatherCondition];
    [self loadWeatherIconForCondition:condition];

    // Condition text: capitalize and add temperature
    NSString *conditionDisplay = [self capitalizedCondition:condition];
    NSNumber *temp = [self resolvedTemperatureForEntity:entity];
    NSString *unit = [entity weatherTemperatureUnit];
    if (temp) {
        self.conditionLabel.text = [NSString stringWithFormat:@"%@, %.0f%@", conditionDisplay, temp.doubleValue, unit];
    } else {
        self.conditionLabel.text = conditionDisplay;
    }

    // Humidity
    NSNumber *humidity = [self resolvedHumidityForEntity:entity];
    if (humidity) {
        self.humidityLabel.text = [NSString stringWithFormat:@"%.0f%% Humidity", humidity.doubleValue];
    } else {
        self.humidityLabel.text = nil;
    }

    // Update clock and date immediately
    [self updateClockDisplay];

    // Start timer
    [self.clockTimer invalidate];
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                      target:self
                                                    selector:@selector(clockTimerFired)
                                                    userInfo:nil
                                                     repeats:YES];

    // Forecast bar — fetch via WebSocket (modern HA removed forecast from entity attributes)
    [self fetchForecastForEntity:entity];
}

#pragma mark - Temperature / Humidity Resolution

/// Returns temperature from the temperature_sensor override if configured, otherwise from the weather entity
- (NSNumber *)resolvedTemperatureForEntity:(HAEntity *)entity {
    NSString *tempSensorId = self.cardConfig[@"temperature_sensor"];
    if (tempSensorId) {
        HAEntity *tempSensor = [[HAConnectionManager sharedManager] entityForId:tempSensorId];
        if (tempSensor && tempSensor.state && ![tempSensor.state isEqualToString:@"unavailable"]) {
            double val = [tempSensor.state doubleValue];
            return @(val);
        }
    }
    return [entity weatherTemperature];
}

/// Returns humidity from the humidity_sensor override if configured, otherwise from the weather entity
- (NSNumber *)resolvedHumidityForEntity:(HAEntity *)entity {
    NSString *humiditySensorId = self.cardConfig[@"humidity_sensor"];
    if (humiditySensorId) {
        HAEntity *humiditySensor = [[HAConnectionManager sharedManager] entityForId:humiditySensorId];
        if (humiditySensor && humiditySensor.state && ![humiditySensor.state isEqualToString:@"unavailable"]) {
            double val = [humiditySensor.state doubleValue];
            return @(val);
        }
    }
    return [entity weatherHumidity];
}

#pragma mark - Condition Display

- (NSString *)capitalizedCondition:(NSString *)condition {
    if (!condition || condition.length == 0) return @"Unknown";
    static NSDictionary *conditionLabels = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        conditionLabels = @{
            @"clear-night":      @"Clear Night",
            @"cloudy":           @"Cloudy",
            @"fog":              @"Fog",
            @"hail":             @"Hail",
            @"lightning":        @"Lightning",
            @"lightning-rainy":  @"Lightning & Rain",
            @"partlycloudy":     @"Partly Cloudy",
            @"pouring":          @"Pouring",
            @"rainy":            @"Rainy",
            @"snowy":            @"Snowy",
            @"snowy-rainy":      @"Sleet",
            @"sunny":            @"Sunny",
            @"windy":            @"Windy",
            @"windy-variant":    @"Windy",
            @"exceptional":      @"Exceptional",
        };
    });
    NSString *label = conditionLabels[condition];
    if (label) return label;
    // Fallback: replace hyphens with spaces, capitalize first letter
    NSString *cleaned = [condition stringByReplacingOccurrencesOfString:@"-" withString:@" "];
    return [[[cleaned substringToIndex:1] uppercaseString] stringByAppendingString:[cleaned substringFromIndex:1]];
}

#pragma mark - Clock Timer

- (void)clockTimerFired {
    [self updateClockDisplay];
}

- (void)updateClockDisplay {
    NSDate *now = self.overrideDate ?: [NSDate date];
    self.clockLabel.text = [self.clockFormatter stringFromDate:now];
    self.dateLabel.text = [self.dateFormatter stringFromDate:now];
}

#pragma mark - Temperature Color

/// Maps temperature (°C) to a color matching the clock-weather-card gradient:
///   -20°C → dark blue, -10°C → blue, 0°C → light blue, 10°C → turquoise,
///   20°C → yellow, 30°C → orange, 40°C → pink
+ (UIColor *)colorForTemperature:(double)temp {
    // Gradient stops: temperature → RGB
    static const struct { double t; double r, g, b; } stops[] = {
        {-20,   0/255.0,  60/255.0,  98/255.0},
        {-10, 120/255.0, 162/255.0, 204/255.0},
        {  0, 164/255.0, 195/255.0, 210/255.0},
        { 10, 121/255.0, 210/255.0, 179/255.0},
        { 20, 252/255.0, 245/255.0, 112/255.0},
        { 30, 255/255.0, 150/255.0,  79/255.0},
        { 40, 255/255.0, 192/255.0, 159/255.0},
    };
    static const int stopCount = sizeof(stops) / sizeof(stops[0]);

    // Clamp to range
    if (temp <= stops[0].t) return [UIColor colorWithRed:stops[0].r green:stops[0].g blue:stops[0].b alpha:1];
    if (temp >= stops[stopCount-1].t) return [UIColor colorWithRed:stops[stopCount-1].r green:stops[stopCount-1].g blue:stops[stopCount-1].b alpha:1];

    // Find bounding stops and interpolate
    for (int i = 0; i < stopCount - 1; i++) {
        if (temp >= stops[i].t && temp <= stops[i+1].t) {
            double ratio = (temp - stops[i].t) / (stops[i+1].t - stops[i].t);
            double r = stops[i].r + ratio * (stops[i+1].r - stops[i].r);
            double g = stops[i].g + ratio * (stops[i+1].g - stops[i].g);
            double b = stops[i].b + ratio * (stops[i+1].b - stops[i].b);
            return [UIColor colorWithRed:r green:g blue:b alpha:1];
        }
    }

    return [UIColor colorWithRed:stops[3].r green:stops[3].g blue:stops[3].b alpha:1]; // fallback: 10°C turquoise
}

#pragma mark - Forecast

/// Fetch forecast via WebSocket call_service with return_response (HA 2023.7+).
/// The subscribe_forecast API is subscription-based and doesn't return data in the
/// initial result. Using call_service + return_response is a one-shot approach that
/// works with the completion handler pattern.
- (void)fetchForecastForEntity:(HAEntity *)entity {
    __weak typeof(self) weakSelf = self;
    NSString *currentEntityId = entity.entityId;

    [HAWeatherHelper fetchForecastForEntity:entity completion:^(NSArray *forecast, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // Verify cell still shows the same entity (not reused)
        if (![strongSelf.entity.entityId isEqualToString:currentEntityId]) return;

        if (forecast.count > 0) {
            HAEntity *currentEntity = [[HAConnectionManager sharedManager] entityForId:currentEntityId];
            [strongSelf renderForecast:forecast entity:currentEntity ?: entity];
        }
    }];
}

/// Render forecast data as a visual bar: [Day] [Icon] [Low°] [==gradient==] [High°]
- (void)renderForecast:(NSArray *)forecast entity:(HAEntity *)entity {
    // Clear existing forecast bar content
    for (UIView *v in self.forecastBarView.subviews) [v removeFromSuperview];

    NSInteger forecastRows = 5;
    NSNumber *rowsConfig = self.cardConfig[@"forecast_rows"];
    if (rowsConfig) forecastRows = [rowsConfig integerValue];
    if (forecastRows <= 0) forecastRows = 5;

    // Update forecast container height for the number of rows (28pt bar + 2pt gap per row)
    NSInteger actualRows = MIN(forecastRows, (NSInteger)forecast.count);
    if (actualRows < 1) actualRows = 1;
    self.forecastHeightConstraint.constant = kForecastRowHeight * actualRows - 2.0;

    static NSDateFormatter *sDayFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sDayFormatter = [[NSDateFormatter alloc] init];
        [sDayFormatter setDateFormat:@"EEE"];
    });

    // Apply locale if configured (formatter is shared, but re-set each render is cheap)
    NSString *localeStr = self.cardConfig[@"locale"];
    if (localeStr) {
        sDayFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:
            [localeStr stringByReplacingOccurrencesOfString:@"-" withString:@"_"]];
    } else {
        sDayFormatter.locale = [NSLocale currentLocale];
    }

    NSString *unit = [entity weatherTemperatureUnit] ?: @"°";
    UIFont *textFont = [UIFont systemFontOfSize:11];
    CGFloat iconFontSize = 14;
    UIColor *textColor = [HATheme secondaryTextColor];
    CGFloat barHeight = 28.0;
    CGFloat rowY = 0;

    NSInteger count = MIN(forecastRows, (NSInteger)forecast.count);
    for (NSInteger i = 0; i < count; i++) {
        NSDictionary *day = forecast[i];
        if (![day isKindOfClass:[NSDictionary class]]) continue;

        // Day name
        NSString *dayName = @"";
        NSString *dateStr = day[@"datetime"];
        if ([dateStr isKindOfClass:[NSString class]]) {
            NSDate *date = [HADateUtils dateFromISO8601String:dateStr];
            if (date) dayName = [sDayFormatter stringFromDate:date];
        }

        NSNumber *tempLow = day[@"templow"];
        NSNumber *tempHigh = day[@"temperature"];
        NSString *dayCondition = day[@"condition"];
        NSString *mdiName = [HAWeatherHelper mdiIconNameForCondition:dayCondition];
        NSString *dayGlyph = [HAIconMapper glyphForIconName:mdiName];

        // Layout: [Day 28pt] [Icon 20pt] [Low 36pt] [Bar flex] [High 36pt]
        CGFloat x = 0;
        CGFloat fullWidth = self.forecastBarView.bounds.size.width;
        if (fullWidth <= 0) fullWidth = 280; // fallback

        // Day name label
        UILabel *dayLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, rowY, 28, barHeight)];
        dayLabel.text = dayName;
        dayLabel.font = textFont;
        dayLabel.textColor = textColor;
        dayLabel.textAlignment = NSTextAlignmentLeft;
        [self.forecastBarView addSubview:dayLabel];
        x += 28;

        // Weather icon
        UILabel *iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, rowY, 20, barHeight)];
        if (dayGlyph) {
            iconLabel.attributedText = [HAIconMapper attributedGlyph:dayGlyph fontSize:iconFontSize color:textColor];
        } else {
            iconLabel.text = @"?";
            iconLabel.font = textFont;
            iconLabel.textColor = textColor;
        }
        iconLabel.textAlignment = NSTextAlignmentCenter;
        [self.forecastBarView addSubview:iconLabel];
        x += 24;

        // Low temp
        NSString *lowStr = tempLow ? [NSString stringWithFormat:@"%.0f%@", tempLow.doubleValue, unit] : @"";
        UILabel *lowLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, rowY, 36, barHeight)];
        lowLabel.text = lowStr;
        lowLabel.font = textFont;
        lowLabel.textColor = textColor;
        lowLabel.textAlignment = NSTextAlignmentRight;
        [self.forecastBarView addSubview:lowLabel];
        x += 40;

        // Temperature gradient bar — colors based on actual temperature range
        CGFloat barWidth = fullWidth - x - 44;
        if (barWidth > 20 && tempLow && tempHigh) {
            CGFloat barY = rowY + (barHeight - 6) / 2.0;
            UIView *gradientBar = [[UIView alloc] initWithFrame:CGRectMake(x, barY, barWidth, 6)];
            gradientBar.layer.cornerRadius = 3.0;
            gradientBar.clipsToBounds = YES;

            UIColor *lowColor = [[self class] colorForTemperature:tempLow.doubleValue];
            UIColor *highColor = [[self class] colorForTemperature:tempHigh.doubleValue];

            CAGradientLayer *gradient = [CAGradientLayer layer];
            gradient.frame = gradientBar.bounds;
            gradient.startPoint = CGPointMake(0, 0.5);
            gradient.endPoint = CGPointMake(1, 0.5);
            gradient.colors = @[(id)lowColor.CGColor, (id)highColor.CGColor];
            gradient.cornerRadius = 3.0;
            [gradientBar.layer addSublayer:gradient];

            [self.forecastBarView addSubview:gradientBar];
            x += barWidth + 4;
        }

        // High temp
        NSString *highStr = tempHigh ? [NSString stringWithFormat:@"%.0f%@", tempHigh.doubleValue, unit] : @"";
        UILabel *highLabel = [[UILabel alloc] initWithFrame:CGRectMake(fullWidth - 36, rowY, 36, barHeight)];
        highLabel.text = highStr;
        highLabel.font = textFont;
        highLabel.textColor = textColor;
        highLabel.textAlignment = NSTextAlignmentLeft;
        [self.forecastBarView addSubview:highLabel];

        rowY += barHeight + 2;
    }
}

#pragma mark - Weather Icon

/// Map HA weather condition to the animated icon filename (from clock-weather-card Lottie exports).
/// Returns nil if no matching icon bundle is found — falls back to MDI glyph.
+ (NSString *)iconFileNameForCondition:(NSString *)condition isDaytime:(BOOL)daytime {
    if (!condition) return nil;
    static NSDictionary *dayMap = nil;
    static NSDictionary *nightMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dayMap = @{
            @"sunny":            @"clear-day",
            @"clear-night":      @"clear-night",
            @"cloudy":           @"cloudy",
            @"partlycloudy":     @"partly-cloudy-day",
            @"fog":              @"fog-day",
            @"hail":             @"hail",
            @"lightning":        @"thunderstorms-day",
            @"lightning-rainy":  @"thunderstorms-day",
            @"pouring":          @"rain",
            @"rainy":            @"drizzle",
            @"snowy":            @"snow",
            @"snowy-rainy":      @"sleet",
            @"windy":            @"wind",
            @"windy-variant":    @"wind",
            @"exceptional":      @"dust-day",
        };
        nightMap = @{
            @"sunny":            @"clear-night",
            @"clear-night":      @"clear-night",
            @"cloudy":           @"cloudy",
            @"partlycloudy":     @"partly-cloudy-night",
            @"fog":              @"fog-night",
            @"hail":             @"hail",
            @"lightning":        @"thunderstorms-night",
            @"lightning-rainy":  @"thunderstorms-night",
            @"pouring":          @"rain",
            @"rainy":            @"drizzle",
            @"snowy":            @"snow",
            @"snowy-rainy":      @"sleet",
            @"windy":            @"wind",
            @"windy-variant":    @"wind",
            @"exceptional":      @"dust-day",
        };
    });
    NSDictionary *map = daytime ? dayMap : nightMap;
    return map[condition] ?: dayMap[condition];
}

/// Load animated weather icon using lottie-ios 2.x (LOTAnimationView).
/// Falls back to MDI glyph + Core Animation if Lottie JSON not found.
- (void)loadWeatherIconForCondition:(NSString *)condition {
    // Determine day/night
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSInteger hour;
    if ([cal respondsToSelector:@selector(component:fromDate:)]) {
        hour = [cal component:NSCalendarUnitHour fromDate:[NSDate date]];
    } else {
        NSDateComponents *comps = [cal components:NSHourCalendarUnit fromDate:[NSDate date]];
        hour = [comps hour];
    }
    BOOL isDaytime = (hour >= 6 && hour < 20);

    NSString *iconName = [[self class] iconFileNameForCondition:condition isDaytime:isDaytime];

    // Skip if same icon already playing
    if ([iconName isEqualToString:self.currentWeatherIcon] && self.lottieView) return;

    // Remove old Lottie view
    [self.lottieView removeFromSuperview];
    self.lottieView = nil;

    CGFloat padding = 12.0;
    CGFloat iconSize = 80.0;

    // Try loading Lottie JSON from bundle
    if (iconName) {
        NSString *path = [[NSBundle mainBundle] pathForResource:iconName ofType:@"json"];
        if (path) {
            LOTAnimationView *lottie = [LOTAnimationView animationWithFilePath:path];
            lottie.frame = CGRectMake(padding, padding, iconSize, iconSize);
            lottie.contentMode = UIViewContentModeScaleAspectFit;
            lottie.loopAnimation = YES;
            [self.contentView insertSubview:lottie belowSubview:self.weatherIconLabel];
            [lottie play];

            self.lottieView = lottie;
            self.currentWeatherIcon = iconName;
            self.weatherIconLabel.hidden = YES;
            [self.weatherIconLabel.layer removeAllAnimations];
            return;
        }
    }

    // Fall back to MDI glyph with Core Animation
    self.currentWeatherIcon = nil;
    self.weatherIconLabel.hidden = NO;

    NSString *mdiIconName = [HAWeatherHelper mdiIconNameForCondition:condition];
    NSString *glyph = [HAIconMapper glyphForIconName:mdiIconName];
    self.weatherIconLabel.text = glyph ?: @"\u2601";
    [self animateWeatherIconForCondition:condition];
}

/// Core Animation fallback for MDI glyph weather icon
- (void)animateWeatherIconForCondition:(NSString *)condition {
    [self.weatherIconLabel.layer removeAllAnimations];
    if (!condition) return;

    CABasicAnimation *anim = nil;
    NSString *key = nil;

    if ([condition isEqualToString:@"sunny"]) {
        anim = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        anim.fromValue = @0; anim.toValue = @(M_PI * 2);
        anim.duration = 12.0;
        key = @"sunRotation";
    } else if (([condition rangeOfString:@"rainy"].location != NSNotFound) || [condition isEqualToString:@"pouring"]) {
        anim = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
        anim.fromValue = @(-2); anim.toValue = @(2);
        anim.duration = 1.5; anim.autoreverses = YES;
        key = @"rainBounce";
    } else if ([condition rangeOfString:@"cloudy"].location != NSNotFound) {
        anim = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
        anim.fromValue = @(-3); anim.toValue = @(3);
        anim.duration = 3.0; anim.autoreverses = YES;
        key = @"cloudDrift";
    } else if ([condition rangeOfString:@"wind"].location != NSNotFound) {
        anim = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        anim.fromValue = @(-0.1); anim.toValue = @(0.1);
        anim.duration = 0.8; anim.autoreverses = YES;
        key = @"windSway";
    } else if ([condition rangeOfString:@"lightning"].location != NSNotFound) {
        anim = [CABasicAnimation animationWithKeyPath:@"opacity"];
        anim.fromValue = @(1.0); anim.toValue = @(0.4);
        anim.duration = 0.3; anim.autoreverses = YES;
        key = @"lightningFlash";
    } else if ([condition rangeOfString:@"snowy"].location != NSNotFound) {
        anim = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
        anim.fromValue = @(-2); anim.toValue = @(2);
        anim.duration = 2.0; anim.autoreverses = YES;
        key = @"snowFall";
    } else if ([condition isEqualToString:@"fog"]) {
        anim = [CABasicAnimation animationWithKeyPath:@"opacity"];
        anim.fromValue = @(1.0); anim.toValue = @(0.6);
        anim.duration = 3.0; anim.autoreverses = YES;
        key = @"fogFade";
    } else if ([condition isEqualToString:@"clear-night"]) {
        anim = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        anim.fromValue = @(1.0); anim.toValue = @(1.05);
        anim.duration = 2.0; anim.autoreverses = YES;
        key = @"nightPulse";
    }

    if (anim && key) {
        anim.repeatCount = HUGE_VALF;
        anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.weatherIconLabel.layer addAnimation:anim forKey:key];
    }
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat padding = 12.0;
        CGFloat iconSize = 80.0;

        // Weather icon: top-left
        self.weatherIconLabel.frame = CGRectMake(padding, padding, iconSize, iconSize);
        if (self.lottieView) {
            self.lottieView.frame = self.weatherIconLabel.frame;
        }

        // Text column: right of icon
        CGFloat textX = padding + iconSize + 8;
        CGFloat textW = w - textX - padding;

        CGSize condSize = [self.conditionLabel sizeThatFits:CGSizeMake(textW, CGFLOAT_MAX)];
        self.conditionLabel.frame = CGRectMake(textX, padding, textW, condSize.height);

        CGSize humidSize = [self.humidityLabel sizeThatFits:CGSizeMake(textW, CGFLOAT_MAX)];
        self.humidityLabel.frame = CGRectMake(textX, CGRectGetMaxY(self.conditionLabel.frame) + 2, textW, humidSize.height);

        CGSize clockSize = [self.clockLabel sizeThatFits:CGSizeMake(textW, CGFLOAT_MAX)];
        self.clockLabel.frame = CGRectMake(textX, CGRectGetMaxY(self.humidityLabel.frame) + 4, textW, clockSize.height);

        CGSize dateSize = [self.dateLabel sizeThatFits:CGSizeMake(textW, CGFLOAT_MAX)];
        self.dateLabel.frame = CGRectMake(textX, CGRectGetMaxY(self.clockLabel.frame), textW, dateSize.height);

        // Forecast bar: bottom area
        CGFloat forecastH = h - kTopContentHeight - kForecastGap - padding;
        if (forecastH < 20) forecastH = 20;
        self.forecastBarView.frame = CGRectMake(padding, kTopContentHeight + kForecastGap, w - padding * 2, forecastH);
    }
}

#pragma mark - Window Lifecycle

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [self.clockTimer invalidate];
        self.clockTimer = nil;
    }
}

#pragma mark - Reuse / Cleanup

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.clockTimer invalidate];
    self.clockTimer = nil;
    [self.lottieView removeFromSuperview];
    self.lottieView = nil;
    self.currentWeatherIcon = nil;
    [self.weatherIconLabel.layer removeAllAnimations];
    self.weatherIconLabel.text = nil;
    self.weatherIconLabel.hidden = NO;
    self.conditionLabel.text = nil;
    self.humidityLabel.text = nil;
    self.clockLabel.text = nil;
    self.dateLabel.text = nil;
    for (UIView *v in self.forecastBarView.subviews) [v removeFromSuperview];
    self.cardConfig = nil;
    self.weatherIconLabel.textColor = [HATheme primaryTextColor];
    self.conditionLabel.textColor = [HATheme primaryTextColor];
    self.humidityLabel.textColor = [HATheme secondaryTextColor];
    self.clockLabel.textColor = [HATheme primaryTextColor];
    self.dateLabel.textColor = [HATheme secondaryTextColor];
}

- (void)dealloc {
    [_clockTimer invalidate];
}

@end
