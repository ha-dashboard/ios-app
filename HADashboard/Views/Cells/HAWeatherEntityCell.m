#import "HAWeatherEntityCell.h"
#import "HAStrings.h"
#import "HADateUtils.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HAConnectionManager.h"
#import "HAWeatherHelper.h"

/// Height for the top section: name + condition symbol + temp + details
static const CGFloat kTopContentHeight = 90.0;
/// Gap between top content and forecast strip
static const CGFloat kForecastGap = 6.0;
/// Per-row height for forecast (24pt row + 2pt gap)
static const CGFloat kForecastRowHeight = 26.0;
/// Bottom padding below forecast
static const CGFloat kBottomPadding = 10.0;
/// Number of forecast rows when forecast_slots isn't configured
static const NSInteger kDefaultForecastRows = 5;
/// forecast_slots is clamped to this range so a bad config value can't blow
/// out the cell height or produce a degenerate 0-row forecast.
static const NSInteger kMinForecastRows = 1;
static const NSInteger kMaxForecastRows = 10;

static NSInteger HAWeatherForecastRowsFromCustomProperties(NSDictionary *customProperties) {
    NSNumber *slots = customProperties[@"forecast_slots"];
    if (![slots isKindOfClass:[NSNumber class]]) return kDefaultForecastRows;
    NSInteger rows = slots.integerValue;
    return MAX(kMinForecastRows, MIN(kMaxForecastRows, rows));
}

/// show_current/show_forecast both default to true in HA. Mirrors
/// hui-weather-forecast-card.ts: the card never renders fully blank, so the
/// current-conditions section is forced on when the forecast section isn't
/// shown, even if show_current was itself explicitly false
/// (`weather = !forecast || show_current !== false`).
static void HAWeatherSectionsFromCustomProperties(NSDictionary *customProperties, BOOL *showCurrentOut, BOOL *showForecastOut) {
    NSNumber *showCurrentNum = customProperties[@"show_current"];
    NSNumber *showForecastNum = customProperties[@"show_forecast"];
    BOOL showForecastConfig = [showForecastNum isKindOfClass:[NSNumber class]] ? showForecastNum.boolValue : YES;
    BOOL showCurrentConfig = [showCurrentNum isKindOfClass:[NSNumber class]] ? showCurrentNum.boolValue : YES;
    if (showForecastOut) *showForecastOut = showForecastConfig;
    if (showCurrentOut) *showCurrentOut = showCurrentConfig || !showForecastConfig;
}

@interface HAWeatherEntityCell ()
@property (nonatomic, strong) UILabel *conditionSymbol;
@property (nonatomic, strong) UILabel *tempLabel;
@property (nonatomic, strong) UILabel *detailsLabel;
@property (nonatomic, strong) UIView *forecastContainer;
// Exactly one of these two is active at a time (toggled in
// -configureWithEntity:configItem:), never both — see the comment on
// -setupSubviews for why this is two constraints instead of one mutable one.
@property (nonatomic, strong) NSLayoutConstraint *forecastTopWhenCurrentShown;
@property (nonatomic, strong) NSLayoutConstraint *forecastTopWhenCurrentHidden;
@property (nonatomic, strong) NSLayoutConstraint *forecastHeightConstraint;
@property (nonatomic, assign) BOOL forecastSectionEnabled;
@property (nonatomic, assign) NSInteger forecastSlots;
@property (nonatomic, copy) NSString *forecastType;
@property (nonatomic, copy) NSString *secondaryInfoAttribute;
@property (nonatomic, assign) BOOL roundTemperature;
@end

@implementation HAWeatherEntityCell

+ (CGFloat)preferredHeight {
    return [self preferredHeightForConfigItem:nil];
}

+ (CGFloat)preferredHeightForConfigItem:(HADashboardConfigItem *)configItem {
    NSDictionary *props = configItem.customProperties;
    BOOL showCurrent, showForecast;
    HAWeatherSectionsFromCustomProperties(props, &showCurrent, &showForecast);
    NSInteger forecastRows = HAWeatherForecastRowsFromCustomProperties(props);

    CGFloat height = kBottomPadding;
    if (showCurrent) height += kTopContentHeight;
    if (showForecast) {
        if (showCurrent) height += kForecastGap;
        height += kForecastRowHeight * forecastRows;
    }
    return height;
}

