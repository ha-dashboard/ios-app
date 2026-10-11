#import "HAClockCardCell.h"
#import "HAClockCardFormatter.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import <QuartzCore/QuartzCore.h>
#import <sys/utsname.h>

// Metrics below are ported from the HA frontend CSS (hui-clock-card.ts,
// hui-clock-card-digital.ts, hui-clock-card-analog.ts) using HA's font-size
// tokens: xs 10, s 12, m 14, l 16, xl 20, 2xl 24.

typedef NS_ENUM(NSInteger, HAClockSize) {
    HAClockSizeUnset = 0, // no clock_size: renders like small
    HAClockSizeSmall,
    HAClockSizeMedium,
    HAClockSizeLarge,
};

typedef NS_ENUM(NSInteger, HAClockTicks) {
    HAClockTicksHour = 0, // HA default
    HAClockTicksNone,
    HAClockTicksQuarter,
    HAClockTicksMinute,
};

typedef NS_ENUM(NSInteger, HAClockFace) {
    HAClockFaceMarkers = 0, // also the rendering for an unset face_style
    HAClockFaceNumbers,
    HAClockFaceRoman,
};

static const CGFloat kCardCornerRadius = 14.0; // HABaseEntityCell's card radius
static const CGFloat kDigitalDateGap = 4.0;    // .date-container margin-top: var(--ha-space-1)
static const CGFloat kTitleLineHeight = 1.2;   // --ha-line-height-condensed

static HAClockSize HAClockSizeFromValue(id value) {
    if (![value isKindOfClass:[NSString class]]) return HAClockSizeUnset;
    if ([value isEqualToString:@"small"]) return HAClockSizeSmall;
    if ([value isEqualToString:@"medium"]) return HAClockSizeMedium;
    if ([value isEqualToString:@"large"]) return HAClockSizeLarge;
    return HAClockSizeUnset;
}

static BOOL HAClockSizeIsRoomy(HAClockSize size) {
    return size == HAClockSizeMedium || size == HAClockSizeLarge;
}

static CGFloat HAClockVerticalPadding(HAClockSize size)   { return HAClockSizeIsRoomy(size) ? 16.0 : 6.0; }
static CGFloat HAClockHorizontalPadding(HAClockSize size) { return HAClockSizeIsRoomy(size) ? 16.0 : 8.0; }
static CGFloat HAClockRowGap(HAClockSize size)            { return HAClockSizeIsRoomy(size) ? 12.0 : 6.0; }

static CGFloat HAClockTitleFontSize(HAClockSize size) {
    switch (size) {
        case HAClockSizeLarge:  return 24.0;
        case HAClockSizeMedium: return 16.0;
        default:                return 14.0;
    }
}

static CGFloat HAClockDigitalTimeFontSize(HAClockSize size) {
    switch (size) {
        case HAClockSizeLarge:  return 64.0;
        case HAClockSizeMedium: return 48.0;
        default:                return 24.0;
    }
}

static CGFloat HAClockDigitalSuffixFontSize(HAClockSize size) {
    switch (size) {
        case HAClockSizeLarge:  return 24.0;
        case HAClockSizeMedium: return 16.0;
        default:                return 10.0;
    }
}

static CGFloat HAClockDigitalSuffixMargin(HAClockSize size) {
    switch (size) {
        case HAClockSizeLarge:  return 8.0;
        case HAClockSizeMedium: return 6.0;
        default:                return 4.0;
    }
}

static CGFloat HAClockDigitalDateFontSize(HAClockSize size) {
    switch (size) {
        case HAClockSizeLarge:  return 24.0;
        case HAClockSizeMedium: return 16.0;
        default:                return 12.0;
    }
}

static CGFloat HAClockAnalogDiameter(HAClockSize size) {
    switch (size) {
        case HAClockSizeLarge:  return 220.0;
        case HAClockSizeMedium: return 160.0;
        default:                return 100.0;
    }
}

/// Digital time row height: the CSS grid uses line-height 0.8.
static CGFloat HAClockTimeRowHeight(HAClockSize size) {
    return ceil(HAClockDigitalTimeFontSize(size) * 0.8);
}

static UIFont *HAClockTitleFont(HAClockSize size) {
    return [UIFont systemFontOfSize:HAClockTitleFontSize(size)];
}

static UIFont *HAClockDigitalDateFont(HAClockSize size) {
    return [UIFont systemFontOfSize:HAClockDigitalDateFontSize(size)];
}

static NSUInteger HAClockLineCount(NSArray<NSString *> *dateParts) {
    NSUInteger lines = 1;
    for (NSString *part in dateParts) {
        if ([part isEqualToString:@"separator-new-line"]) lines++;
    }
    return lines;
}

/// iPad 2/3 class hardware (A5/A5X, armv7) — same list as HAGraphView /
/// HAPerfMonitor. On these the continuous second-hand sweep degrades to a
/// once-per-second tick and hand shadows are skipped.
static BOOL HAClockIsLightweightDevice(void) {
#if TARGET_OS_SIMULATOR
    return NO;
#else
    static BOOL lightweight = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct utsname systemInfo;
        if (uname(&systemInfo) == 0) {
            NSString *machine = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
            lightweight = ([machine hasPrefix:@"iPad2"] || [machine hasPrefix:@"iPad3"] ||
                           [machine hasPrefix:@"iPhone4"] || [machine hasPrefix:@"iPod5"]);
        }
    });
    return lightweight;
#endif
}

static UIColor *HAClockResolvedColor(UIColor *color, UITraitCollection *traits) {
    // @available alone misreports on RosettaSim legacy runtimes (see HATheme
    // +colorWithLight:dark:), so also check the selector exists.
    if (@available(iOS 13.0, *)) {
        if (traits && [color respondsToSelector:@selector(resolvedColorWithTraitCollection:)]) {
            return [color resolvedColorWithTraitCollection:traits];
        }
    }
    return color;
}

