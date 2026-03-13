#import "HAAutoLayout.h"
#import "HAGaugeCardCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAEntityDisplayHelper.h"
#import "UIFont+HACompat.h"

// Gauge geometry
static const CGFloat kGaugeArcLineWidth = 10.0;
static const CGFloat kGaugePadding      = 6.0;
static const CGFloat kGaugeCellHeight   = 140.0;

// Arc angles: semicircle from left (π) to right (2π), drawn clockwise through the top.
// In UIKit (Y-down), clockwise:YES sweeps visually clockwise: left → top → right.
static const CGFloat kGaugeStartAngle = M_PI;       // 9 o'clock (left)
static const CGFloat kGaugeEndAngle   = 2.0 * M_PI; // 3 o'clock (right)

@interface HAGaugeCardCell () {
    CGSize _lastLayoutSize;
}
@property (nonatomic, strong) CAShapeLayer *trackLayer;
@property (nonatomic, strong) CAShapeLayer *fillLayer;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) NSLayoutConstraint *valueLabelTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *valueLabelWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *nameLabelTopConstraint;
@property (nonatomic, weak)   HAEntity *entity;
@property (nonatomic, strong) HADashboardConfigItem *configItem;
@end

@implementation HAGaugeCardCell

+ (CGFloat)preferredHeight {
    return kGaugeCellHeight;
}

+ (CGFloat)preferredHeightForWidth:(CGFloat)width {
    // Compute height to tightly fit the arc + name label with no top gap.
    // radius is constrained by width: (width - 2*padding - lineWidth) / 2
    // Cap radius at 80pt so full-width gauges don't become excessively tall.
    CGFloat maxRadius = (width - kGaugePadding * 2 - kGaugeArcLineWidth) / 2.0;
    maxRadius = MIN(MAX(maxRadius, 20.0), 80.0);
    CGFloat nameLabelSpace = 16.0;
    // height = top padding + lineWidth/2 + radius (arc top to center) + nameLabel + bottom pad
    return kGaugePadding + kGaugeArcLineWidth / 2.0 + maxRadius + nameLabelSpace + 2.0;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
        self.contentView.layer.cornerRadius = 14.0;
        self.contentView.clipsToBounds = YES;

        // Value label (centered inside arc, auto-sizes for narrow cards)
        self.valueLabel = [[UILabel alloc] init];
        self.valueLabel.font = [UIFont ha_monospacedDigitSystemFontOfSize:20 weight:HAFontWeightBold];
        self.valueLabel.textColor = [HATheme primaryTextColor];
        self.valueLabel.textAlignment = NSTextAlignmentCenter;
        self.valueLabel.adjustsFontSizeToFitWidth = YES;
        self.valueLabel.minimumScaleFactor = 0.4;
        self.valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.valueLabel];

        // Name label (smaller, below value)
        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.font = [UIFont ha_systemFontOfSize:13 weight:HAFontWeightRegular];
        self.nameLabel.textColor = [HATheme secondaryTextColor];
        self.nameLabel.textAlignment = NSTextAlignmentCenter;
        self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.nameLabel];

        // Horizontal centering only; vertical positions are managed dynamically
        // in -updateGaugeArc based on computed arc geometry.
        HAActivateConstraints(@[
            HACon([self.valueLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor]),
            HACon([self.valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:kGaugePadding]),
            HACon([self.valueLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-kGaugePadding]),
            HACon([self.nameLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor]),
            HACon([self.nameLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:kGaugePadding]),
            HACon([self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-kGaugePadding]),
        ]);
    }
    return self;
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat cellW = self.contentView.bounds.size.width;
        CGFloat cellH = self.contentView.bounds.size.height;
        if (cellW > 0 && cellH > 0) {
            // Position value and name labels manually (constraints not available)
            CGFloat maxRadius = (cellW - kGaugePadding * 2 - kGaugeArcLineWidth) / 2.0;
            maxRadius = MIN(MAX(maxRadius, 20.0), 80.0);
            CGFloat centerY = kGaugePadding + maxRadius + kGaugeArcLineWidth / 2.0;

            CGSize valSize = [self.valueLabel sizeThatFits:CGSizeMake(cellW - kGaugePadding * 2, CGFLOAT_MAX)];
            CGFloat valueLabelY = centerY - maxRadius * 0.45;
            self.valueLabel.frame = CGRectMake((cellW - valSize.width) / 2.0, valueLabelY, valSize.width, valSize.height);

            CGSize nameSize = [self.nameLabel sizeThatFits:CGSizeMake(cellW - kGaugePadding * 2, CGFLOAT_MAX)];
            self.nameLabel.frame = CGRectMake((cellW - nameSize.width) / 2.0, centerY + 2, nameSize.width, nameSize.height);
        }
    }
    CGSize newSize = self.contentView.bounds.size;
    if (!CGSizeEqualToSize(newSize, _lastLayoutSize)) {
        _lastLayoutSize = newSize;
        [self updateGaugeArc];
    }
}