#pragma mark - Setup

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Large weather symbol
    self.conditionSymbol = [[UILabel alloc] init];
    self.conditionSymbol.font = [UIFont systemFontOfSize:36];
    self.conditionSymbol.textAlignment = NSTextAlignmentCenter;
    self.conditionSymbol.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.conditionSymbol];

    // Temperature
    self.tempLabel = [[UILabel alloc] init];
    self.tempLabel.font = [UIFont monospacedDigitSystemFontOfSize:28 weight:UIFontWeightLight];
    self.tempLabel.textColor = [HATheme primaryTextColor];
    self.tempLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.tempLabel];

    // Details: humidity, wind, pressure
    self.detailsLabel = [[UILabel alloc] init];
    self.detailsLabel.font = [UIFont systemFontOfSize:11];
    self.detailsLabel.textColor = [HATheme secondaryTextColor];
    self.detailsLabel.numberOfLines = 1;
    self.detailsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.detailsLabel];

    // Forecast container
    self.forecastContainer = [[UIView alloc] init];
    self.forecastContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.forecastContainer.clipsToBounds = YES;
    [self.contentView addSubview:self.forecastContainer];

    // Symbol: left side, below name. Deliberately NOT wrapped in a
    // fixed-height "current conditions" container: these three labels'
    // combined height is only ever an ESTIMATE (kTopContentHeight, used by
    // +preferredHeightForConfigItem:), never an Auto Layout requirement —
    // forcing a hard height here previously fought with the (also required)
    // nameLabel-above / forecastContainer-below constraints whenever the
    // estimate didn't exactly match reality, and Auto Layout resolved that
    // conflict by collapsing nameLabel's own height to 0 (GitHub #20 code
    // review). Leaving this organic, like before #20, means any shortfall is
    // instead absorbed by the forecast rows running tight against the
    // bottom — exactly this cell's pre-#20 behavior.
    [NSLayoutConstraint activateConstraints:@[
        [self.conditionSymbol.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [self.conditionSymbol.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2],
    ]];

    // Temp: right of symbol
    [NSLayoutConstraint activateConstraints:@[
        [self.tempLabel.leadingAnchor constraintEqualToAnchor:self.conditionSymbol.trailingAnchor constant:8],
        [self.tempLabel.centerYAnchor constraintEqualToAnchor:self.conditionSymbol.centerYAnchor],
    ]];

    // Details: below condition symbol, single line
    [NSLayoutConstraint activateConstraints:@[
        [self.detailsLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [self.detailsLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
        [self.detailsLabel.topAnchor constraintEqualToAnchor:self.conditionSymbol.bottomAnchor constant:4],
    ]];

    // Forecast container: below the current-conditions labels, pinned
    // leading/trailing/bottom. Two alternate top constraints, toggled by
    // -configureWithEntity:configItem: (never both active): one anchored to
    // detailsLabel (current conditions shown — organic, ">=" so a taller
    // current-conditions block just tightens the gap instead of conflicting)
    // and one anchored directly to nameLabel (current conditions hidden, so
    // the forecast strip isn't pinned below hidden-but-still-laid-out labels).
    self.forecastTopWhenCurrentShown = [self.forecastContainer.topAnchor constraintGreaterThanOrEqualToAnchor:self.detailsLabel.bottomAnchor constant:kForecastGap];
    self.forecastTopWhenCurrentHidden = [self.forecastContainer.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2];
    self.forecastTopWhenCurrentHidden.active = NO; // default: current conditions shown

    self.forecastHeightConstraint = [self.forecastContainer.heightAnchor constraintEqualToConstant:kForecastRowHeight * kDefaultForecastRows];
    [NSLayoutConstraint activateConstraints:@[
        [self.forecastContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [self.forecastContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
        self.forecastTopWhenCurrentShown,
        [self.forecastContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-kBottomPadding],
        self.forecastHeightConstraint,
    ]];
}

#pragma mark - Configure

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    NSDictionary *props = configItem.customProperties;
    BOOL showCurrent, showForecast;
    HAWeatherSectionsFromCustomProperties(props, &showCurrent, &showForecast);

    self.forecastSectionEnabled = showForecast;
    self.forecastSlots = HAWeatherForecastRowsFromCustomProperties(props);
    self.forecastType = [props[@"forecast_type"] isKindOfClass:[NSString class]] ? props[@"forecast_type"] : nil;
    self.secondaryInfoAttribute = [props[@"secondary_info_attribute"] isKindOfClass:[NSString class]] ? props[@"secondary_info_attribute"] : nil;
    NSNumber *roundTemperatureNum = props[@"round_temperature"];
    // Default true: the cell has always rendered whole-degree temperatures;
    // round_temperature: false is the only way to opt into one decimal place.
    self.roundTemperature = [roundTemperatureNum isKindOfClass:[NSNumber class]] ? roundTemperatureNum.boolValue : YES;

    self.conditionSymbol.hidden = !showCurrent;
    self.tempLabel.hidden = !showCurrent;
    self.detailsLabel.hidden = !showCurrent;
    self.forecastTopWhenCurrentShown.active = showCurrent;
    self.forecastTopWhenCurrentHidden.active = !showCurrent;

    if (!showForecast) {
        for (UIView *v in self.forecastContainer.subviews) [v removeFromSuperview];
        self.forecastHeightConstraint.constant = 0;
    } else {
        // Provisional height until the forecast fetch completes and
        // -renderForecast: tightens it to the actual row count.
        self.forecastHeightConstraint.constant = kForecastRowHeight * self.forecastSlots;
    }

    NSString *condition = [entity weatherCondition];
    self.conditionSymbol.text = [HAEntity symbolForWeatherCondition:condition];

    NSString *tempFormat = self.roundTemperature ? @"%.0f%@" : @"%.1f%@";
    NSNumber *temp = [entity weatherTemperature];
    NSString *unit = [entity weatherTemperatureUnit];
    if (temp) {
        self.tempLabel.text = [NSString stringWithFormat:tempFormat, temp.doubleValue, unit];
    } else {
        self.tempLabel.text = HALocalizedString(@"cell.weather.no_value", @"Temperature label fallback in the weather cell, shown when no temperature is available.");
    }

    // Build details string. When secondary_info_attribute is configured,
    // HA shows only that single attribute next to the temperature instead of
    // this cell's default "show everything available" summary line.
    NSArray<NSString *> *details;
    if (self.secondaryInfoAttribute.length > 0) {
        NSString *single = [self detailStringForAttribute:self.secondaryInfoAttribute entity:entity];
        details = single ? @[single] : @[];
    } else {
        details = [self defaultDetailStringsForEntity:entity];
    }
    self.detailsLabel.text = [details componentsJoinedByString:@"  ·  "];

    // Background tint based on condition
    if ([condition isEqualToString:@"sunny"] || [condition isEqualToString:@"clear-night"]) {
        self.contentView.backgroundColor = [HATheme onTintColor];
    } else if ([condition hasPrefix:@"rain"] || [condition isEqualToString:@"pouring"]) {
        self.contentView.backgroundColor = [HATheme coolTintColor];
    } else if ([condition hasPrefix:@"snow"]) {
        self.contentView.backgroundColor = [HATheme coolTintColor];
    } else {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    }

    // Fetch and render forecast (skipped entirely when show_forecast: false)
    if (entity && showForecast) {
        [self fetchForecastForEntity:entity];
    }
}

#pragma mark - Detail Attribute Formatting

// Note: HA's secondary_info_attribute also accepts "temperature" and
// "apparent_temperature" (WEATHER_TEMPERATURE_ATTRIBUTES in the frontend's
// data/weather.ts) — this cell doesn't have an existing localized label for
// either (unlike "Dew:", which was already hardcoded here), so they're left
// unsupported rather than inventing new user-visible strings outside the
// localization pipeline. dew_point, the one temperature-like attribute this
// cell already displayed, is still supported below.

- (NSString *)detailStringForAttribute:(NSString *)attribute entity:(HAEntity *)entity {
    NSString *tempFormat = self.roundTemperature ? @"%.0f°" : @"%.1f°";

    if ([attribute isEqualToString:@"humidity"]) {
        NSNumber *humidity = [entity weatherHumidity];
        return humidity ? [NSString stringWithFormat:@"Humidity: %.0f%%", humidity.doubleValue] : nil;
    }
    if ([attribute isEqualToString:@"wind_speed"]) {
        NSNumber *wind = [entity weatherWindSpeed];
        if (!wind) return nil;
        NSString *bearing = [entity weatherWindBearing];
        return bearing ? [NSString stringWithFormat:@"Wind: %.0f %@", wind.doubleValue, bearing]
                        : [NSString stringWithFormat:@"Wind: %.0f", wind.doubleValue];
    }
    if ([attribute isEqualToString:@"pressure"]) {
        NSNumber *pressure = [entity weatherPressure];
        return pressure ? [NSString stringWithFormat:@"Pressure: %.0f", pressure.doubleValue] : nil;
    }
    if ([attribute isEqualToString:@"visibility"]) {
        NSNumber *visibility = HAAttrNumber(entity.attributes, @"visibility");
        return visibility ? [NSString stringWithFormat:@"Vis: %.0f", visibility.doubleValue] : nil;
    }
    if ([attribute isEqualToString:@"uv_index"]) {
        NSNumber *uvIndex = HAAttrNumber(entity.attributes, @"uv_index");
        return uvIndex ? [NSString stringWithFormat:@"UV: %.0f", uvIndex.doubleValue] : nil;
    }
    if ([attribute isEqualToString:@"precipitation"]) {
        NSNumber *precipitation = HAAttrNumber(entity.attributes, @"precipitation");
        return precipitation ? [NSString stringWithFormat:@"Precip: %.1f", precipitation.doubleValue] : nil;
    }
    if ([attribute isEqualToString:@"dew_point"]) {
        NSNumber *dewPoint = HAAttrNumber(entity.attributes, @"dew_point");
        return dewPoint ? [NSString stringWithFormat:@"Dew: %@", [NSString stringWithFormat:tempFormat, dewPoint.doubleValue]] : nil;
    }
    if ([attribute isEqualToString:@"cloud_coverage"]) {
        NSNumber *cloudCoverage = HAAttrNumber(entity.attributes, @"cloud_coverage");
        return cloudCoverage ? [NSString stringWithFormat:@"Cloud: %.0f%%", cloudCoverage.doubleValue] : nil;
    }
    return nil;
}

- (NSArray<NSString *> *)defaultDetailStringsForEntity:(HAEntity *)entity {
    NSMutableArray *details = [NSMutableArray array];
    for (NSString *attribute in @[@"humidity", @"wind_speed", @"pressure", @"visibility",
                                   @"uv_index", @"precipitation", @"dew_point", @"cloud_coverage"]) {
        NSString *value = [self detailStringForAttribute:attribute entity:entity];
        if (value) [details addObject:value];
    }
    return details;
}

#pragma mark - Forecast Fetch

- (void)fetchForecastForEntity:(HAEntity *)entity {
    __weak typeof(self) weakSelf = self;
    NSString *currentEntityId = entity.entityId;

    [HAWeatherHelper fetchForecastForEntity:entity forecastType:self.forecastType completion:^(NSArray *forecast, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        // Verify cell still shows the same entity (not reused) and that the
        // forecast section wasn't turned off while the fetch was in flight.
        if (![strongSelf.entity.entityId isEqualToString:currentEntityId]) return;
        if (!strongSelf.forecastSectionEnabled) return;

        if (forecast.count > 0) {
            HAEntity *currentEntity = [[HAConnectionManager sharedManager] entityForId:currentEntityId];
            [strongSelf renderForecast:forecast entity:currentEntity ?: entity];
        }
    }];
}

#pragma mark - Forecast Rendering

- (void)renderForecast:(NSArray *)forecast entity:(HAEntity *)entity {
    // Clear existing forecast content
    for (UIView *v in self.forecastContainer.subviews) [v removeFromSuperview];

    NSInteger forecastRows = self.forecastSlots > 0 ? self.forecastSlots : kDefaultForecastRows;
    NSInteger actualRows = MIN(forecastRows, (NSInteger)forecast.count);
    if (actualRows < 1) actualRows = 1;
    self.forecastHeightConstraint.constant = kForecastRowHeight * actualRows;

    NSDateFormatter *dayFormatter = [[NSDateFormatter alloc] init];
    // Pin to UTC: forecast datetimes are ISO 8601 with an explicit UTC
    // offset (see -[HAWeatherHelper fetchForecastForEntity:...] and the
    // matching test fixture), so formatting in the device's local time zone
    // could shift a near-midnight forecast entry onto the wrong weekday
    // depending on where the device/simulator is. Locale is left as the
    // device default so the weekday abbreviation still localizes normally;
    // only the time zone (which affects correctness, not language) is fixed.
    dayFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    [dayFormatter setDateFormat:@"EEE"];

    NSString *unit = [entity weatherTemperatureUnit] ?: @"°";
    NSString *tempFormat = self.roundTemperature ? @"%.0f%@" : @"%.1f%@";
    UIFont *textFont = [UIFont systemFontOfSize:11];
    UIFont *iconFont = [HAIconMapper mdiFontOfSize:14];
    UIColor *textColor = [HATheme secondaryTextColor];
    CGFloat rowHeight = 24.0;
    CGFloat rowY = 0;

    NSInteger count = MIN(forecastRows, (NSInteger)forecast.count);
    for (NSInteger i = 0; i < count; i++) {
        NSDictionary *day = forecast[i];
        if (![day isKindOfClass:[NSDictionary class]]) continue;

        // Parse day name from datetime
        NSString *dayName = @"";
        NSString *dateStr = day[@"datetime"];
        if ([dateStr isKindOfClass:[NSString class]]) {
            NSDate *date = [HADateUtils dateFromISO8601String:dateStr];
            if (date) dayName = [dayFormatter stringFromDate:date];
        }

        NSNumber *tempLow = day[@"templow"];
        NSNumber *tempHigh = day[@"temperature"];
        NSString *dayCondition = day[@"condition"];
        NSString *mdiName = [HAWeatherHelper mdiIconNameForCondition:dayCondition];
        NSString *dayGlyph = [HAIconMapper glyphForIconName:mdiName];

        // Layout: [Day 30pt] [Icon 20pt] [gap 4pt] [High temp 36pt] [/] [Low temp 36pt]
        CGFloat x = 0;
        CGFloat fullWidth = self.forecastContainer.bounds.size.width;
        if (fullWidth <= 0) fullWidth = 280; // fallback before layout pass

        // Day name label
        UILabel *dayLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, rowY, 30, rowHeight)];
        dayLabel.text = dayName;
        dayLabel.font = textFont;
        dayLabel.textColor = textColor;
        dayLabel.textAlignment = NSTextAlignmentLeft;
        [self.forecastContainer addSubview:dayLabel];
        x += 30;

        // Weather icon
        UILabel *iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, rowY, 20, rowHeight)];
        iconLabel.text = dayGlyph ?: @"?";
        iconLabel.font = dayGlyph ? iconFont : textFont;
        iconLabel.textColor = textColor;
        iconLabel.textAlignment = NSTextAlignmentCenter;
        [self.forecastContainer addSubview:iconLabel];
        x += 24;

        // High temp
        NSString *highStr = tempHigh ? [NSString stringWithFormat:tempFormat, tempHigh.doubleValue, unit] : @"";
        UILabel *highLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, rowY, 36, rowHeight)];
        highLabel.text = highStr;
        highLabel.font = textFont;
        highLabel.textColor = [HATheme primaryTextColor];
        highLabel.textAlignment = NSTextAlignmentRight;
        [self.forecastContainer addSubview:highLabel];
        x += 38;

        // Separator
        UILabel *sepLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, rowY, 10, rowHeight)];
        sepLabel.text = @"/";
        sepLabel.font = textFont;
        sepLabel.textColor = textColor;
        sepLabel.textAlignment = NSTextAlignmentCenter;
        [self.forecastContainer addSubview:sepLabel];
        x += 10;

        // Low temp
        NSString *lowStr = tempLow ? [NSString stringWithFormat:tempFormat, tempLow.doubleValue, unit] : @"";
        UILabel *lowLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, rowY, 36, rowHeight)];
        lowLabel.text = lowStr;
        lowLabel.font = textFont;
        lowLabel.textColor = textColor;
        lowLabel.textAlignment = NSTextAlignmentLeft;
        [self.forecastContainer addSubview:lowLabel];

        rowY += rowHeight + 2;
    }
}

#pragma mark - Reuse

- (void)prepareForReuse {
    [super prepareForReuse];
    self.conditionSymbol.text = nil;
    self.conditionSymbol.hidden = NO;
    self.tempLabel.text = nil;
    self.tempLabel.hidden = NO;
    self.detailsLabel.text = nil;
    self.detailsLabel.hidden = NO;
    self.forecastTopWhenCurrentShown.active = YES;
    self.forecastTopWhenCurrentHidden.active = NO;
    self.forecastSectionEnabled = NO;
    self.forecastType = nil;
    self.secondaryInfoAttribute = nil;
    for (UIView *v in self.forecastContainer.subviews) [v removeFromSuperview];
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.tempLabel.textColor = [HATheme primaryTextColor];
    self.detailsLabel.textColor = [HATheme secondaryTextColor];
}

@end