static NSString *HAClockRomanNumeral(NSInteger number) {
    static NSArray *numerals = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        numerals = @[@"", @"I", @"II", @"III", @"IV", @"V", @"VI", @"VII", @"VIII", @"IX", @"X", @"XI", @"XII"];
    });
    if (number < 1 || number > 12) return @"";
    return numerals[number];
}

#pragma mark - Weak timer proxy

/// NSTimer retains its target; targeting this proxy instead of the cell keeps
/// the timer from retaining the cell. iOS 9 has no block-based NSTimer API.
@interface HAClockTickProxy : NSObject
@property (nonatomic, weak) HAClockCardCell *cell;
@end

@interface HAClockCardCell ()
- (void)handleTick:(NSTimer *)timer;
@end

@implementation HAClockTickProxy
- (void)tick:(NSTimer *)timer {
    HAClockCardCell *cell = self.cell;
    if (cell) {
        [cell handleTick:timer];
    } else {
        [timer invalidate];
    }
}
@end

#pragma mark - Analog face

@interface HAClockAnalogFaceView : UIView
@property (nonatomic, assign) HAClockSize clockSize;
@property (nonatomic, assign) HAClockTicks ticks;
@property (nonatomic, assign) HAClockFace face;
@property (nonatomic, assign) BOOL uprightNumbers;
@property (nonatomic, assign) BOOL showsBorder;
@property (nonatomic, assign) BOOL showsSeconds;
@property (nonatomic, assign) BOOL longDate;
@property (nonatomic, assign) NSUInteger dateLineCount;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIColor *primaryColor;
@property (nonatomic, strong) UIColor *secondHandColor;
- (void)setNeedsGeometryUpdate;
- (void)setHourAngle:(CGFloat)hourAngle minuteAngle:(CGFloat)minuteAngle;
- (void)setSecondAngle:(CGFloat)angle sweepToAngle:(CGFloat)toAngle duration:(NSTimeInterval)duration;
- (void)stopSweep;
@end

@implementation HAClockAnalogFaceView {
    CAShapeLayer *_borderLayer;
    CAShapeLayer *_minuteTickLayer;
    CAShapeLayer *_hourTickLayer;
    UIView *_labelsView;
    NSMutableArray<UILabel *> *_numberLabels;
    CALayer *_hourHand;
    CALayer *_minuteHand;
    CALayer *_secondHand;
    CALayer *_centerDot;
    CGSize _geometrySize;
    BOOL _geometryDirty;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _primaryColor = [UIColor blackColor];
        _secondHandColor = [UIColor redColor];

        _borderLayer = [CAShapeLayer layer];
        _borderLayer.fillColor = [UIColor clearColor].CGColor;
        _borderLayer.lineWidth = 2.0;
        [self.layer addSublayer:_borderLayer];

        _minuteTickLayer = [CAShapeLayer layer];
        _minuteTickLayer.lineWidth = 1.0;
        _minuteTickLayer.opacity = 0.5;
        [self.layer addSublayer:_minuteTickLayer];

        _hourTickLayer = [CAShapeLayer layer];
        _hourTickLayer.lineWidth = 2.0;
        _hourTickLayer.opacity = 0.8;
        [self.layer addSublayer:_hourTickLayer];

        // Numbers and the date sit below the hands, like the HA z-order.
        _labelsView = [[UIView alloc] initWithFrame:self.bounds];
        _labelsView.userInteractionEnabled = NO;
        [self addSubview:_labelsView];
        _numberLabels = [NSMutableArray array];

        _dateLabel = [[UILabel alloc] init];
        _dateLabel.textAlignment = NSTextAlignmentCenter;
        _dateLabel.adjustsFontSizeToFitWidth = YES;
        _dateLabel.minimumScaleFactor = 0.5;
        _dateLabel.alpha = 0.8;
        [_labelsView addSubview:_dateLabel];

        // HA z-index: hour 1, second 2, center dot 3, minute 3 (later in DOM).
        _hourHand = [self handLayerWithWidth:4.0];
        _secondHand = [self handLayerWithWidth:2.0];
        _secondHand.opacity = 0.8;
        _centerDot = [CALayer layer];
        _centerDot.bounds = CGRectMake(0, 0, 8.0, 8.0);
        _centerDot.cornerRadius = 4.0;
        _minuteHand = [self handLayerWithWidth:3.0];
        _minuteHand.opacity = 0.9;
        [self.layer addSublayer:_hourHand];
        [self.layer addSublayer:_secondHand];
        [self.layer addSublayer:_centerDot];
        [self.layer addSublayer:_minuteHand];

        _geometryDirty = YES;
    }
    return self;
}

- (CALayer *)handLayerWithWidth:(CGFloat)width {
    CALayer *hand = [CALayer layer];
    hand.anchorPoint = CGPointMake(0.5, 1.0); // pivot at the dial centre
    hand.bounds = CGRectMake(0, 0, width, 0);
    hand.cornerRadius = 2.0;
    if (!HAClockIsLightweightDevice()) {
        hand.shadowColor = [UIColor blackColor].CGColor;
        hand.shadowOpacity = 0.2;
        hand.shadowRadius = 3.0;
        hand.shadowOffset = CGSizeZero;
    }
    return hand;
}

- (void)setNeedsGeometryUpdate {
    _geometryDirty = YES;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (_geometryDirty || !CGSizeEqualToSize(_geometrySize, self.bounds.size)) {
        [self updateGeometry];
        _geometrySize = self.bounds.size;
        _geometryDirty = NO;
    }
    [self applyColors];
    [CATransaction commit];
}