- (void)updateGaugeArc {
    CGFloat cellW = self.contentView.bounds.size.width;
    CGFloat cellH = self.contentView.bounds.size.height;
    if (cellW <= 0 || cellH <= 0) return;

    // Remove old layers
    [self.trackLayer removeFromSuperlayer];
    [self.fillLayer removeFromSuperlayer];

    // Arc geometry: anchor from the TOP so there's no dead space above the arc.
    // The semicircle center (baseline) = top padding + radius + half line width.
    // Name label sits below the arc baseline.
    CGFloat nameLabelSpace = 16.0;
    CGFloat maxRadiusByWidth  = (cellW - kGaugePadding * 2 - kGaugeArcLineWidth) / 2.0;
    CGFloat maxRadiusByHeight = cellH - kGaugePadding - kGaugeArcLineWidth / 2.0 - nameLabelSpace - 2.0;
    CGFloat radius = MIN(maxRadiusByWidth, maxRadiusByHeight);
    radius = MIN(MAX(radius, 20.0), 80.0);

    CGFloat centerX = cellW / 2.0;
    CGFloat centerY = kGaugePadding + radius + kGaugeArcLineWidth / 2.0;

    // Value label: visually centered inside the semicircle bowl
    CGFloat valueLabelY = centerY - radius * 0.45;
    if (self.valueLabelTopConstraint) {
        self.valueLabelTopConstraint.constant = valueLabelY;
    } else {
        self.valueLabelTopConstraint = HAMakeConstraint([self.valueLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:valueLabelY]);
        HASetConstraintActive(self.valueLabelTopConstraint, YES);
    }

    // Constrain value label width to the arc's inner chord at the label's vertical position.
    // This ensures text scales down to fit INSIDE the arc, not extend beyond it.
    CGFloat innerRadius = radius - kGaugeArcLineWidth / 2.0;
    CGFloat labelOffsetY = radius * 0.45; // distance from center to label center
    CGFloat chordHalf = sqrt(MAX(0, innerRadius * innerRadius - labelOffsetY * labelOffsetY));
    CGFloat maxLabelWidth = chordHalf * 2.0 - 4.0; // 4pt breathing room
    if (maxLabelWidth < 20) maxLabelWidth = 20;
    if (self.valueLabelWidthConstraint) {
        self.valueLabelWidthConstraint.constant = maxLabelWidth;
    } else {
        self.valueLabelWidthConstraint = HAMakeConstraint([self.valueLabel.widthAnchor constraintLessThanOrEqualToConstant:maxLabelWidth]);
        HASetConstraintActive(self.valueLabelWidthConstraint, YES);
    }

    // Name label just below the arc baseline
    CGFloat nameLabelY = centerY + 2.0;
    if (self.nameLabelTopConstraint) {
        self.nameLabelTopConstraint.constant = nameLabelY;
    } else {
        self.nameLabelTopConstraint = HAMakeConstraint([self.nameLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:nameLabelY]);
        HASetConstraintActive(self.nameLabelTopConstraint, YES);
    }

    CGPoint center = CGPointMake(centerX, centerY);

    // Background track (full semicircle, grey)
    UIBezierPath *trackPath = [UIBezierPath bezierPathWithArcCenter:center
                                                              radius:radius
                                                          startAngle:kGaugeStartAngle
                                                            endAngle:kGaugeEndAngle
                                                           clockwise:YES];
    self.trackLayer = [CAShapeLayer layer];
    self.trackLayer.path = trackPath.CGPath;
    self.trackLayer.fillColor = [UIColor clearColor].CGColor;
    UIColor *trackColor;
    if (@available(iOS 13.0, *)) {
        trackColor = [UIColor labelColor];
    } else {
        trackColor = [UIColor darkGrayColor];
    }
    self.trackLayer.strokeColor = [trackColor colorWithAlphaComponent:0.15].CGColor;
    self.trackLayer.lineWidth = kGaugeArcLineWidth;
    self.trackLayer.lineCap = kCALineCapRound;
    [self.contentView.layer insertSublayer:self.trackLayer atIndex:0];

    // Filled arc (proportional to value)
    CGFloat fillProportion = [self currentFillProportion];
    UIColor *fillColor = [self currentFillColor] ?: [UIColor orangeColor];

    UIBezierPath *fillPath = [UIBezierPath bezierPathWithArcCenter:center
                                                             radius:radius
                                                         startAngle:kGaugeStartAngle
                                                           endAngle:kGaugeEndAngle
                                                          clockwise:YES];
    self.fillLayer = [CAShapeLayer layer];
    self.fillLayer.path = fillPath.CGPath;
    self.fillLayer.fillColor = [UIColor clearColor].CGColor;
    self.fillLayer.strokeColor = fillColor.CGColor;
    self.fillLayer.lineWidth = kGaugeArcLineWidth;
    self.fillLayer.lineCap = kCALineCapRound;
    self.fillLayer.strokeStart = 0.0;
    self.fillLayer.strokeEnd = fillProportion;
    [self.contentView.layer insertSublayer:self.fillLayer above:self.trackLayer];
}

