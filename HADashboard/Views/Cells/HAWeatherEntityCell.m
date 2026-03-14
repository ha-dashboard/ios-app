#import "HAAutoLayout.h"
#import "HAWeatherEntityCell.h"
#import "HADateUtils.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HAConnectionManager.h"
#import "HAWeatherHelper.h"
#import "UIFont+HACompat.h"

/// Height for the top section: name + condition symbol + temp + details
static const CGFloat kTopContentHeight = 90.0;
/// Gap between top content and forecast strip
static const CGFloat kForecastGap = 6.0;
/// Per-row height for forecast (24pt row + 2pt gap)
static const CGFloat kForecastRowHeight = 26.0;
/// Bottom padding below forecast
static const CGFloat kBottomPadding = 10.0;
/// Number of forecast rows
static const NSInteger kDefaultForecastRows = 5;

@interface HAWeatherEntityCell ()
@property (nonatomic, strong) UILabel *conditionSymbol;
@property (nonatomic, strong) UILabel *tempLabel;
@property (nonatomic, strong) UILabel *detailsLabel;
@property (nonatomic, strong) UIView *forecastContainer;
@property (nonatomic, strong) NSLayoutConstraint *forecastHeightConstraint;
@end

@implementation HAWeatherEntityCell

+ (CGFloat)preferredHeight {
    CGFloat forecastHeight = kForecastRowHeight * kDefaultForecastRows;
    return kTopContentHeight + kForecastGap + forecastHeight + kBottomPadding;
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
    self.tempLabel.font = [UIFont ha_monospacedDigitSystemFontOfSize:28 weight:HAFontWeightLight];
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
    [self.contentView addSubview:self.forecastContainer];

    // Symbol: left side, below name
    HAActivateConstraints(@[
        HACon([self.conditionSymbol.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]),
        HACon([self.conditionSymbol.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2]),
    ]);

    // Temp: right of symbol
    HAActivateConstraints(@[
        HACon([self.tempLabel.leadingAnchor constraintEqualToAnchor:self.conditionSymbol.trailingAnchor constant:8]),
        HACon([self.tempLabel.centerYAnchor constraintEqualToAnchor:self.conditionSymbol.centerYAnchor]),
    ]);

    // Details: below condition symbol, single line
    HAActivateConstraints(@[
        HACon([self.detailsLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]),
        HACon([self.detailsLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding]),
        HACon([self.detailsLabel.topAnchor constraintEqualToAnchor:self.conditionSymbol.bottomAnchor constant:4]),
    ]);

    // Forecast container: below details, pinned leading/trailing/bottom
    self.forecastHeightConstraint = HAMakeConstraint([self.forecastContainer.heightAnchor constraintEqualToConstant:kForecastRowHeight * kDefaultForecastRows]);
    HAActivateConstraints(@[
        HACon([self.forecastContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]),
        HACon([self.forecastContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding]),
        HACon([self.forecastContainer.topAnchor constraintGreaterThanOrEqualToAnchor:self.detailsLabel.bottomAnchor constant:kForecastGap]),
        HACon([self.forecastContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-kBottomPadding]),
        HACon(self.forecastHeightConstraint),
    ]);
}

#pragma mark - Configure

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    NSString *condition = [entity weatherCondition];
    self.conditionSymbol.text = [HAEntity symbolForWeatherCondition:condition];

    NSNumber *temp = [entity weatherTemperature];
    NSString *unit = [entity weatherTemperatureUnit];
    if (temp) {
        self.tempLabel.text = [NSString stringWithFormat:@"%.0f%@", temp.doubleValue, unit];
    } else {
        self.tempLabel.text = @"\u2014";
    }

    // Build details string
    NSMutableArray *details = [NSMutableArray array];

    NSNumber *humidity = [entity weatherHumidity];
    if (humidity) {
        [details addObject:[NSString stringWithFormat:@"Humidity: %.0f%%", humidity.doubleValue]];
    }

    NSNumber *wind = [entity weatherWindSpeed];
    NSString *bearing = [entity weatherWindBearing];
    if (wind) {
        if (bearing) {
            [details addObject:[NSString stringWithFormat:@"Wind: %.0f %@", wind.doubleValue, bearing]];
        } else {
            [details addObject:[NSString stringWithFormat:@"Wind: %.0f", wind.doubleValue]];
        }
    }

    NSNumber *pressure = [entity weatherPressure];
    if (pressure) {
        [details addObject:[NSString stringWithFormat:@"Pressure: %.0f", pressure.doubleValue]];
    }

    NSNumber *visibility = HAAttrNumber(entity.attributes, @"visibility");
    if (visibility) {
        [details addObject:[NSString stringWithFormat:@"Vis: %.0f", visibility.doubleValue]];
    }

    NSNumber *uvIndex = HAAttrNumber(entity.attributes, @"uv_index");
    if (uvIndex) {
        [details addObject:[NSString stringWithFormat:@"UV: %.0f", uvIndex.doubleValue]];
    }

    NSNumber *precipitation = HAAttrNumber(entity.attributes, @"precipitation");
    if (precipitation) {
        [details addObject:[NSString stringWithFormat:@"Precip: %.1f", precipitation.doubleValue]];
    }

    NSNumber *dewPoint = HAAttrNumber(entity.attributes, @"dew_point");
    if (dewPoint) {
        [details addObject:[NSString stringWithFormat:@"Dew: %.0f°", dewPoint.doubleValue]];
    }

    NSNumber *cloudCoverage = HAAttrNumber(entity.attributes, @"cloud_coverage");
    if (cloudCoverage) {
        [details addObject:[NSString stringWithFormat:@"Cloud: %.0f%%", cloudCoverage.doubleValue]];
    }

    self.detailsLabel.text = [details componentsJoinedByString:@"  \u00B7  "];

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

    // Fetch and render forecast
    if (entity) {
        [self fetchForecastForEntity:entity];
    }
}