- (void)updateGeometry {
    CGSize boundsSize = self.bounds.size;
    CGFloat diameter = MIN(boundsSize.width, boundsSize.height);
    _labelsView.frame = self.bounds;
    if (diameter <= 0) return;

    CGPoint center = CGPointMake(boundsSize.width / 2.0, boundsSize.height / 2.0);
    // .dial-border is a 2px border with box-sizing: border-box; ticks are
    // absolutely positioned inside it.
    CGFloat inset = self.showsBorder ? 2.0 : 0.0;
    CGFloat outerRadius = diameter / 2.0 - inset;

    _borderLayer.hidden = !self.showsBorder;
    _borderLayer.path = [UIBezierPath bezierPathWithOvalInRect:
                         CGRectMake(center.x - diameter / 2.0 + 1.0, center.y - diameter / 2.0 + 1.0,
                                    diameter - 2.0, diameter - 2.0)].CGPath;

    NSInteger tickCount = 0;
    switch (self.ticks) {
        case HAClockTicksQuarter: tickCount = 4; break;
        case HAClockTicksHour:    tickCount = 12; break;
        case HAClockTicksMinute:  tickCount = 60; break;
        case HAClockTicksNone:    tickCount = 0; break;
    }
    BOOL withNumbers = (self.face != HAClockFaceMarkers);

    UIBezierPath *hourPath = [UIBezierPath bezierPath];
    UIBezierPath *minutePath = [UIBezierPath bezierPath];
    NSMutableArray<NSNumber *> *numberValues = [NSMutableArray array];
    NSMutableArray<NSNumber *> *numberAngles = [NSMutableArray array];

    for (NSInteger i = 0; i < tickCount; i++) {
        CGFloat angle = (CGFloat)i * 2.0 * M_PI / (CGFloat)tickCount;
        BOOL isHourTick = (self.ticks != HAClockTicksMinute) || (i % 5 == 0);
        CGFloat length = diameter * (isHourTick ? (withNumbers ? 0.03 : 0.07) : (withNumbers ? 0.015 : 0.04));
        CGFloat dx = sin(angle), dy = -cos(angle);
        UIBezierPath *path = isHourTick ? hourPath : minutePath;
        [path moveToPoint:CGPointMake(center.x + outerRadius * dx, center.y + outerRadius * dy)];
        [path addLineToPoint:CGPointMake(center.x + (outerRadius - length) * dx,
                                         center.y + (outerRadius - length) * dy)];

        if (isHourTick && withNumbers) {
            NSInteger number;
            if (self.ticks == HAClockTicksQuarter) {
                number = [@[@12, @3, @6, @9][i] integerValue];
            } else if (self.ticks == HAClockTicksMinute) {
                number = ((i / 5 + 11) % 12) + 1;
            } else {
                number = ((i + 11) % 12) + 1;
            }
            [numberValues addObject:@(number)];
            [numberAngles addObject:@(angle)];
        }
    }
    _hourTickLayer.path = hourPath.CGPath;
    _minuteTickLayer.path = minutePath.CGPath;

    // Numbers: centred on the tick's radial line, 35% of their own line box
    // below the dial edge (translate(-50%, 35%)), upright or rotated with the
    // tick (roman).
    CGFloat numberFontSize = (self.clockSize == HAClockSizeLarge) ? 16.0
                           : (self.clockSize == HAClockSizeMedium) ? 14.0 : 12.0;
    UIFont *numberFont = [UIFont systemFontOfSize:numberFontSize weight:UIFontWeightMedium];
    CGFloat numberBoxHeight = ceil(numberFontSize * kTitleLineHeight);
    CGFloat numberRadius = outerRadius - numberBoxHeight * 0.85;
    while (_numberLabels.count < numberValues.count) {
        UILabel *label = [[UILabel alloc] init];
        label.textAlignment = NSTextAlignmentCenter;
        [_labelsView insertSubview:label belowSubview:_dateLabel];
        [_numberLabels addObject:label];
    }
    for (NSUInteger i = 0; i < _numberLabels.count; i++) {
        UILabel *label = _numberLabels[i];
        if (i >= numberValues.count) {
            label.hidden = YES;
            continue;
        }
        NSInteger number = numberValues[i].integerValue;
        CGFloat angle = numberAngles[i].doubleValue;
        label.hidden = NO;
        label.font = numberFont;
        label.text = (self.face == HAClockFaceRoman) ? HAClockRomanNumeral(number) : [NSString stringWithFormat:@"%ld", (long)number];
        label.transform = CGAffineTransformIdentity;
        CGSize textSize = [label sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
        label.bounds = CGRectMake(0, 0, ceil(textSize.width), numberBoxHeight);
        label.center = CGPointMake(center.x + numberRadius * sin(angle), center.y - numberRadius * cos(angle));
        if (!self.uprightNumbers) label.transform = CGAffineTransformMakeRotation(angle);
    }

    // Date: centred at 68% of the dial (66% and 45% wide for a long date on a
    // small dial).
    BOOL compactLongDate = self.longDate && !HAClockSizeIsRoomy(self.clockSize);
    CGFloat dateFontSize = (self.clockSize == HAClockSizeLarge) ? 20.0
                         : (self.clockSize == HAClockSizeMedium) ? 16.0
                         : (compactLongDate ? 10.0 : 12.0);
    _dateLabel.font = [UIFont systemFontOfSize:dateFontSize weight:UIFontWeightMedium];
    NSUInteger lines = MAX(self.dateLineCount, (NSUInteger)1);
    _dateLabel.numberOfLines = lines;
    CGFloat dateHeight = ceil(_dateLabel.font.lineHeight * lines);
    CGFloat dateWidth = diameter * (compactLongDate ? 0.45 : 1.0);
    CGFloat dateCenterY = center.y - diameter / 2.0 + diameter * (compactLongDate ? 0.66 : 0.68);
    _dateLabel.frame = CGRectMake(center.x - dateWidth / 2.0, dateCenterY - dateHeight / 2.0, dateWidth, dateHeight);

    // Hands grow outward from the centre: hour 25%, minute 35%, second 42%.
    _hourHand.bounds = CGRectMake(0, 0, 4.0, diameter * 0.25);
    _minuteHand.bounds = CGRectMake(0, 0, 3.0, diameter * 0.35);
    _secondHand.bounds = CGRectMake(0, 0, 2.0, diameter * 0.42);
    for (CALayer *hand in @[_hourHand, _minuteHand, _secondHand]) {
        hand.position = center;
        if (hand.shadowOpacity > 0) {
            hand.shadowPath = [UIBezierPath bezierPathWithRoundedRect:hand.bounds cornerRadius:2.0].CGPath;
        }
    }
    _secondHand.hidden = !self.showsSeconds;
    _centerDot.position = center;
}

- (void)applyColors {
    UITraitCollection *traits = self.traitCollection;
    UIColor *primary = HAClockResolvedColor(self.primaryColor, traits);
    CGColorRef primaryCG = primary.CGColor;
    _borderLayer.strokeColor = [primary colorWithAlphaComponent:0.12].CGColor; // --divider-color
    _hourTickLayer.strokeColor = primaryCG;
    _minuteTickLayer.strokeColor = primaryCG;
    _hourHand.backgroundColor = primaryCG;
    _minuteHand.backgroundColor = primaryCG;
    _centerDot.backgroundColor = primaryCG;
    _secondHand.backgroundColor = HAClockResolvedColor(self.secondHandColor, traits).CGColor;
    for (UILabel *label in _numberLabels) label.textColor = self.primaryColor;
    _dateLabel.textColor = self.primaryColor;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self setNeedsLayout];
}