#pragma mark - Configuration

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    self.entity = entity;
    self.configItem = configItem;

    self.contentView.backgroundColor = [HATheme cellBackgroundColor];

    // Display name
    NSString *name = [HAEntityDisplayHelper displayNameForEntity:entity
                                                     configItem:configItem
                                                   nameOverride:nil];
    self.nameLabel.text = name;
    self.nameLabel.textColor = [HATheme secondaryTextColor];

    // Value text with unit
    NSString *stateStr = entity.state;
    BOOL isNumeric = [self isNumericString:stateStr];

    if (isNumeric) {
        double value = [stateStr doubleValue];
        NSString *unit = configItem.customProperties[@"unit"] ?: [entity unitOfMeasurement];

        // Format value: use 0 decimals for integers, 1 for others
        NSString *formattedValue;
        if (value == floor(value)) {
            formattedValue = [HAEntityDisplayHelper formattedNumberString:value decimals:0];
        } else {
            formattedValue = [HAEntityDisplayHelper formattedNumberString:value decimals:1];
        }

        if (unit.length > 0) {
            self.valueLabel.text = [NSString stringWithFormat:@"%@ %@", formattedValue, unit];
        } else {
            self.valueLabel.text = formattedValue;
        }
    } else {
        self.valueLabel.text = [HAEntityDisplayHelper humanReadableState:stateStr] ?: @"--";
    }
    self.valueLabel.textColor = [HATheme primaryTextColor];

    // Force layout update for arc rendering
    [self setNeedsLayout];
}

#pragma mark - Gauge Calculations

- (CGFloat)currentFillProportion {
    if (!self.entity) return 0.0;

    NSString *stateStr = self.entity.state;
    if (![self isNumericString:stateStr]) return 0.0;

    double value = [stateStr doubleValue];

    // Get min/max from card config, falling back to entity attributes, then defaults
    double minVal = [self gaugeMinValue];
    double maxVal = [self gaugeMaxValue];

    if (maxVal <= minVal) return 0.0;

    CGFloat proportion = (CGFloat)((value - minVal) / (maxVal - minVal));
    return MAX(0.0, MIN(1.0, proportion));
}

- (double)gaugeMinValue {
    NSDictionary *props = self.configItem.customProperties;
    if (props[@"gauge_min"]) return [props[@"gauge_min"] doubleValue];
    return HAAttrDouble(self.entity.attributes, HAAttrMin, 0.0);
}

- (double)gaugeMaxValue {
    NSDictionary *props = self.configItem.customProperties;
    if (props[@"gauge_max"]) return [props[@"gauge_max"] doubleValue];
    return HAAttrDouble(self.entity.attributes, HAAttrMax, 100.0);
}

- (UIColor *)currentFillColor {
    if (!self.entity) return [HATheme accentColor];

    NSString *stateStr = self.entity.state;
    if (![self isNumericString:stateStr]) return [HATheme accentColor];

    double value = [stateStr doubleValue];

    // Check severity thresholds from card config (array format, converted from dict by parser)
    NSArray *severity = self.configItem.customProperties[@"severity"];
    if ([severity isKindOfClass:[NSArray class]] && severity.count > 0) {
        UIColor *color = [self colorForValue:value severity:severity];
        if (color) return color;
    }

    // Check for a card-level color override
    NSString *colorOverride = self.configItem.customProperties[@"color"];
    if (colorOverride.length > 0) {
        UIColor *parsed = [self parseColorString:colorOverride];
        if (parsed) return parsed;
    }

    // Default: value-position-based gradient (matching HA gauge behavior)
    CGFloat proportion = [self currentFillProportion];
    if (proportion < 0.35) {
        return [UIColor colorWithRed:0.30 green:0.69 blue:0.31 alpha:1.0]; // Green
    } else if (proportion < 0.70) {
        return [UIColor colorWithRed:1.00 green:0.76 blue:0.03 alpha:1.0]; // Yellow/amber
    }
    return [UIColor colorWithRed:0.90 green:0.23 blue:0.20 alpha:1.0]; // Red
}