#pragma mark - Forecast Fetch

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

#pragma mark - Forecast Rendering

- (void)renderForecast:(NSArray *)forecast entity:(HAEntity *)entity {
    // Clear existing forecast content
    for (UIView *v in self.forecastContainer.subviews) [v removeFromSuperview];

    NSInteger forecastRows = kDefaultForecastRows;
    NSInteger actualRows = MIN(forecastRows, (NSInteger)forecast.count);
    if (actualRows < 1) actualRows = 1;
    self.forecastHeightConstraint.constant = kForecastRowHeight * actualRows;

    NSDateFormatter *dayFormatter = [[NSDateFormatter alloc] init];
    [dayFormatter setDateFormat:@"EEE"];

    NSString *unit = [entity weatherTemperatureUnit] ?: @"\u00B0";
    UIFont *textFont = [UIFont systemFontOfSize:11];
    CGFloat iconFontSize = 14;
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
        if (dayGlyph) {
            iconLabel.attributedText = [HAIconMapper attributedGlyph:dayGlyph fontSize:iconFontSize color:textColor];
        } else {
            iconLabel.text = @"?";
            iconLabel.font = textFont;
            iconLabel.textColor = textColor;
        }
        iconLabel.textAlignment = NSTextAlignmentCenter;
        [self.forecastContainer addSubview:iconLabel];
        x += 24;

        // High temp
        NSString *highStr = tempHigh ? [NSString stringWithFormat:@"%.0f%@", tempHigh.doubleValue, unit] : @"";
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
        NSString *lowStr = tempLow ? [NSString stringWithFormat:@"%.0f%@", tempLow.doubleValue, unit] : @"";
        UILabel *lowLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, rowY, 36, rowHeight)];
        lowLabel.text = lowStr;
        lowLabel.font = textFont;
        lowLabel.textColor = textColor;
        lowLabel.textAlignment = NSTextAlignmentLeft;
        [self.forecastContainer addSubview:lowLabel];

        rowY += rowHeight + 2;
    }
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat padding = 10.0;

        // Condition symbol: below name, left
        CGSize symSize = [self.conditionSymbol sizeThatFits:CGSizeMake(50, CGFLOAT_MAX)];
        self.conditionSymbol.frame = CGRectMake(padding, CGRectGetMaxY(self.nameLabel.frame) + 2, symSize.width, symSize.height);

        // Temp: right of symbol, vertically centered
        CGSize tempSize = [self.tempLabel sizeThatFits:CGSizeMake(100, CGFLOAT_MAX)];
        self.tempLabel.frame = CGRectMake(CGRectGetMaxX(self.conditionSymbol.frame) + 8,
                                          self.conditionSymbol.frame.origin.y + (symSize.height - tempSize.height) / 2.0,
                                          tempSize.width, tempSize.height);

        // Details: below condition symbol
        CGSize detSize = [self.detailsLabel sizeThatFits:CGSizeMake(w - padding * 2, CGFLOAT_MAX)];
        self.detailsLabel.frame = CGRectMake(padding, CGRectGetMaxY(self.conditionSymbol.frame) + 4, w - padding * 2, detSize.height);

        // Forecast container: bottom area
        CGFloat forecastH = kForecastRowHeight * kDefaultForecastRows;
        self.forecastContainer.frame = CGRectMake(padding, h - kBottomPadding - forecastH, w - padding * 2, forecastH);
    }
}

#pragma mark - Reuse

- (void)prepareForReuse {
    [super prepareForReuse];
    self.conditionSymbol.text = nil;
    self.tempLabel.text = nil;
    self.detailsLabel.text = nil;
    for (UIView *v in self.forecastContainer.subviews) [v removeFromSuperview];
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.tempLabel.textColor = [HATheme primaryTextColor];
    self.detailsLabel.textColor = [HATheme secondaryTextColor];
}

@end