- (void)setHourAngle:(CGFloat)hourAngle minuteAngle:(CGFloat)minuteAngle {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _hourHand.affineTransform = CGAffineTransformMakeRotation(hourAngle);
    _minuteHand.affineTransform = CGAffineTransformMakeRotation(minuteAngle);
    [CATransaction commit];
}

- (void)setSecondAngle:(CGFloat)angle sweepToAngle:(CGFloat)toAngle duration:(NSTimeInterval)duration {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_secondHand removeAnimationForKey:@"sweep"];
    if (duration > 0) {
        // One render-server animation per second for the continuous sweep;
        // no per-frame work on the main thread.
        _secondHand.affineTransform = CGAffineTransformMakeRotation(toAngle);
        CABasicAnimation *sweep = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        sweep.fromValue = @(angle);
        sweep.toValue = @(toAngle);
        sweep.duration = duration;
        sweep.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        [_secondHand addAnimation:sweep forKey:@"sweep"];
    } else {
        _secondHand.affineTransform = CGAffineTransformMakeRotation(angle);
    }
    [CATransaction commit];
}

- (void)stopSweep {
    [_secondHand removeAnimationForKey:@"sweep"];
}

@end

#pragma mark - Cell

@interface HAClockCardCell ()
@property (nonatomic, strong) UIStackView *mainStack;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIStackView *digitalStack;
@property (nonatomic, strong) UIView *timeRow;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *secondsLabel;
@property (nonatomic, strong) UILabel *amPmLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) HAClockAnalogFaceView *analogView;

@property (nonatomic, strong) NSLayoutConstraint *stackTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *stackLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *stackWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *timeRowHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *secondsLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *amPmLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *secondsCenterConstraint;
@property (nonatomic, strong) NSLayoutConstraint *amPmCenterConstraint;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *suffixConstraints;
@property (nonatomic, strong) NSLayoutConstraint *analogSizeConstraint;
@property (nonatomic, strong) NSLayoutConstraint *analogMaxSizeConstraint;

// Resolved configuration
@property (nonatomic, assign) BOOL analog;
@property (nonatomic, assign) HAClockSize clockSize;
@property (nonatomic, assign) BOOL showSeconds;
@property (nonatomic, assign) BOOL tickMotion;
@property (nonatomic, assign) BOOL twelveHour;
@property (nonatomic, assign) BOOL noBackground;
@property (nonatomic, copy) NSArray<NSString *> *dateParts;
@property (nonatomic, strong) NSLocale *locale;
@property (nonatomic, strong) NSTimeZone *timeZone;
@property (nonatomic, strong) NSCalendar *calendar;

// Tick state
@property (nonatomic, strong) NSTimer *tickTimer;
@property (nonatomic, strong) HAClockTickProxy *tickProxy;
@property (nonatomic, assign) BOOL tickRequested;
@property (nonatomic, assign) BOOL configured;
@property (nonatomic, assign) long long lastDateMinute;

@property (nonatomic, readwrite, copy) NSString *renderedTimeText;
@property (nonatomic, readwrite, copy) NSString *renderedSecondsText;
@property (nonatomic, readwrite, copy) NSString *renderedAmPmText;
@property (nonatomic, readwrite, copy) NSString *renderedDateText;
@end

@implementation HAClockCardCell

#pragma mark - Sizing