/// Walk the severity array to find which color applies to the current value.
/// HA severity format: [{from: 0, to: 50, color: "green"}, {from: 50, to: 75, color: "yellow"}, ...]
- (UIColor *)colorForValue:(double)value severity:(NSArray *)severity {
    for (NSDictionary *entry in severity) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;

        double from = [entry[@"from"] doubleValue];
        double to = [entry[@"to"] doubleValue];

        if (value >= from && value < to) {
            NSString *colorStr = entry[@"color"];
            if (![colorStr isKindOfClass:[NSString class]]) continue;
            return [self parseColorString:colorStr];
        }
    }

    // If value equals the max "to" boundary of the last segment, match it
    if (severity.count > 0) {
        NSDictionary *last = severity.lastObject;
        if ([last isKindOfClass:[NSDictionary class]]) {
            double to = [last[@"to"] doubleValue];
            if (value >= to) {
                NSString *colorStr = last[@"color"];
                if ([colorStr isKindOfClass:[NSString class]]) {
                    return [self parseColorString:colorStr];
                }
            }
        }
    }

    return nil;
}

/// Parse a color string: supports named HA colors (green, yellow, red, etc.) and hex (#RRGGBB).
/// Named colors are checked FIRST because colorFromHex: will mis-parse color names like "yellow"
/// (6 chars) as hex values, producing near-black colors.
- (UIColor *)parseColorString:(NSString *)colorStr {
    if (!colorStr || colorStr.length == 0) return nil;

    // Named color mapping (matching HA's gauge severity names) — must come before hex
    NSString *lower = [colorStr lowercaseString];
    if ([lower isEqualToString:@"green"])  return [UIColor colorWithRed:0.30 green:0.69 blue:0.31 alpha:1.0];
    if ([lower isEqualToString:@"yellow"]) return [UIColor colorWithRed:1.00 green:0.76 blue:0.03 alpha:1.0];
    if ([lower isEqualToString:@"red"])    return [UIColor colorWithRed:0.90 green:0.23 blue:0.20 alpha:1.0];
    if ([lower isEqualToString:@"orange"]) return [UIColor colorWithRed:1.00 green:0.60 blue:0.00 alpha:1.0];
    if ([lower isEqualToString:@"blue"])   return [UIColor colorWithRed:0.13 green:0.59 blue:0.95 alpha:1.0];
    if ([lower isEqualToString:@"purple"]) return [UIColor colorWithRed:0.61 green:0.15 blue:0.69 alpha:1.0];
    if ([lower isEqualToString:@"teal"])   return [UIColor colorWithRed:0.00 green:0.59 blue:0.53 alpha:1.0];
    if ([lower isEqualToString:@"grey"] || [lower isEqualToString:@"gray"]) return [HATheme secondaryTextColor];

    // Hex (#RRGGBB or RRGGBB)
    UIColor *hexColor = [HATheme colorFromHex:colorStr];
    if (hexColor) return hexColor;

    return nil;
}

#pragma mark - Helpers

- (BOOL)isNumericString:(NSString *)str {
    if (!str || str.length == 0) return NO;
    if ([str isEqualToString:@"unavailable"] ||
        [str isEqualToString:@"unknown"] ||
        [str isEqualToString:@"on"] ||
        [str isEqualToString:@"off"]) {
        return NO;
    }
    NSScanner *scanner = [NSScanner scannerWithString:str];
    double value;
    return [scanner scanDouble:&value] && [scanner isAtEnd];
}

#pragma mark - Reuse

- (void)prepareForReuse {
    [super prepareForReuse];
    _lastLayoutSize = CGSizeZero;
    self.valueLabel.text = nil;
    self.nameLabel.text = nil;
    self.entity = nil;
    self.configItem = nil;
    [self.trackLayer removeFromSuperlayer];
    [self.fillLayer removeFromSuperlayer];
    self.trackLayer = nil;
    self.fillLayer = nil;
    // Reset dynamic vertical constraints so they are re-created on next layout.
    if (self.valueLabelTopConstraint) {
        HASetConstraintActive(self.valueLabelTopConstraint, NO);
        self.valueLabelTopConstraint = nil;
    }
    if (self.nameLabelTopConstraint) {
        HASetConstraintActive(self.nameLabelTopConstraint, NO);
        self.nameLabelTopConstraint = nil;
    }
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.valueLabel.textColor = [HATheme primaryTextColor];
    self.nameLabel.textColor = [HATheme secondaryTextColor];
}

@end