+ (CGFloat)preferredHeightForConfigItem:(HADashboardConfigItem *)configItem width:(CGFloat)width {
    NSDictionary *props = configItem.customProperties;
    HAClockSize size = HAClockSizeFromValue(props[@"clock_size"]);
    BOOL analog = [props[@"clock_style"] isKindOfClass:[NSString class]] && [props[@"clock_style"] isEqualToString:@"analog"];

    CGFloat height = HAClockVerticalPadding(size) * 2.0;
    NSString *title = props[@"clock_title"];
    if ([title isKindOfClass:[NSString class]] && title.length > 0) {
        height += ceil(HAClockTitleFont(size).lineHeight) + HAClockRowGap(size);
    }
    if (analog) {
        CGFloat diameter = HAClockAnalogDiameter(size);
        if (width > 0) diameter = MIN(diameter, width - HAClockHorizontalPadding(size) * 2.0);
        height += MAX(diameter, 0);
    } else {
        height += HAClockTimeRowHeight(size);
        NSArray *parts = [HAClockCardFormatter normalizedDateParts:props[@"date_format"]];
        if (parts.count > 0) {
            height += kDigitalDateGap + ceil(HAClockDigitalDateFont(size).lineHeight * HAClockLineCount(parts));
        }
    }
    return ceil(height);
}

#pragma mark - Setup

- (void)setupSubviews {
    [super setupSubviews];
    // The base name/state labels have nothing to show for an entity-less card.
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitStaticText | UIAccessibilityTraitUpdatesFrequently;

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    // Digital: [time row, date] with a 4pt gap.
    self.timeRow = [[UIView alloc] init];
    self.timeRow.translatesAutoresizingMaskIntoConstraints = NO;

    self.timeLabel = [[UILabel alloc] init];
    self.timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.timeLabel.adjustsFontSizeToFitWidth = YES;
    self.timeLabel.minimumScaleFactor = 0.4;
    self.timeLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    [self.timeLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.timeRow addSubview:self.timeLabel];

    self.secondsLabel = [[UILabel alloc] init];
    self.secondsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.secondsLabel.alpha = 0.4;
    [self.timeRow addSubview:self.secondsLabel];

    self.amPmLabel = [[UILabel alloc] init];
    self.amPmLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.amPmLabel.alpha = 0.6;
    [self.timeRow addSubview:self.amPmLabel];

    self.dateLabel = [[UILabel alloc] init];
    self.dateLabel.textAlignment = NSTextAlignmentCenter;
    self.dateLabel.alpha = 0.8;
    self.dateLabel.adjustsFontSizeToFitWidth = YES;
    self.dateLabel.minimumScaleFactor = 0.5;
    [self.dateLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    self.digitalStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.timeRow, self.dateLabel]];
    self.digitalStack.axis = UILayoutConstraintAxisVertical;
    self.digitalStack.alignment = UIStackViewAlignmentCenter;
    self.digitalStack.spacing = kDigitalDateGap;

    self.analogView = [[HAClockAnalogFaceView alloc] init];
    self.analogView.translatesAutoresizingMaskIntoConstraints = NO;

    self.mainStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.digitalStack, self.analogView]];
    self.mainStack.axis = UILayoutConstraintAxisVertical;
    self.mainStack.alignment = UIStackViewAlignmentCenter;
    self.mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.mainStack];

    UIView *cv = self.contentView;
    self.stackTopConstraint = [self.mainStack.topAnchor constraintGreaterThanOrEqualToAnchor:cv.topAnchor];
    self.stackLeadingConstraint = [self.mainStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:cv.leadingAnchor];
    self.stackWidthConstraint = [self.mainStack.widthAnchor constraintLessThanOrEqualToAnchor:cv.widthAnchor];
    NSLayoutConstraint *titleWidth = [self.titleLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.mainStack.widthAnchor];

    // Time row: [hh:mm][seconds over am/pm], hugging its content.
    NSLayoutConstraint *rowHug = [self.timeRow.widthAnchor constraintEqualToConstant:0];
    rowHug.priority = UILayoutPriorityFittingSizeLevel;
    self.timeRowHeightConstraint = [self.timeRow.heightAnchor constraintEqualToConstant:0];
    self.secondsLeadingConstraint = [self.secondsLabel.leadingAnchor constraintEqualToAnchor:self.timeLabel.trailingAnchor];
    self.amPmLeadingConstraint = [self.amPmLabel.leadingAnchor constraintEqualToAnchor:self.timeLabel.trailingAnchor];
    self.secondsCenterConstraint = [self.secondsLabel.centerYAnchor constraintEqualToAnchor:self.timeRow.topAnchor];
    self.amPmCenterConstraint = [self.amPmLabel.centerYAnchor constraintEqualToAnchor:self.timeRow.bottomAnchor];
    self.suffixConstraints = @[
        [self.timeRow.trailingAnchor constraintGreaterThanOrEqualToAnchor:self.secondsLabel.trailingAnchor],
        [self.timeRow.trailingAnchor constraintGreaterThanOrEqualToAnchor:self.amPmLabel.trailingAnchor],
    ];

    // Analog: square, HA's fixed diameter when it fits, shrinking otherwise.
    self.analogMaxSizeConstraint = [self.analogView.widthAnchor constraintLessThanOrEqualToConstant:100.0];
    self.analogSizeConstraint = [self.analogView.widthAnchor constraintEqualToConstant:100.0];
    self.analogSizeConstraint.priority = UILayoutPriorityDefaultLow - 1;

    [NSLayoutConstraint activateConstraints:@[
        [self.mainStack.centerXAnchor constraintEqualToAnchor:cv.centerXAnchor],
        [self.mainStack.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
        self.stackTopConstraint, self.stackLeadingConstraint, self.stackWidthConstraint, titleWidth,
        rowHug, self.timeRowHeightConstraint,
        [self.timeLabel.leadingAnchor constraintEqualToAnchor:self.timeRow.leadingAnchor],
        [self.timeLabel.centerYAnchor constraintEqualToAnchor:self.timeRow.centerYAnchor],
        [self.timeRow.trailingAnchor constraintGreaterThanOrEqualToAnchor:self.timeLabel.trailingAnchor],
        self.secondsLeadingConstraint, self.amPmLeadingConstraint,
        self.secondsCenterConstraint, self.amPmCenterConstraint,
        [self.analogView.heightAnchor constraintEqualToAnchor:self.analogView.widthAnchor],
        self.analogMaxSizeConstraint, self.analogSizeConstraint,
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange:)
                                                 name:HAThemeDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [_tickTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Configure

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    // Never an entity: the base gives us heading-icon support and the
    // fallback badge reset; undo its "missing entity" dimming.
    [super configureWithEntity:nil configItem:configItem];
    self.contentView.alpha = 1.0;
    self.nameLabel.text = nil;
    self.stateLabel.text = nil;

    NSDictionary *props = configItem.customProperties;
    self.analog = [props[@"clock_style"] isKindOfClass:[NSString class]] && [props[@"clock_style"] isEqualToString:@"analog"];
    self.clockSize = HAClockSizeFromValue(props[@"clock_size"]);
    self.showSeconds = [props[@"show_seconds"] respondsToSelector:@selector(boolValue)] && [props[@"show_seconds"] boolValue];
    self.tickMotion = [props[@"seconds_motion"] isKindOfClass:[NSString class]] && [props[@"seconds_motion"] isEqualToString:@"tick"];
    self.noBackground = [props[@"no_background"] respondsToSelector:@selector(boolValue)] && [props[@"no_background"] boolValue];
    self.dateParts = [HAClockCardFormatter normalizedDateParts:props[@"date_format"]];
    self.analogView.ticks = [[self class] ticksFromValue:props[@"ticks"]];
    self.analogView.face = [[self class] faceFromValue:props[@"face_style"]];
    self.analogView.uprightNumbers = [[self class] uprightNumbersFromValue:props[@"face_style"]];
    self.analogView.showsBorder = [props[@"border"] respondsToSelector:@selector(boolValue)] && [props[@"border"] boolValue];

    NSString *language = self.languageCodeOverride.length > 0 ? self.languageCodeOverride : [HAClockCardFormatter currentLanguageCode];
    self.locale = [HAClockCardFormatter localeForLanguageCode:language];
    self.timeZone = [HAClockCardFormatter timeZoneForConfigValue:props[@"time_zone"]];
    self.twelveHour = [HAClockCardFormatter usesTwelveHourClockForTimeFormat:props[@"time_format"] languageLocale:self.locale];
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = self.timeZone;
    self.calendar = calendar;

    // Background: no_background drops the card surface entirely. A zero
    // corner radius is also what tells the dashboard not to add the frosted
    // card background (same convention as markdown text_only).
    if (self.noBackground) {
        self.contentView.backgroundColor = [UIColor clearColor];
        self.contentView.layer.cornerRadius = 0;
    } else {
        self.contentView.layer.cornerRadius = kCardCornerRadius;
    }

    [self applyLayoutMetrics];

    NSString *title = [props[@"clock_title"] isKindOfClass:[NSString class]] ? props[@"clock_title"] : nil;
    self.titleLabel.text = title;
    self.titleLabel.hidden = (title.length == 0);

    self.digitalStack.hidden = self.analog;
    self.analogView.hidden = !self.analog;
    self.dateLabel.hidden = self.analog || self.dateParts.count == 0;
    self.analogView.dateLabel.hidden = !self.analog || self.dateParts.count == 0;

    [self applyClockColors];

    self.configured = YES;
    self.lastDateMinute = LLONG_MIN;
    self.renderedTimeText = nil;
    self.renderedSecondsText = nil;
    self.renderedAmPmText = nil;
    self.renderedDateText = nil;
    self.secondsLabel.text = nil;
    self.amPmLabel.text = nil;
    [self updateSuffixLayout];
    [self.analogView stopSweep];
    [self refreshDisplayAnimated:NO];

    self.tickRequested = YES;
    [self updateTimerState];
}

- (void)applyLayoutMetrics {
    HAClockSize size = self.clockSize;
    self.stackTopConstraint.constant = HAClockVerticalPadding(size);
    self.stackLeadingConstraint.constant = HAClockHorizontalPadding(size);
    self.stackWidthConstraint.constant = -2.0 * HAClockHorizontalPadding(size);
    self.mainStack.spacing = HAClockRowGap(size);
    self.titleLabel.font = HAClockTitleFont(size);

    // Digital
    CGFloat timeFontSize = HAClockDigitalTimeFontSize(size);
    CGFloat suffixFontSize = HAClockDigitalSuffixFontSize(size);
    CGFloat rowHeight = HAClockTimeRowHeight(size);
    self.timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:timeFontSize weight:UIFontWeightMedium];
    UIFont *suffixFont = [UIFont monospacedDigitSystemFontOfSize:suffixFontSize weight:UIFontWeightMedium];
    self.secondsLabel.font = suffixFont;
    self.amPmLabel.font = suffixFont;
    self.timeRowHeightConstraint.constant = rowHeight;
    CGFloat margin = HAClockDigitalSuffixMargin(size);
    self.secondsLeadingConstraint.constant = margin;
    self.amPmLeadingConstraint.constant = margin;
    self.dateLabel.font = HAClockDigitalDateFont(size);
    self.dateLabel.numberOfLines = HAClockLineCount(self.dateParts);

    // Analog
    CGFloat diameter = HAClockAnalogDiameter(size);
    self.analogSizeConstraint.constant = diameter;
    self.analogMaxSizeConstraint.constant = diameter;
    HAClockAnalogFaceView *face = self.analogView;
    face.clockSize = size;
    face.showsSeconds = self.showSeconds;
    face.dateLineCount = HAClockLineCount(self.dateParts);
    face.longDate = [self.dateParts containsObject:@"month-long"] || [self.dateParts containsObject:@"weekday-long"];
    [face setNeedsGeometryUpdate];
}

+ (HAClockTicks)ticksFromValue:(id)value {
    if (![value isKindOfClass:[NSString class]]) return HAClockTicksHour; // HA default
    if ([value isEqualToString:@"none"]) return HAClockTicksNone;
    if ([value isEqualToString:@"quarter"]) return HAClockTicksQuarter;
    if ([value isEqualToString:@"minute"]) return HAClockTicksMinute;
    return HAClockTicksHour;
}

+ (HAClockFace)faceFromValue:(id)value {
    // HA splits face_style on "_": "numbers" → arabic numerals, "roman" →
    // roman numerals, anything else (incl. "markers") → tick marks only.
    if (![value isKindOfClass:[NSString class]]) return HAClockFaceMarkers;
    NSArray *parts = [(NSString *)value componentsSeparatedByString:@"_"];
    if ([parts containsObject:@"roman"]) return HAClockFaceRoman;
    if ([parts containsObject:@"numbers"]) return HAClockFaceNumbers;
    return HAClockFaceMarkers;
}

+ (BOOL)uprightNumbersFromValue:(id)value {
    // "_upright" keeps numerals level; without it they rotate with their tick
    // (so "roman" draws like a classic dial).
    return [value isKindOfClass:[NSString class]] &&
           [[(NSString *)value componentsSeparatedByString:@"_"] containsObject:@"upright"];
}

#pragma mark - Theme

- (void)applyClockColors {
    UIColor *primary = [HATheme primaryTextColor];
    self.titleLabel.textColor = primary;
    self.timeLabel.textColor = primary;
    self.secondsLabel.textColor = primary;
    self.amPmLabel.textColor = primary;
    self.dateLabel.textColor = primary;
    self.analogView.primaryColor = primary;
    self.analogView.secondHandColor = [HATheme destructiveColor];
    [self.analogView setNeedsLayout];
}

- (void)resetThemeColors {
    [super resetThemeColors];
    [self applyClockColors];
}

- (void)themeDidChange:(NSNotification *)notification {
    [self applyClockColors];
}

#pragma mark - Ticking

- (BOOL)isTicking {
    return self.tickTimer != nil;
}

- (void)beginTicking {
    if (!self.configured) return;
    BOOL wasTicking = self.isTicking;
    self.tickRequested = YES;
    [self updateTimerState];
    if (!wasTicking && self.isTicking) [self refreshDisplayAnimated:NO];
}

- (void)endTicking {
    self.tickRequested = NO;
    [self updateTimerState];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    BOOL wasTicking = self.isTicking;
    [self updateTimerState];
    // Time passed while off-screen: catch up immediately on return.
    if (!wasTicking && self.isTicking) [self refreshDisplayAnimated:NO];
}

- (void)updateTimerState {
    BOOL shouldTick = self.configured && self.tickRequested && self.window != nil && self.fixedDate == nil;
    if (shouldTick && !self.tickTimer) {
        [self scheduleNextTick];
    } else if (!shouldTick && self.tickTimer) {
        [self.tickTimer invalidate];
        self.tickTimer = nil;
        [self.analogView stopSweep];
    }
}

- (void)scheduleNextTick {
    [self.tickTimer invalidate];
    if (!self.tickProxy) {
        self.tickProxy = [[HAClockTickProxy alloc] init];
        self.tickProxy.cell = self;
    }
    // Fire just after the next wall-clock second boundary so the displayed
    // second never lags; re-armed every tick, so it cannot drift.
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSDate *fireDate = [NSDate dateWithTimeIntervalSinceReferenceDate:floor(now) + 1.0 + 0.005];
    NSTimer *timer = [[NSTimer alloc] initWithFireDate:fireDate
                                              interval:0
                                                target:self.tickProxy
                                              selector:@selector(tick:)
                                              userInfo:nil
                                               repeats:NO];
    timer.tolerance = 0.02;
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.tickTimer = timer;
}

- (void)handleTick:(NSTimer *)timer {
    if (timer != self.tickTimer) return;
    self.tickTimer = nil;
    [self refreshDisplayAnimated:YES];
    [self updateTimerState];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.tickRequested = NO;
    self.configured = NO;
    [self updateTimerState];
    [self.analogView stopSweep];
    self.contentView.layer.cornerRadius = kCardCornerRadius;
    self.titleLabel.text = nil;
    self.timeLabel.attributedText = nil;
    self.secondsLabel.text = nil;
    self.amPmLabel.text = nil;
    self.dateLabel.text = nil;
    self.analogView.dateLabel.text = nil;
    self.accessibilityLabel = nil;
}

#pragma mark - Rendering

- (NSDate *)currentDate {
    return self.fixedDate ?: [NSDate date];
}

- (void)refreshDisplayAnimated:(BOOL)animated {
    if (!self.configured) return;
    NSDate *now = [self currentDate];
    long long minute = (long long)floor(now.timeIntervalSince1970 / 60.0);
    BOOL minuteChanged = (minute != self.lastDateMinute);
    self.lastDateMinute = minute;

    if (minuteChanged) {
        NSString *date = self.dateParts.count > 0
            ? [HAClockCardFormatter dateStringForDate:now parts:self.dateParts locale:self.locale timeZone:self.timeZone]
            : nil;
        self.renderedDateText = date;
        if (self.analog) {
            self.analogView.dateLabel.text = date;
        } else {
            self.dateLabel.text = date;
        }
    }

    if (self.analog) {
        [self refreshAnalogForDate:now animated:animated];
    } else {
        [self refreshDigitalForDate:now minuteChanged:minuteChanged];
    }

    if (minuteChanged) {
        // Minute granularity for VoiceOver, so it doesn't chatter every second.
        NSString *time = [HAClockCardFormatter stringFromDate:now
                                                       format:(self.twelveHour ? @"h:mm a" : @"HH:mm")
                                                       locale:self.locale
                                                     timeZone:self.timeZone];
        NSMutableArray *parts = [NSMutableArray array];
        if (self.titleLabel.text.length > 0) [parts addObject:self.titleLabel.text];
        [parts addObject:time];
        if (self.renderedDateText.length > 0) {
            [parts addObject:[self.renderedDateText stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
        }
        self.accessibilityLabel = [parts componentsJoinedByString:@", "];
    }
}

- (void)refreshDigitalForDate:(NSDate *)now minuteChanged:(BOOL)minuteChanged {
    if (minuteChanged || !self.renderedTimeText) {
        NSString *hour = [HAClockCardFormatter stringFromDate:now format:(self.twelveHour ? @"h" : @"HH")
                                                      locale:self.locale timeZone:self.timeZone];
        NSString *minuteText = [HAClockCardFormatter stringFromDate:now format:@"mm"
                                                            locale:self.locale timeZone:self.timeZone];
        NSString *time = [NSString stringWithFormat:@"%@:%@", hour, minuteText];
        if (![time isEqualToString:self.renderedTimeText]) {
            self.renderedTimeText = time;
            // `.hour:after { content: ":"; margin: 0 2px }`
            NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:time];
            if (hour.length > 0) {
                [attributed addAttribute:NSKernAttributeName value:@2.0 range:NSMakeRange(hour.length - 1, 2)];
            }
            self.timeLabel.attributedText = attributed;
        }

        NSString *amPm = nil;
        if (self.twelveHour) {
            NSInteger hour24 = [self.calendar component:NSCalendarUnitHour fromDate:now];
            amPm = [HAClockCardFormatter amPmSymbolsForLocale:self.locale][hour24 < 12 ? 0 : 1];
        }
        if (![amPm isEqualToString:self.renderedAmPmText] && (amPm || self.renderedAmPmText)) {
            self.renderedAmPmText = amPm;
            self.amPmLabel.text = amPm;
            [self updateSuffixLayout];
        }
    }

    NSString *seconds = self.showSeconds
        ? [HAClockCardFormatter stringFromDate:now format:@"ss" locale:self.locale timeZone:self.timeZone]
        : nil;
    if (![seconds isEqualToString:self.renderedSecondsText] && (seconds || self.renderedSecondsText)) {
        BOOL presenceChanged = (seconds == nil) != (self.renderedSecondsText == nil);
        self.renderedSecondsText = seconds;
        self.secondsLabel.text = seconds;
        if (presenceChanged) [self updateSuffixLayout];
    }
}

/// Seconds sit in the upper grid row and AM/PM in the lower one of the
/// `"hour minute second" / "hour minute am-pm"` grid. CSS grid shares the
/// time block's height between the two auto rows, so each suffix is centred
/// in its row.
- (void)updateSuffixLayout {
    BOOL hasSeconds = self.renderedSecondsText != nil;
    BOOL hasAmPm = self.renderedAmPmText != nil;
    CGFloat rowHeight = HAClockTimeRowHeight(self.clockSize);
    CGFloat suffixLine = HAClockDigitalSuffixFontSize(self.clockSize) * 0.9;

    CGFloat secondsRow, amPmRow;
    if (hasSeconds && hasAmPm) {
        secondsRow = amPmRow = rowHeight / 2.0;
    } else {
        CGFloat occupied = (rowHeight + suffixLine) / 2.0; // the row holding the lone suffix
        secondsRow = hasSeconds ? occupied : rowHeight - occupied;
        amPmRow = rowHeight - secondsRow;
    }
    self.secondsCenterConstraint.constant = secondsRow / 2.0;
    self.amPmCenterConstraint.constant = -amPmRow / 2.0;

    for (NSLayoutConstraint *c in self.suffixConstraints) c.active = (hasSeconds || hasAmPm);
    self.secondsLabel.hidden = !hasSeconds;
    self.amPmLabel.hidden = !hasAmPm;
    self.secondsLeadingConstraint.constant = hasSeconds ? HAClockDigitalSuffixMargin(self.clockSize) : 0;
    self.amPmLeadingConstraint.constant = hasAmPm ? HAClockDigitalSuffixMargin(self.clockSize) : 0;
}

- (void)refreshAnalogForDate:(NSDate *)now animated:(BOOL)animated {
    NSDateComponents *c = [self.calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute |
                                                     NSCalendarUnitSecond | NSCalendarUnitNanosecond)
                                           fromDate:now];
    double seconds = (double)c.second + (double)c.nanosecond / 1e9;
    double minuteSeconds = (double)c.minute * 60.0 + seconds;
    double hourSeconds = (double)(c.hour % 12) * 3600.0 + minuteSeconds;
    [self.analogView setHourAngle:(CGFloat)(hourSeconds / 43200.0 * 2.0 * M_PI)
                      minuteAngle:(CGFloat)(minuteSeconds / 3600.0 * 2.0 * M_PI)];

    if (!self.showSeconds) return;
    // seconds_motion: tick steps once per second; the HA default (continuous)
    // sweeps — except on iPad 2-class hardware, where it degrades to tick.
    BOOL sweep = animated && !self.tickMotion && !HAClockIsLightweightDevice();
    if (sweep) {
        double nextSecond = floor(seconds) + 1.0;
        CGFloat from = (CGFloat)(seconds / 60.0 * 2.0 * M_PI);
        CGFloat to = (CGFloat)(nextSecond / 60.0 * 2.0 * M_PI);
        [self.analogView setSecondAngle:from sweepToAngle:to duration:(nextSecond - seconds)];
    } else {
        double shown = self.tickMotion ? floor(seconds) : seconds;
        [self.analogView setSecondAngle:(CGFloat)(shown / 60.0 * 2.0 * M_PI) sweepToAngle:0 duration:0];
    }
}

@end
