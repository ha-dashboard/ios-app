#import "HAAutoLayout.h"
#import "HAGraphView.h"
#import "HATheme.h"
#import <sys/utsname.h>
#import "UIFont+HACompat.h"
#import "NSString+HACompat.h"

// Cached date formatters used by axis labels, tooltip, and gesture handlers.
// Format is set per-use since it depends on the visible time range.
static NSDateFormatter *sCachedTimeFmt(void) {
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [[NSDateFormatter alloc] init];
    });
    return fmt;
}

@interface HAGraphView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSMutableArray<CAShapeLayer *> *lineLayers;
@property (nonatomic, strong) CAShapeLayer *fillMaskLayer;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) UIView *legendContainer;
@property (nonatomic, strong) NSLayoutConstraint *legendHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *legendBottomConstraint;
@property (nonatomic, strong) UITapGestureRecognizer *legendTapGesture;
@property (nonatomic, strong) NSMutableArray<NSValue *> *legendEntryFrames; // CGRect wrapped in NSValue for hit-testing
@property (nonatomic, assign) BOOL lightweight; // Skip gradient on older devices
// State timeline rendering
@property (nonatomic, strong) NSMutableArray<CALayer *> *timelineLayers; // Bar segment layers
@property (nonatomic, strong) NSMutableArray<UILabel *> *timelineLabels; // Entity name labels
// Axis labels
@property (nonatomic, strong) NSMutableArray<UILabel *> *timeAxisLabels;
@property (nonatomic, strong) NSMutableArray<UILabel *> *valueAxisLabels;
// Stored for tooltip hit-testing
@property (nonatomic, assign) double currentMinVal;
@property (nonatomic, assign) double currentMaxVal;
@property (nonatomic, assign) NSTimeInterval currentMinTime;
@property (nonatomic, assign) NSTimeInterval currentMaxTime;
// Multi-axis Y scaling by unit: groups[i] = @{@"unit":NSString, @"indices":NSIndexSet, @"yMin":NSNumber, @"yMax":NSNumber}
@property (nonatomic, strong) NSArray<NSDictionary *> *axisGroups;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *seriesIndexToGroupIndex; // series idx -> group idx
// Tooltip
@property (nonatomic, strong) CALayer *crosshairLine;
@property (nonatomic, strong) UIView *tooltipView;
@property (nonatomic, strong) UILabel *tooltipValueLabel;
@property (nonatomic, strong) UILabel *tooltipTimeLabel;
@property (nonatomic, strong) UILongPressGestureRecognizer *inspectGesture;
// Zoom/Pan
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchGesture;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGesture;
@property (nonatomic, assign) NSTimeInterval anchorStartTime;
@property (nonatomic, assign) NSTimeInterval anchorEndTime;
@property (nonatomic, assign) CGFloat zoomScale;
@property (nonatomic, assign) CGSize lastLayoutSize;
@end

@implementation HAGraphView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = YES;

    _lineColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.7 alpha:1.0]; // Teal
    _fillColor = nil; // Will derive from lineColor
    _lineLayers = [NSMutableArray array];
    _timelineLayers = [NSMutableArray array];
    _timelineLabels = [NSMutableArray array];
    _timeAxisLabels = [NSMutableArray array];
    _valueAxisLabels = [NSMutableArray array];
    _hiddenSeriesIndices = [NSMutableIndexSet indexSet];
    _legendEntryFrames = [NSMutableArray array];
    _axisGroups = @[];
    _seriesIndexToGroupIndex = [NSMutableDictionary dictionary];

    // Detect older devices: armv7 or low RAM -> skip gradient
    #if !TARGET_OS_SIMULATOR
    NSString *machine = nil;
    struct utsname systemInfo;
    if (uname(&systemInfo) == 0) {
        machine = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    }
    // iPad2,x / iPad3,x / iPhone4,x / iPod5,x are armv7 — use lightweight mode
    _lightweight = (machine && ([machine hasPrefix:@"iPad2"] || [machine hasPrefix:@"iPad3"] ||
                                [machine hasPrefix:@"iPhone4"] || [machine hasPrefix:@"iPod5"]));
    #endif

    if (!_lightweight) {
        // Gradient fill layer (skip on old devices — saves GPU compositing)
        self.gradientLayer = [CAGradientLayer layer];
        self.gradientLayer.startPoint = CGPointMake(0.5, 0);
        self.gradientLayer.endPoint = CGPointMake(0.5, 1);
        [self.layer addSublayer:self.gradientLayer];

        // Fill mask
        self.fillMaskLayer = [CAShapeLayer layer];
        self.fillMaskLayer.fillColor = [UIColor whiteColor].CGColor;
        self.gradientLayer.mask = self.fillMaskLayer;
    }

    // Legend container (hidden until multi-series)
    self.legendContainer = [[UIView alloc] init];
    self.legendContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.legendContainer.hidden = YES;
    [self addSubview:self.legendContainer];

    self.legendHeightConstraint = HAMakeConstraint([self.legendContainer.heightAnchor constraintEqualToConstant:0]);
    // Position legend above the time axis labels (18pt bottom padding when axis shown)
    self.legendBottomConstraint = HAMakeConstraint([self.legendContainer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2]);
    HAActivateConstraints(@[
        HACon([self.legendContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8]),
        HACon([self.legendContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8]),
        HACon(self.legendBottomConstraint),
        HACon(self.legendHeightConstraint),
    ]);

    // Crosshair line (vertical, 1px, hidden until inspection)
    _crosshairLine = [CALayer layer];
    _crosshairLine.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6].CGColor;
    _crosshairLine.hidden = YES;
    [self.layer addSublayer:_crosshairLine];

    // Tooltip container
    _tooltipView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, 36)];
    _tooltipView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
    _tooltipView.layer.cornerRadius = 6;
    _tooltipView.clipsToBounds = YES;
    _tooltipView.hidden = YES;
    _tooltipView.userInteractionEnabled = NO;

    _tooltipValueLabel = [[UILabel alloc] init];
    _tooltipValueLabel.font = [UIFont ha_monospacedDigitSystemFontOfSize:12 weight:HAFontWeightBold];
    _tooltipValueLabel.textColor = [UIColor whiteColor];
    _tooltipValueLabel.textAlignment = NSTextAlignmentCenter;
    _tooltipValueLabel.numberOfLines = 0; // Support multi-line
    _tooltipValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_tooltipView addSubview:_tooltipValueLabel];

    _tooltipTimeLabel = [[UILabel alloc] init];
    _tooltipTimeLabel.font = [UIFont systemFontOfSize:10];
    _tooltipTimeLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    _tooltipTimeLabel.textAlignment = NSTextAlignmentCenter;
    _tooltipTimeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_tooltipView addSubview:_tooltipTimeLabel];

    HAActivateConstraints(@[
        HACon([_tooltipValueLabel.topAnchor constraintEqualToAnchor:_tooltipView.topAnchor constant:3]),
        HACon([_tooltipValueLabel.leadingAnchor constraintEqualToAnchor:_tooltipView.leadingAnchor constant:6]),
        HACon([_tooltipValueLabel.trailingAnchor constraintEqualToAnchor:_tooltipView.trailingAnchor constant:-6]),
        HACon([_tooltipTimeLabel.topAnchor constraintEqualToAnchor:_tooltipValueLabel.bottomAnchor constant:1]),
        HACon([_tooltipTimeLabel.leadingAnchor constraintEqualToAnchor:_tooltipView.leadingAnchor constant:6]),
        HACon([_tooltipTimeLabel.trailingAnchor constraintEqualToAnchor:_tooltipView.trailingAnchor constant:-6]),
    ]);

    [self addSubview:_tooltipView];
}

#pragma mark - Inspection Enabled

- (void)setInspectionEnabled:(BOOL)inspectionEnabled {
    _inspectionEnabled = inspectionEnabled;
    if (inspectionEnabled) {
        if (!self.inspectGesture) {
            self.inspectGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleInspect:)];
            self.inspectGesture.minimumPressDuration = 0.15;
            [self addGestureRecognizer:self.inspectGesture];
        }
        self.inspectGesture.enabled = YES;

        // Pinch-to-zoom
        if (!self.pinchGesture) {
            self.pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
            [self addGestureRecognizer:self.pinchGesture];
        }
        self.pinchGesture.enabled = YES;

        // Horizontal pan (scrub when not zoomed, time shift when zoomed)
        if (!self.panGesture) {
            self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
            self.panGesture.delegate = self;
            [self addGestureRecognizer:self.panGesture];
        }
        self.panGesture.enabled = YES;

        // Double-tap to reset zoom
        if (!self.doubleTapGesture) {
            self.doubleTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
            self.doubleTapGesture.numberOfTapsRequired = 2;
            [self addGestureRecognizer:self.doubleTapGesture];
            [self.inspectGesture requireGestureRecognizerToFail:self.doubleTapGesture];
        }
        self.doubleTapGesture.enabled = YES;
    } else {
        self.inspectGesture.enabled = NO;
        self.pinchGesture.enabled = NO;
        self.panGesture.enabled = NO;
        self.doubleTapGesture.enabled = NO;
        self.crosshairLine.hidden = YES;
        self.tooltipView.hidden = YES;
    }
}

#pragma mark - Axis padding helpers

- (CGFloat)graphAreaLeftPadding {
    if (!self.showAxisLabels) return 0.0;
    // First group gets left axis (30px for value labels)
    return (self.axisGroups.count > 0) ? 35.0 : 30.0;
}

- (CGFloat)graphAreaRightPadding {
    if (!self.showAxisLabels) return 0.0;
    // Additional groups get right axes (35px per group)
    NSUInteger additionalGroups = (self.axisGroups.count > 1) ? (self.axisGroups.count - 1) : 0;
    return additionalGroups * 35.0;
}

- (CGFloat)graphAreaBottomPadding {
    return self.showAxisLabels ? 18.0 : 0.0;
}

#pragma mark - Single-series backward compat

- (void)setDataPoints:(NSArray<NSDictionary *> *)points animated:(BOOL)animated {
    _dataPoints = [points copy];
    _dataSeries = nil;
    _timelineData = nil;
    [self clearTimelineLayers];
    self.gradientLayer.hidden = NO;
    [self rebuildLayers];
    [self updatePaths];
}

- (void)setDataPoints:(NSArray<NSDictionary *> *)dataPoints {
    _dataPoints = [dataPoints copy];
    _dataSeries = nil;
    _timelineData = nil;
    [self clearTimelineLayers];
    self.gradientLayer.hidden = NO;
    [self rebuildLayers];
    [self updatePaths];
}

#pragma mark - Multi-series

- (void)setDataSeries:(NSArray<NSDictionary *> *)dataSeries {
    _dataSeries = [dataSeries copy];
    _dataPoints = nil;
    _timelineData = nil;
    [self clearTimelineLayers];
    self.gradientLayer.hidden = NO;
    [self computeAxisGroups];
    [self rebuildLayers];
    [self updatePaths];
}

/// Group series by unit of measurement for multi-axis Y scaling
- (void)computeAxisGroups {
    if (!self.dataSeries || self.dataSeries.count == 0) {
        self.axisGroups = @[];
        [self.seriesIndexToGroupIndex removeAllObjects];
        return;
    }

    // Group series by unit
    NSMutableDictionary<NSString *, NSMutableIndexSet *> *unitToIndices = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < self.dataSeries.count; i++) {
        NSDictionary *series = self.dataSeries[i];
        NSString *unit = series[@"unit"];
        if (!unit) unit = @"";

        NSMutableIndexSet *indices = unitToIndices[unit];
        if (!indices) {
            indices = [NSMutableIndexSet indexSet];
            unitToIndices[unit] = indices;
        }
        [indices addIndex:i];
    }

    // Build axis groups array, preserving order of first appearance
    NSMutableArray<NSDictionary *> *groups = [NSMutableArray array];
    NSMutableSet<NSString *> *seenUnits = [NSMutableSet set];

    for (NSUInteger i = 0; i < self.dataSeries.count; i++) {
        NSDictionary *series = self.dataSeries[i];
        NSString *unit = series[@"unit"];
        if (!unit) unit = @"";

        if ([seenUnits containsObject:unit]) continue;
        [seenUnits addObject:unit];

        NSIndexSet *indices = unitToIndices[unit];
        [groups addObject:@{
            @"unit": unit,
            @"indices": indices,
            @"yMin": @0.0,  // Will be computed in updateMultiSeriesPaths
            @"yMax": @0.0,
        }];
    }

    self.axisGroups = [groups copy];

    // Build seriesIndex -> groupIndex mapping
    [self.seriesIndexToGroupIndex removeAllObjects];
    for (NSUInteger gi = 0; gi < self.axisGroups.count; gi++) {
        NSDictionary *group = self.axisGroups[gi];
        NSIndexSet *indices = group[@"indices"];
        [indices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            self.seriesIndexToGroupIndex[@(idx)] = @(gi);
        }];
    }
}

#pragma mark - State Timeline

- (void)setTimelineData:(NSArray<NSDictionary *> *)timelineData {
    _timelineData = [timelineData copy];
    _dataPoints = nil;
    _dataSeries = nil;
    // Only destroy line graph layers when switching TO timeline mode (not when clearing)
    if (timelineData.count > 0) {
        for (CAShapeLayer *layer in self.lineLayers) {
            [layer removeFromSuperlayer];
        }
        [self.lineLayers removeAllObjects];
        self.fillMaskLayer.path = nil;
        self.gradientLayer.hidden = YES;
        self.legendContainer.hidden = YES;
        self.legendHeightConstraint.constant = 0;
    }

    [self clearTimelineLayers];
    [self updateTimelineBars];
}

- (void)clearTimelineLayers {
    for (CALayer *layer in self.timelineLayers) {
        [layer removeFromSuperlayer];
    }
    [self.timelineLayers removeAllObjects];
    for (UILabel *label in self.timelineLabels) {
        [label removeFromSuperview];
    }
    [self.timelineLabels removeAllObjects];
}

/// Color for a state string. Active states get a bright color, inactive get dim.
+ (UIColor *)colorForState:(NSString *)state entityId:(NSString *)entityId {
    if (!state) return [UIColor colorWithWhite:0.3 alpha:1.0];
    NSString *lower = [state lowercaseString];

    // Unavailable / unknown — hatched gray
    if ([lower isEqualToString:@"unavailable"] || [lower isEqualToString:@"unknown"]) {
        return [UIColor colorWithWhite:0.25 alpha:0.6];
    }

    // Active states
    static NSSet *activeStates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        activeStates = [NSSet setWithArray:@[
            @"on", @"true", @"home", @"open", @"locked", @"playing",
            @"cleaning", @"charging", @"heat", @"cool", @"heat_cool",
            @"yes", @"active", @"detected", @"wet", @"low",
        ]];
    });

    if ([activeStates containsObject:lower]) {
        // Derive domain from entity ID for color variety
        NSString *domain = nil;
        NSRange dot = [entityId rangeOfString:@"."];
        if (dot.location != NSNotFound) {
            domain = [entityId substringToIndex:dot.location];
        }
        if ([domain isEqualToString:@"binary_sensor"]) {
            return [UIColor colorWithRed:1.00 green:0.72 blue:0.00 alpha:1.0]; // Amber (HA default for binary_sensor on)
        }
        if ([domain isEqualToString:@"person"]) {
            return [UIColor colorWithRed:0.30 green:0.60 blue:1.00 alpha:1.0]; // Blue
        }
        return [UIColor colorWithRed:0.30 green:0.60 blue:1.00 alpha:1.0]; // Default active blue
    }

    // Inactive states
    static NSSet *inactiveStates = nil;
    static dispatch_once_t inactiveOnce;
    dispatch_once(&inactiveOnce, ^{
        inactiveStates = [NSSet setWithArray:@[
            @"off", @"false", @"away", @"closed", @"unlocked", @"idle",
            @"standby", @"paused", @"docked", @"no", @"not_home",
            @"clear", @"normal", @"ok",
        ]];
    });

    if ([inactiveStates containsObject:lower]) {
        return [UIColor colorWithWhite:0.35 alpha:1.0]; // Dim gray
    }

    // Any other state — use a medium distinct color
    return [UIColor colorWithRed:0.50 green:0.50 blue:0.60 alpha:1.0];
}

- (void)updateTimelineBars {
    if (!self.timelineData || self.timelineData.count == 0) return;
    if (CGRectIsEmpty(self.bounds)) return;

    CGFloat bottomPad = [self graphAreaBottomPadding];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height - bottomPad;
    NSUInteger entityCount = self.timelineData.count;

    // Layout: label area on left, bars on right
    CGFloat labelWidth = 0; // Will compute from longest label
    CGFloat barHeight = 22.0;
    CGFloat verticalGap = 4.0;
    CGFloat topPad = 4.0;
    CGFloat labelPad = 6.0; // Gap between label and bar

    // Compute label width from longest entity name
    UIFont *labelFont = [UIFont ha_systemFontOfSize:11 weight:HAFontWeightMedium];
    for (NSDictionary *entity in self.timelineData) {
        NSString *label = entity[@"label"] ?: @"";
        CGSize sz = [label ha_sizeWithAttributes:@{HAFontAttributeName: labelFont}];
        if (sz.width > labelWidth) labelWidth = sz.width;
    }
    // Clamp label width
    if (labelWidth > w * 0.35) labelWidth = w * 0.35;
    if (labelWidth < 30) labelWidth = 30;

    CGFloat barAreaX = labelWidth + labelPad + 8; // 8pt left margin for labels
    CGFloat barAreaW = w - barAreaX - 4; // 4pt right margin
    if (barAreaW < 20) barAreaW = 20;

    // Compute global time range across all entity timelines
    double minTime = HUGE_VAL, maxTime = -HUGE_VAL;
    for (NSDictionary *entity in self.timelineData) {
        NSArray *segments = entity[@"segments"];
        for (NSDictionary *seg in segments) {
            double start = [seg[@"start"] doubleValue];
            double end = [seg[@"end"] doubleValue];
            if (start < minTime) minTime = start;
            if (end > maxTime) maxTime = end;
        }
    }
    double timeRange = maxTime - minTime;
    if (timeRange < 1.0) timeRange = 1.0;

    // Store for Phase 4 tooltip hit-testing and axis labels
    self.currentMinTime = minTime;
    self.currentMaxTime = maxTime;
    self.currentMinVal = 0;
    self.currentMaxVal = 0;

    // Adjust bar height if too many entities would overflow
    CGFloat totalNeeded = topPad + entityCount * (barHeight + verticalGap);
    if (totalNeeded > h && entityCount > 0) {
        barHeight = MAX(8.0, (h - topPad - verticalGap * entityCount) / entityCount);
    }

    // Draw each entity's timeline
    for (NSUInteger i = 0; i < entityCount; i++) {
        NSDictionary *entity = self.timelineData[i];
        NSString *label = entity[@"label"] ?: @"";
        NSString *entityId = entity[@"entityId"] ?: @"";
        NSArray *segments = entity[@"segments"];

        CGFloat y = topPad + i * (barHeight + verticalGap);

        // Entity name label
        UILabel *lbl = [[UILabel alloc] init];
        lbl.text = label;
        lbl.font = labelFont;
        lbl.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
        lbl.lineBreakMode = NSLineBreakByTruncatingTail;
        lbl.frame = CGRectMake(8, y, labelWidth, barHeight);
        [self addSubview:lbl];
        [self.timelineLabels addObject:lbl];

        // Background bar (full track, very dim)
        CALayer *bgBar = [CALayer layer];
        bgBar.frame = CGRectMake(barAreaX, y, barAreaW, barHeight);
        bgBar.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0].CGColor;
        bgBar.cornerRadius = 3.0;
        bgBar.masksToBounds = YES;
        [self.layer addSublayer:bgBar];
        [self.timelineLayers addObject:bgBar];

        // Segment bars
        for (NSDictionary *seg in segments) {
            double start = [seg[@"start"] doubleValue];
            double end = [seg[@"end"] doubleValue];
            NSString *state = seg[@"state"];

            CGFloat segX = (CGFloat)((start - minTime) / timeRange) * barAreaW;
            CGFloat segEndX = (CGFloat)((end - minTime) / timeRange) * barAreaW;
            CGFloat segW = segEndX - segX;
            if (segW < 0.5) segW = 0.5; // Minimum visible width

            UIColor *color = [HAGraphView colorForState:state entityId:entityId];

            CALayer *segLayer = [CALayer layer];
            segLayer.frame = CGRectMake(barAreaX + segX, y, segW, barHeight);
            segLayer.backgroundColor = color.CGColor;
            // Round corners only on first/last segments
            if (segX <= 0.5) {
                segLayer.cornerRadius = 3.0;
                segLayer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
            }
            if (segEndX >= barAreaW - 0.5) {
                segLayer.cornerRadius = 3.0;
                segLayer.maskedCorners |= kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
            }
            segLayer.masksToBounds = YES;
            [self.layer addSublayer:segLayer];
            [self.timelineLayers addObject:segLayer];
        }
    }

    [self updateAxisLabels];
}

#pragma mark - Layer management

- (void)rebuildLayers {
    // Remove old line layers
    for (CAShapeLayer *layer in self.lineLayers) {
        [layer removeFromSuperlayer];
    }
    [self.lineLayers removeAllObjects];

    NSUInteger count = 1;
    if (self.dataSeries.count > 0) {
        count = self.dataSeries.count;
    }

    for (NSUInteger i = 0; i < count; i++) {
        CAShapeLayer *lineLayer = [CAShapeLayer layer];
        lineLayer.fillColor = [UIColor clearColor].CGColor;
        lineLayer.lineWidth = self.lightweight ? 1.5 : 2.0;
        lineLayer.lineJoin = kCALineJoinRound;
        lineLayer.lineCap = kCALineCapRound;
        [self.layer addSublayer:lineLayer];
        [self.lineLayers addObject:lineLayer];
    }

    // Update legend
    [self updateLegend];
}

- (void)updateLegend {
    // Remove old legend subviews
    for (UIView *sub in self.legendContainer.subviews) {
        [sub removeFromSuperview];
    }
    [self.legendEntryFrames removeAllObjects];

    if (self.dataSeries.count <= 1) {
        self.legendContainer.hidden = YES;
        self.legendHeightConstraint.constant = 0;
        if (self.legendTapGesture) {
            self.legendTapGesture.enabled = NO;
        }
        return;
    }

    // Build wrapping legend: dot + label for each series, wraps to multiple lines
    self.legendContainer.hidden = NO;

    // Add tap gesture if needed
    if (!self.legendTapGesture) {
        self.legendTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleLegendTap:)];
        [self.legendContainer addGestureRecognizer:self.legendTapGesture];
    }
    self.legendTapGesture.enabled = YES;

    CGFloat containerWidth = self.bounds.size.width - 16; // 8pt padding each side
    if (containerWidth < 40) containerWidth = 200; // Fallback before layout
    CGFloat rowHeight = 16.0;
    CGFloat x = 0;
    CGFloat y = 0;

    for (NSUInteger i = 0; i < self.dataSeries.count; i++) {
        NSDictionary *series = self.dataSeries[i];
        UIColor *color = series[@"color"] ?: [UIColor whiteColor];
        NSString *label = series[@"label"] ?: @"";
        BOOL isHidden = [self.hiddenSeriesIndices containsIndex:i];
        CGFloat alpha = isHidden ? 0.3 : 1.0;

        // Measure label width
        UILabel *measureLabel = [[UILabel alloc] init];
        measureLabel.text = label;
        measureLabel.font = [UIFont ha_systemFontOfSize:10 weight:HAFontWeightMedium];
        [measureLabel sizeToFit];
        CGFloat entryWidth = 12 + measureLabel.frame.size.width + 10; // dot(8) + gap(4) + label + spacing

        // Wrap to next line if this entry would overflow
        if (x > 0 && x + entryWidth > containerWidth) {
            x = 0;
            y += rowHeight;
        }

        CGFloat entryStartX = x;

        // Colored dot
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(x, y + 4, 8, 8)];
        dot.backgroundColor = color;
        dot.layer.cornerRadius = 4;
        dot.alpha = alpha;
        [self.legendContainer addSubview:dot];
        x += 12;

        // Label
        UILabel *lbl = [[UILabel alloc] init];
        lbl.text = label;
        lbl.font = [UIFont ha_systemFontOfSize:10 weight:HAFontWeightMedium];
        lbl.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        lbl.alpha = alpha;
        [lbl sizeToFit];
        lbl.frame = CGRectMake(x, y + 1, lbl.frame.size.width, 14);
        [self.legendContainer addSubview:lbl];
        x += lbl.frame.size.width + 10;

        // Store the frame for this entry for hit-testing
        CGRect entryFrame = CGRectMake(entryStartX, y, x - entryStartX, rowHeight);
        [self.legendEntryFrames addObject:[NSValue valueWithCGRect:entryFrame]];
    }

    CGFloat totalHeight = y + rowHeight;
    self.legendHeightConstraint.constant = totalHeight;

    // Legend sits at the very bottom; time axis labels are drawn above it
    self.legendBottomConstraint.constant = -2;
}

- (CGFloat)currentLegendHeight {
    if (self.dataSeries.count <= 1) return 0.0;
    return self.legendHeightConstraint.constant;
}

- (void)handleLegendTap:(UITapGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.legendContainer];

    // Find which legend entry was tapped
    NSInteger tappedIndex = -1;
    for (NSUInteger i = 0; i < self.legendEntryFrames.count; i++) {
        CGRect frame = [self.legendEntryFrames[i] CGRectValue];
        if (CGRectContainsPoint(frame, point)) {
            tappedIndex = i;
            break;
        }
    }

    if (tappedIndex < 0 || tappedIndex >= (NSInteger)self.dataSeries.count) return;

    // Count currently visible series
    NSUInteger visibleCount = 0;
    for (NSUInteger i = 0; i < self.dataSeries.count; i++) {
        if (![self.hiddenSeriesIndices containsIndex:i]) {
            visibleCount++;
        }
    }

    // Prevent hiding the last visible series
    BOOL isCurrentlyHidden = [self.hiddenSeriesIndices containsIndex:tappedIndex];
    if (!isCurrentlyHidden && visibleCount <= 1) {
        return; // Can't hide the last visible series
    }

    // Toggle the series
    if (isCurrentlyHidden) {
        [self.hiddenSeriesIndices removeIndex:tappedIndex];
    } else {
        [self.hiddenSeriesIndices addIndex:tappedIndex];
    }

    // Update legend alpha for the tapped entry
    CGFloat newAlpha = isCurrentlyHidden ? 1.0 : 0.3;
    NSUInteger subviewIndex = tappedIndex * 2; // Each entry has 2 subviews (dot + label)
    if (subviewIndex + 1 < self.legendContainer.subviews.count) {
        self.legendContainer.subviews[subviewIndex].alpha = newAlpha;     // Dot
        self.legendContainer.subviews[subviewIndex + 1].alpha = newAlpha; // Label
    }

    // Redraw the graph
    [self updatePaths];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradientLayer.frame = self.bounds;

    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.bounds.size.width;
        CGFloat h = self.bounds.size.height;
        // Legend container at bottom
        CGFloat legendH = self.legendHeightConstraint ? self.legendHeightConstraint.constant : 0;
        if (!self.legendContainer.hidden && legendH > 0) {
            self.legendContainer.frame = CGRectMake(8, h - legendH - 2, w - 16, legendH);
        }
        // Tooltip internal layout
        if (!self.tooltipView.hidden) {
            CGFloat tw = self.tooltipView.bounds.size.width;
            self.tooltipValueLabel.frame = CGRectMake(6, 3, tw - 12, 16);
            self.tooltipTimeLabel.frame = CGRectMake(6, 20, tw - 12, 12);
        }
    }

    CGSize newSize = self.bounds.size;
    if (CGSizeEqualToSize(newSize, self.lastLayoutSize)) return;
    self.lastLayoutSize = newSize;
    if (self.timelineData.count > 0) {
        [self clearTimelineLayers];
        [self updateTimelineBars];
    } else {
        [self updatePaths];
    }
}

#pragma mark - Path rendering

- (void)updatePaths {
    if (CGRectIsEmpty(self.bounds)) return;

    if (self.dataSeries.count > 0) {
        [self updateMultiSeriesPaths];
    } else {
        [self updateSingleSeriesPath];
    }
}

- (void)updateSingleSeriesPath {
    // Ensure we have exactly one line layer
    if (self.lineLayers.count == 0) return;
    CAShapeLayer *lineLayer = self.lineLayers.firstObject;

    if (self.dataPoints.count < 2) {
        lineLayer.path = nil;
        self.fillMaskLayer.path = nil;
        return;
    }

    // Update colors
    UIColor *fill = self.fillColor ?: [self.lineColor colorWithAlphaComponent:0.3];
    lineLayer.strokeColor = self.lineColor.CGColor;
    self.gradientLayer.colors = @[
        (id)[fill colorWithAlphaComponent:0.5].CGColor,
        (id)[fill colorWithAlphaComponent:0.05].CGColor
    ];

    // Compute min/max for Y scaling
    double minVal = HUGE_VAL, maxVal = -HUGE_VAL;
    double minTime = HUGE_VAL, maxTime = -HUGE_VAL;
    for (NSDictionary *pt in self.dataPoints) {
        double v = [pt[@"value"] doubleValue];
        double t = [pt[@"timestamp"] doubleValue];
        if (v < minVal) minVal = v;
        if (v > maxVal) maxVal = v;
        if (t < minTime) minTime = t;
        if (t > maxTime) maxTime = t;
    }

    // Add 10% padding to Y range
    double yRange = maxVal - minVal;
    if (yRange < 0.001) yRange = 1.0;
    double yPad = yRange * 0.1;
    minVal -= yPad;
    maxVal += yPad;
    yRange = maxVal - minVal;

    double xRange = maxTime - minTime;
    if (xRange < 1.0) xRange = 1.0;

    // Store for Phase 4 tooltip hit-testing and axis labels
    self.currentMinVal = minVal;
    self.currentMaxVal = maxVal;
    self.currentMinTime = minTime;
    self.currentMaxTime = maxTime;

    CGFloat leftPad = [self graphAreaLeftPadding];
    CGFloat rightPad = [self graphAreaRightPadding];
    CGFloat bottomPad = [self graphAreaBottomPadding];
    CGFloat w = self.bounds.size.width - leftPad - rightPad;
    CGFloat h = self.bounds.size.height;
    CGFloat insetY = 2.0;
    CGFloat drawH = h - insetY * 2 - bottomPad;
    CGFloat fillBottom = h - bottomPad;

    // Build line path
    UIBezierPath *linePath = [UIBezierPath bezierPath];
    UIBezierPath *fillPath = self.lightweight ? nil : [UIBezierPath bezierPath];

    BOOL first = YES;
    CGPoint lastPoint = CGPointZero;
    for (NSDictionary *pt in self.dataPoints) {
        double v = [pt[@"value"] doubleValue];
        double t = [pt[@"timestamp"] doubleValue];
        CGFloat x = leftPad + (CGFloat)((t - minTime) / xRange) * w;
        CGFloat y = insetY + drawH - (CGFloat)((v - minVal) / yRange) * drawH;
        CGPoint p = CGPointMake(x, y);

        if (first) {
            [linePath moveToPoint:p];
            [fillPath moveToPoint:CGPointMake(x, fillBottom)];
            [fillPath addLineToPoint:p];
            first = NO;
        } else {
            [linePath addLineToPoint:p];
            [fillPath addLineToPoint:p];
        }
        lastPoint = p;
    }

    lineLayer.path = linePath.CGPath;

    if (!self.lightweight) {
        [fillPath addLineToPoint:CGPointMake(lastPoint.x, fillBottom)];
        [fillPath closePath];
        self.fillMaskLayer.path = fillPath.CGPath;
    }

    [self updateAxisLabels];
}

- (void)updateMultiSeriesPaths {
    if (self.dataSeries.count == 0 || self.lineLayers.count == 0) return;

    // Compute per-group min/max ranges (skipping hidden series)
    NSMutableArray<NSMutableDictionary *> *mutableGroups = [NSMutableArray array];
    for (NSDictionary *group in self.axisGroups) {
        [mutableGroups addObject:[group mutableCopy]];
    }

    __block double minTime = HUGE_VAL, maxTime = -HUGE_VAL;

    for (NSUInteger gi = 0; gi < mutableGroups.count; gi++) {
        NSMutableDictionary *group = mutableGroups[gi];
        NSIndexSet *indices = group[@"indices"];
        __block double gMin = HUGE_VAL, gMax = -HUGE_VAL;

        [indices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            // Skip hidden series
            if ([self.hiddenSeriesIndices containsIndex:idx]) return;

            NSDictionary *series = self.dataSeries[idx];
            NSArray *points = series[@"points"];
            for (NSDictionary *pt in points) {
                double v = [pt[@"value"] doubleValue];
                double t = [pt[@"timestamp"] doubleValue];
                if (v < gMin) gMin = v;
                if (v > gMax) gMax = v;
                if (t < minTime) minTime = t;
                if (t > maxTime) maxTime = t;
            }
        }];

        // Add 10% padding to Y range for this group
        if (gMin <= gMax) {
            double yRange = gMax - gMin;
            if (yRange < 0.001) yRange = 1.0;
            double yPad = yRange * 0.1;
            gMin -= yPad;
            gMax += yPad;
        } else {
            // No valid data for this group (all series hidden)
            gMin = 0.0;
            gMax = 1.0;
        }

        group[@"yMin"] = @(gMin);
        group[@"yMax"] = @(gMax);
    }

    // Update stored groups with computed ranges
    self.axisGroups = [mutableGroups copy];

    // For backward compat with single-axis: store first group's range as "current"
    if (mutableGroups.count > 0) {
        self.currentMinVal = [mutableGroups[0][@"yMin"] doubleValue];
        self.currentMaxVal = [mutableGroups[0][@"yMax"] doubleValue];
    } else {
        self.currentMinVal = 0.0;
        self.currentMaxVal = 1.0;
    }

    if (minTime > maxTime) {
        // No valid data
        for (CAShapeLayer *layer in self.lineLayers) {
            layer.path = nil;
        }
        self.fillMaskLayer.path = nil;
        return;
    }

    double xRange = maxTime - minTime;
    if (xRange < 1.0) xRange = 1.0;

    self.currentMinTime = minTime;
    self.currentMaxTime = maxTime;

    CGFloat leftPad = [self graphAreaLeftPadding];
    CGFloat rightPad = [self graphAreaRightPadding];
    CGFloat bottomPad = [self graphAreaBottomPadding];
    CGFloat w = self.bounds.size.width - leftPad - rightPad;
    CGFloat h = self.bounds.size.height;
    CGFloat legendH = [self currentLegendHeight];
    CGFloat insetY = 2.0;
    CGFloat drawH = h - insetY * 2 - legendH - bottomPad;
    if (drawH < 10) drawH = 10;
    CGFloat fillBottom = h - legendH - bottomPad;

    // Render each series
    for (NSUInteger i = 0; i < self.dataSeries.count && i < self.lineLayers.count; i++) {
        NSDictionary *series = self.dataSeries[i];
        NSArray *points = series[@"points"];
        UIColor *color = series[@"color"] ?: self.lineColor;
        CAShapeLayer *lineLayer = self.lineLayers[i];
        lineLayer.strokeColor = color.CGColor;

        // Skip hidden series — clear their paths
        if ([self.hiddenSeriesIndices containsIndex:i]) {
            lineLayer.path = nil;
            if (i == 0) self.fillMaskLayer.path = nil;
            continue;
        }

        if (points.count < 2) {
            lineLayer.path = nil;
            if (i == 0) self.fillMaskLayer.path = nil;
            continue;
        }

        // Get this series' Y axis group
        NSNumber *groupIndexNum = self.seriesIndexToGroupIndex[@(i)];
        NSUInteger groupIndex = groupIndexNum ? [groupIndexNum unsignedIntegerValue] : 0;
        NSDictionary *group = (groupIndex < self.axisGroups.count) ? self.axisGroups[groupIndex] : nil;
        double seriesMinVal = group ? [group[@"yMin"] doubleValue] : 0.0;
        double seriesMaxVal = group ? [group[@"yMax"] doubleValue] : 1.0;
        double seriesYRange = seriesMaxVal - seriesMinVal;
        if (seriesYRange < 0.001) seriesYRange = 1.0;

        UIBezierPath *linePath = [UIBezierPath bezierPath];
        // Gradient fill only for first VISIBLE series, non-lightweight
        // Check if this is the first visible series (not just i == 0)
        BOOL isFirstVisible = YES;
        for (NSUInteger j = 0; j < i; j++) {
            if (![self.hiddenSeriesIndices containsIndex:j]) {
                isFirstVisible = NO;
                break;
            }
        }
        UIBezierPath *fillPath = (isFirstVisible && !self.lightweight) ? [UIBezierPath bezierPath] : nil;

        BOOL first = YES;
        CGPoint lastPoint = CGPointZero;
        for (NSDictionary *pt in points) {
            double v = [pt[@"value"] doubleValue];
            double t = [pt[@"timestamp"] doubleValue];
            CGFloat x = leftPad + (CGFloat)((t - minTime) / xRange) * w;
            CGFloat y = insetY + drawH - (CGFloat)((v - seriesMinVal) / seriesYRange) * drawH;
            CGPoint p = CGPointMake(x, y);

            if (first) {
                [linePath moveToPoint:p];
                [fillPath moveToPoint:CGPointMake(x, fillBottom)];
                [fillPath addLineToPoint:p];
                first = NO;
            } else {
                [linePath addLineToPoint:p];
                [fillPath addLineToPoint:p];
            }
            lastPoint = p;
        }

        lineLayer.path = linePath.CGPath;

        if (isFirstVisible && !self.lightweight) {
            // Update gradient for first visible series color
            UIColor *fill = [color colorWithAlphaComponent:0.3];
            self.gradientLayer.colors = @[
                (id)[fill colorWithAlphaComponent:0.5].CGColor,
                (id)[fill colorWithAlphaComponent:0.05].CGColor
            ];
            [fillPath addLineToPoint:CGPointMake(lastPoint.x, fillBottom)];
            [fillPath closePath];
            self.fillMaskLayer.path = fillPath.CGPath;
        }
    }

    [self updateAxisLabels];
}

#pragma mark - Axis Labels

- (void)removeOldAxisLabels {
    for (UILabel *label in self.timeAxisLabels) {
        [label removeFromSuperview];
    }
    [self.timeAxisLabels removeAllObjects];
    for (UILabel *label in self.valueAxisLabels) {
        [label removeFromSuperview];
    }
    [self.valueAxisLabels removeAllObjects];
}

- (void)updateAxisLabels {
    [self removeOldAxisLabels];

    // Skip axis labels entirely on lightweight devices or when disabled
    if (!self.showAxisLabels || self.lightweight) return;

    UIFont *axisFont = [UIFont systemFontOfSize:9];
    UIColor *axisColor = [HATheme tertiaryTextColor];
    BOOL isTimeline = (self.timelineData.count > 0);

    double minTime = self.currentMinTime;
    double maxTime = self.currentMaxTime;
    double timeRange = maxTime - minTime;
    if (timeRange < 1.0) return; // No meaningful range to label

    // --- Value labels — skip for timeline bars ---
    if (!isTimeline) {
        CGFloat leftPad = [self graphAreaLeftPadding];
        CGFloat rightPad = [self graphAreaRightPadding];
        CGFloat bottomPad = [self graphAreaBottomPadding];
        CGFloat h = self.bounds.size.height;
        CGFloat insetY = 2.0;
        CGFloat legendH = [self currentLegendHeight];
        CGFloat drawH = h - insetY * 2 - bottomPad - legendH;
        if (drawH < 10) drawH = 10;

        if (self.axisGroups.count > 0) {
            // Multi-axis: render per-group Y axes
            CGFloat viewWidth = self.bounds.size.width;

            for (NSUInteger gi = 0; gi < self.axisGroups.count; gi++) {
                NSDictionary *group = self.axisGroups[gi];
                double minVal = [group[@"yMin"] doubleValue];
                double maxVal = [group[@"yMax"] doubleValue];
                double valRange = maxVal - minVal;
                if (valRange < 0.0001) valRange = 1.0;

                NSString *unit = group[@"unit"];
                BOOL isLeftAxis = (gi == 0);
                BOOL useIntegers = (valRange > 10.0);
                NSString *fmt = useIntegers ? @"%.0f" : @"%.1f";

                // Position: left axis at left edge, subsequent axes stacked from right edge
                CGFloat axisX = 0;
                CGFloat axisWidth = 32.0;
                NSTextAlignment alignment = NSTextAlignmentRight;

                if (isLeftAxis) {
                    axisX = 0;
                    axisWidth = leftPad - 3.0;
                    alignment = NSTextAlignmentRight;
                } else {
                    // Right-side axes: stack from right edge inward
                    NSUInteger rightIndex = gi - 1;
                    axisX = viewWidth - rightPad + rightIndex * 35.0;
                    axisWidth = 32.0;
                    alignment = NSTextAlignmentLeft;
                }

                // Unit label at top
                if (unit.length > 0) {
                    UILabel *unitLabel = [[UILabel alloc] init];
                    unitLabel.text = unit;
                    unitLabel.font = [UIFont ha_systemFontOfSize:8 weight:HAFontWeightMedium];
                    unitLabel.textColor = [axisColor colorWithAlphaComponent:0.7];
                    unitLabel.textAlignment = alignment;
                    unitLabel.frame = CGRectMake(axisX, insetY - 2, axisWidth, 10);
                    [self addSubview:unitLabel];
                    [self.valueAxisLabels addObject:unitLabel];
                }

                // Value labels
                NSUInteger valueCount = 5;
                for (NSUInteger i = 0; i < valueCount; i++) {
                    double fraction = (double)i / (double)(valueCount - 1);
                    double val = minVal + fraction * valRange;
                    CGFloat y = insetY + drawH - (CGFloat)(fraction) * drawH;

                    UILabel *lbl = [[UILabel alloc] init];
                    lbl.text = [NSString stringWithFormat:fmt, val];
                    lbl.font = axisFont;
                    lbl.textColor = axisColor;
                    lbl.textAlignment = alignment;
                    lbl.frame = CGRectMake(axisX, y - 6.0, axisWidth, 12.0);
                    [self addSubview:lbl];
                    [self.valueAxisLabels addObject:lbl];
                }
            }
        } else {
            // Single-series: render one Y-axis using currentMinVal/currentMaxVal
            double minVal = self.currentMinVal;
            double maxVal = self.currentMaxVal;
            double valRange = maxVal - minVal;
            if (valRange < 0.0001) valRange = 1.0;

            BOOL useIntegers = (valRange > 10.0);
            NSString *fmt = useIntegers ? @"%.0f" : @"%.1f";

            NSUInteger valueCount = 5;
            for (NSUInteger i = 0; i < valueCount; i++) {
                double fraction = (double)i / (double)(valueCount - 1);
                double val = minVal + fraction * valRange;
                CGFloat y = insetY + drawH - (CGFloat)(fraction) * drawH;

                UILabel *lbl = [[UILabel alloc] init];
                lbl.text = [NSString stringWithFormat:fmt, val];
                lbl.font = axisFont;
                lbl.textColor = axisColor;
                lbl.textAlignment = NSTextAlignmentRight;
                lbl.frame = CGRectMake(0, y - 6.0, leftPad - 3.0, 12.0);
                [self addSubview:lbl];
                [self.valueAxisLabels addObject:lbl];
            }
        }
    }

    // --- Time labels (bottom edge, above legend if present) ---
    CGFloat leftPad = isTimeline ? 0.0 : [self graphAreaLeftPadding];
    CGFloat rightPad = isTimeline ? 0.0 : [self graphAreaRightPadding];
    CGFloat drawW = self.bounds.size.width - leftPad - rightPad;
    CGFloat legendH = [self currentLegendHeight];
    CGFloat bottomY = self.bounds.size.height - [self graphAreaBottomPadding] - legendH;

    // For timeline bars, time labels start at the bar area X offset
    CGFloat timeAreaX = leftPad;
    CGFloat timeAreaW = drawW;
    if (isTimeline) {
        // Recompute barAreaX/W for timeline to align time labels with bars
        CGFloat labelWidth = 0;
        UIFont *labelFont = [UIFont ha_systemFontOfSize:11 weight:HAFontWeightMedium];
        for (NSDictionary *entity in self.timelineData) {
            NSString *label = entity[@"label"] ?: @"";
            CGSize sz = [label ha_sizeWithAttributes:@{HAFontAttributeName: labelFont}];
            if (sz.width > labelWidth) labelWidth = sz.width;
        }
        CGFloat w = self.bounds.size.width;
        if (labelWidth > w * 0.35) labelWidth = w * 0.35;
        if (labelWidth < 30) labelWidth = 30;
        CGFloat barAreaX = labelWidth + 6.0 + 8.0;
        CGFloat barAreaW = w - barAreaX - 4.0;
        if (barAreaW < 20) barAreaW = 20;
        timeAreaX = barAreaX;
        timeAreaW = barAreaW;
    }

    // Choose time format based on total range
    NSDateFormatter *timeFmt = sCachedTimeFmt();
    if (timeRange > 604800) {
        // > 7 days
        timeFmt.dateFormat = @"d/M HH:mm";
    } else if (timeRange > 86400) {
        // > 24 hours
        timeFmt.dateFormat = @"MMM d";
    } else {
        // <= 24 hours
        timeFmt.dateFormat = @"HH:mm";
    }

    NSUInteger timeCount = (timeRange > 86400) ? 4 : 5;
    // Use fewer labels if drawing area is narrow
    if (timeAreaW < 150) timeCount = 3;

    for (NSUInteger i = 0; i < timeCount; i++) {
        double fraction = (double)i / (double)(timeCount - 1);
        double t = minTime + fraction * timeRange;
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:t];
        NSString *text = [timeFmt stringFromDate:date];

        CGFloat x = timeAreaX + (CGFloat)(fraction) * timeAreaW;

        UILabel *lbl = [[UILabel alloc] init];
        lbl.text = text;
        lbl.font = axisFont;
        lbl.textColor = axisColor;
        lbl.textAlignment = NSTextAlignmentCenter;
        [lbl sizeToFit];

        // Center the label on x, but clamp to bounds
        CGFloat lblW = lbl.frame.size.width;
        CGFloat lblX = x - lblW / 2.0;
        if (lblX < 0) lblX = 0;
        if (lblX + lblW > self.bounds.size.width) lblX = self.bounds.size.width - lblW;
        lbl.frame = CGRectMake(lblX, bottomY + 2.0, lblW, 14.0);

        [self addSubview:lbl];
        [self.timeAxisLabels addObject:lbl];
    }
}

#pragma mark - Inspection (Tooltip)

- (void)handleInspect:(UILongPressGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self];
    CGFloat leftPad = [self graphAreaLeftPadding];
    CGFloat rightPad = [self graphAreaRightPadding];
    CGFloat bottomPad = [self graphAreaBottomPadding];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat drawW = w - leftPad - rightPad;
    CGFloat drawH = h - bottomPad;

    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        // Clamp X to graph area
        CGFloat x = MAX(leftPad, MIN(point.x, w - rightPad));
        CGFloat fraction = (drawW > 0) ? (x - leftPad) / drawW : 0;
        fraction = MAX(0.0, MIN(1.0, fraction));

        NSTimeInterval timestamp = self.currentMinTime + fraction * (self.currentMaxTime - self.currentMinTime);

        // Position crosshair
        self.crosshairLine.hidden = NO;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.crosshairLine.frame = CGRectMake(x - 0.5, 0, 1.0, drawH);
        [CATransaction commit];

        // Determine value and format tooltip
        NSString *valueText = nil;
        NSString *stateText = nil;
        NSTimeInterval duration = 0;
        double value = NAN;

        if (self.timelineData.count > 0) {
            // Timeline mode: find segment at timestamp
            NSDictionary *firstEntity = self.timelineData.firstObject;
            NSArray *segments = firstEntity[@"segments"];
            for (NSDictionary *seg in segments) {
                NSTimeInterval segStart = [seg[@"start"] doubleValue];
                NSTimeInterval segEnd = [seg[@"end"] doubleValue];
                if (timestamp >= segStart && timestamp <= segEnd) {
                    stateText = seg[@"state"];
                    duration = segEnd - segStart;
                    break;
                }
            }
            if (stateText) {
                // Format duration
                NSInteger totalSec = (NSInteger)duration;
                NSInteger hrs = totalSec / 3600;
                NSInteger mins = (totalSec % 3600) / 60;
                if (hrs > 0) {
                    valueText = [NSString stringWithFormat:@"%@ (%ldh %ldm)", [stateText capitalizedString], (long)hrs, (long)mins];
                } else {
                    valueText = [NSString stringWithFormat:@"%@ (%ldm)", [stateText capitalizedString], (long)mins];
                }
            } else {
                valueText = @"\u2014";
            }
        } else if (self.dataSeries.count > 1) {
            // Multi-series: show ALL visible series
            NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] init];
            NSUInteger visibleCount = 0;
            CGFloat maxWidth = 0;

            for (NSUInteger i = 0; i < self.dataSeries.count; i++) {
                if ([self.hiddenSeriesIndices containsIndex:i]) continue;

                NSDictionary *series = self.dataSeries[i];
                NSArray *points = series[@"points"];
                UIColor *color = series[@"color"] ?: [UIColor whiteColor];
                NSString *label = series[@"label"] ?: @"";
                NSString *unit = series[@"unit"] ?: @"";

                if (points.count == 0) continue;

                double val = [self interpolateValueAtTimestamp:timestamp fromPoints:points];
                NSString *valStr = [NSString stringWithFormat:@"%.1f", val];
                if (unit.length > 0) {
                    valStr = [NSString stringWithFormat:@"%@ %@", valStr, unit];
                }

                // Build line: "● Label: 25.5 °C"
                NSString *line = [NSString stringWithFormat:@"%@ %@: %@", @"●", label, valStr];
                if (visibleCount > 0) {
                    line = [@"\n" stringByAppendingString:line];
                }

                // Color the dot
                NSMutableAttributedString *lineAttr = [[NSMutableAttributedString alloc] initWithString:line];
                NSRange dotRange = [line rangeOfString:@"●"];
                if (dotRange.location != NSNotFound) {
                    [lineAttr addAttribute:HAForegroundColorAttributeName value:color range:dotRange];
                }
                [lineAttr addAttribute:HAFontAttributeName value:[UIFont ha_monospacedDigitSystemFontOfSize:12 weight:HAFontWeightBold] range:NSMakeRange(0, lineAttr.length)];
                [lineAttr addAttribute:HAForegroundColorAttributeName value:[UIColor whiteColor] range:NSMakeRange(0, lineAttr.length)];

                [attrStr appendAttributedString:lineAttr];

                // Track width for sizing
                CGSize lineSize = [line ha_sizeWithAttributes:@{HAFontAttributeName: [UIFont ha_monospacedDigitSystemFontOfSize:12 weight:HAFontWeightBold]}];
                if (lineSize.width > maxWidth) maxWidth = lineSize.width;

                visibleCount++;
                // Store first series value for delegate (backward compat)
                if (visibleCount == 1) value = val;
            }

            if (visibleCount > 0) {
                self.tooltipValueLabel.attributedText = attrStr;
            } else {
                self.tooltipValueLabel.text = @"\u2014";
            }

            // Compute tooltip dimensions
            CGFloat lineHeight = 14.0;
            CGFloat timeHeight = 12.0;
            CGFloat tooltipW = MAX(100, MIN(200, maxWidth + 16));
            CGFloat tooltipH = 6 + (visibleCount * lineHeight) + timeHeight + 6;
            CGFloat tooltipX = x - tooltipW / 2.0;
            tooltipX = MAX(2, MIN(w - tooltipW - 2, tooltipX));
            CGFloat tooltipY = MAX(2, point.y - tooltipH - 10);
            if (tooltipY < 2) tooltipY = point.y + 10;

            self.tooltipView.frame = CGRectMake(tooltipX, tooltipY, tooltipW, tooltipH);
        } else {
            // Single-series: backward compatible display
            NSArray *points = self.dataPoints;
            if (self.dataSeries.count > 0) {
                // Use first VISIBLE series
                NSUInteger visibleIndex = NSNotFound;
                for (NSUInteger i = 0; i < self.dataSeries.count; i++) {
                    if (![self.hiddenSeriesIndices containsIndex:i]) {
                        visibleIndex = i;
                        break;
                    }
                }
                if (visibleIndex != NSNotFound) {
                    points = self.dataSeries[visibleIndex][@"points"];
                } else {
                    points = nil; // All series hidden (shouldn't happen, but defensive)
                }
            }
            if (points.count > 0) {
                value = [self interpolateValueAtTimestamp:timestamp fromPoints:points];
                valueText = [NSString stringWithFormat:@"%.1f", value];
            } else {
                valueText = @"\u2014";
            }

            self.tooltipValueLabel.text = valueText;

            // Size tooltip to fit content
            CGFloat tooltipW = MAX(100, MIN(180, [valueText ha_sizeWithAttributes:@{HAFontAttributeName: self.tooltipValueLabel.font}].width + 20));
            CGFloat tooltipH = 36;
            CGFloat tooltipX = x - tooltipW / 2.0;
            tooltipX = MAX(2, MIN(w - tooltipW - 2, tooltipX));
            CGFloat tooltipY = MAX(2, point.y - tooltipH - 10);
            if (tooltipY < 2) tooltipY = point.y + 10; // Below if no room above

            self.tooltipView.frame = CGRectMake(tooltipX, tooltipY, tooltipW, tooltipH);
        }

        // Format time
        NSDateFormatter *timeFmt = sCachedTimeFmt();
        NSTimeInterval totalRange = self.currentMaxTime - self.currentMinTime;
        if (totalRange < 86400) {
            timeFmt.dateFormat = @"HH:mm:ss";
        } else {
            timeFmt.dateFormat = @"MMM d, HH:mm";
        }
        NSString *timeText = [timeFmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
        self.tooltipTimeLabel.text = timeText;

        self.tooltipView.hidden = NO;

        // Delegate
        if ([self.delegate respondsToSelector:@selector(graphView:didInspectValue:timestamp:state:duration:)]) {
            [self.delegate graphView:self didInspectValue:value timestamp:timestamp state:stateText duration:duration];
        }

    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        // Fade out
        [UIView animateWithDuration:0.2 animations:^{
            self.tooltipView.alpha = 0;
        } completion:^(BOOL finished) {
            self.tooltipView.hidden = YES;
            self.tooltipView.alpha = 1.0;
            self.crosshairLine.hidden = YES;
        }];

        if ([self.delegate respondsToSelector:@selector(graphViewDidEndInspection:)]) {
            [self.delegate graphViewDidEndInspection:self];
        }
    }
}

- (double)interpolateValueAtTimestamp:(NSTimeInterval)timestamp fromPoints:(NSArray<NSDictionary *> *)points {
    if (points.count == 0) return NAN;
    if (points.count == 1) return [points[0][@"value"] doubleValue];

    // Binary search for bracketing points
    NSDictionary *prev = points.firstObject;
    NSDictionary *next = points.lastObject;

    for (NSUInteger i = 0; i < points.count - 1; i++) {
        NSTimeInterval t0 = [points[i][@"timestamp"] doubleValue];
        NSTimeInterval t1 = [points[i + 1][@"timestamp"] doubleValue];
        if (timestamp >= t0 && timestamp <= t1) {
            prev = points[i];
            next = points[i + 1];
            break;
        }
    }

    double t0 = [prev[@"timestamp"] doubleValue];
    double t1 = [next[@"timestamp"] doubleValue];
    double v0 = [prev[@"value"] doubleValue];
    double v1 = [next[@"value"] doubleValue];

    if (fabs(t1 - t0) < 0.001) return v0;
    double frac = (timestamp - t0) / (t1 - t0);
    frac = MAX(0.0, MIN(1.0, frac));
    return v0 + frac * (v1 - v0);
}

#pragma mark - Pinch-to-Zoom

- (void)handlePinch:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.anchorStartTime = (self.visibleStartTime > 0) ? self.visibleStartTime : self.currentMinTime;
        self.anchorEndTime = (self.visibleEndTime > 0) ? self.visibleEndTime : self.currentMaxTime;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat scale = MAX(0.1, gesture.scale);
        NSTimeInterval anchorRange = self.anchorEndTime - self.anchorStartTime;
        NSTimeInterval newRange = anchorRange / scale;
        NSTimeInterval mid = (self.anchorStartTime + self.anchorEndTime) / 2.0;
        NSTimeInterval newStart = mid - newRange / 2.0;
        NSTimeInterval newEnd = mid + newRange / 2.0;

        // Clamp to data bounds
        if (newStart < self.currentMinTime) { newStart = self.currentMinTime; newEnd = newStart + newRange; }
        if (newEnd > self.currentMaxTime) { newEnd = self.currentMaxTime; newStart = newEnd - newRange; }
        newStart = MAX(newStart, self.currentMinTime);
        newEnd = MIN(newEnd, self.currentMaxTime);

        self.visibleStartTime = newStart;
        self.visibleEndTime = newEnd;
        NSTimeInterval fullRange = self.currentMaxTime - self.currentMinTime;
        _zoomScale = (fullRange > 0) ? (CGFloat)(fullRange / (newEnd - newStart)) : 1.0;
        [self setNeedsLayout];
        [self layoutIfNeeded];
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        NSTimeInterval fullRange = self.currentMaxTime - self.currentMinTime;
        NSTimeInterval visRange = self.visibleEndTime - self.visibleStartTime;
        if (fullRange > 0 && fabs(visRange / fullRange - 1.0) > 0.1) {
            if ([self.delegate respondsToSelector:@selector(graphView:didZoomToStartTime:endTime:)]) {
                [self.delegate graphView:self didZoomToStartTime:self.visibleStartTime endTime:self.visibleEndTime];
            }
        }
    }
}

#pragma mark - Pan/Scrub

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self];

    if (self.zoomScale <= 1.01) {
        // Not zoomed: act as scrub (crosshair + tooltip)
        if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
            CGFloat leftPad = [self graphAreaLeftPadding];
            CGFloat rightPad = [self graphAreaRightPadding];
            CGFloat w = self.bounds.size.width;
            CGFloat drawW = w - leftPad - rightPad;
            CGFloat drawH = self.bounds.size.height - [self graphAreaBottomPadding];
            CGFloat x = MAX(leftPad, MIN(point.x, w - rightPad));
            CGFloat fraction = (drawW > 0) ? (x - leftPad) / drawW : 0;
            fraction = MAX(0.0, MIN(1.0, fraction));
            NSTimeInterval timestamp = self.currentMinTime + fraction * (self.currentMaxTime - self.currentMinTime);

            self.crosshairLine.hidden = NO;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.crosshairLine.frame = CGRectMake(x - 0.5, 0, 1.0, drawH);
            [CATransaction commit];

            if (self.dataSeries.count > 1) {
                // Multi-series: show ALL visible series
                NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] init];
                NSUInteger visibleCount = 0;
                CGFloat maxWidth = 0;

                for (NSUInteger i = 0; i < self.dataSeries.count; i++) {
                    if ([self.hiddenSeriesIndices containsIndex:i]) continue;

                    NSDictionary *series = self.dataSeries[i];
                    NSArray *points = series[@"points"];
                    UIColor *color = series[@"color"] ?: [UIColor whiteColor];
                    NSString *label = series[@"label"] ?: @"";
                    NSString *unit = series[@"unit"] ?: @"";

                    if (points.count == 0) continue;

                    double val = [self interpolateValueAtTimestamp:timestamp fromPoints:points];
                    NSString *valStr = [NSString stringWithFormat:@"%.1f", val];
                    if (unit.length > 0) {
                        valStr = [NSString stringWithFormat:@"%@ %@", valStr, unit];
                    }

                    // Build line: "● Label: 25.5 °C"
                    NSString *line = [NSString stringWithFormat:@"%@ %@: %@", @"●", label, valStr];
                    if (visibleCount > 0) {
                        line = [@"\n" stringByAppendingString:line];
                    }

                    // Color the dot
                    NSMutableAttributedString *lineAttr = [[NSMutableAttributedString alloc] initWithString:line];
                    NSRange dotRange = [line rangeOfString:@"●"];
                    if (dotRange.location != NSNotFound) {
                        [lineAttr addAttribute:HAForegroundColorAttributeName value:color range:dotRange];
                    }
                    [lineAttr addAttribute:HAFontAttributeName value:[UIFont ha_monospacedDigitSystemFontOfSize:12 weight:HAFontWeightBold] range:NSMakeRange(0, lineAttr.length)];
                    [lineAttr addAttribute:HAForegroundColorAttributeName value:[UIColor whiteColor] range:NSMakeRange(0, lineAttr.length)];

                    [attrStr appendAttributedString:lineAttr];

                    // Track width for sizing
                    CGSize lineSize = [line ha_sizeWithAttributes:@{HAFontAttributeName: [UIFont ha_monospacedDigitSystemFontOfSize:12 weight:HAFontWeightBold]}];
                    if (lineSize.width > maxWidth) maxWidth = lineSize.width;

                    visibleCount++;
                }

                if (visibleCount > 0) {
                    self.tooltipValueLabel.attributedText = attrStr;
                } else {
                    self.tooltipValueLabel.text = @"\u2014";
                }

                // Compute tooltip dimensions
                CGFloat lineHeight = 14.0;
                CGFloat timeHeight = 12.0;
                CGFloat tooltipW = MAX(100, MIN(200, maxWidth + 16));
                CGFloat tooltipH = 6 + (visibleCount * lineHeight) + timeHeight + 6;
                CGFloat tooltipX = MAX(2, MIN(w - tooltipW - 2, x - tooltipW / 2.0));
                self.tooltipView.frame = CGRectMake(tooltipX, MAX(2, point.y - tooltipH - 10), tooltipW, tooltipH);
            } else {
                // Single-series: backward compatible display
                NSArray *points = self.dataPoints;
                if (self.dataSeries.count > 0) {
                    // Use first VISIBLE series
                    NSUInteger visibleIndex = NSNotFound;
                    for (NSUInteger i = 0; i < self.dataSeries.count; i++) {
                        if (![self.hiddenSeriesIndices containsIndex:i]) {
                            visibleIndex = i;
                            break;
                        }
                    }
                    if (visibleIndex != NSNotFound) {
                        points = self.dataSeries[visibleIndex][@"points"];
                    } else {
                        points = nil;
                    }
                }
                NSString *valueText = @"\u2014";
                if (points.count > 0) {
                    double val = [self interpolateValueAtTimestamp:timestamp fromPoints:points];
                    valueText = [NSString stringWithFormat:@"%.1f", val];
                }

                self.tooltipValueLabel.text = valueText;

                CGFloat tooltipW = 120;
                CGFloat tooltipX = MAX(2, MIN(w - tooltipW - 2, x - tooltipW / 2.0));
                self.tooltipView.frame = CGRectMake(tooltipX, MAX(2, point.y - 46), tooltipW, 36);
            }

            NSDateFormatter *timeFmt = sCachedTimeFmt();
            timeFmt.dateFormat = (self.currentMaxTime - self.currentMinTime < 86400) ? @"HH:mm:ss" : @"MMM d, HH:mm";
            self.tooltipTimeLabel.text = [timeFmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
            self.tooltipView.hidden = NO;
        } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
            [UIView animateWithDuration:0.2 animations:^{
                self.tooltipView.alpha = 0;
            } completion:^(BOOL finished) {
                self.tooltipView.hidden = YES;
                self.tooltipView.alpha = 1.0;
                self.crosshairLine.hidden = YES;
            }];
        }
    } else {
        // Zoomed: shift time window
        if (gesture.state == UIGestureRecognizerStateBegan) {
            self.anchorStartTime = self.visibleStartTime;
            self.anchorEndTime = self.visibleEndTime;
        } else if (gesture.state == UIGestureRecognizerStateChanged) {
            CGPoint translation = [gesture translationInView:self];
            CGFloat drawW = self.bounds.size.width - [self graphAreaLeftPadding] - [self graphAreaRightPadding];
            NSTimeInterval visRange = self.anchorEndTime - self.anchorStartTime;
            NSTimeInterval timeDelta = -(translation.x / drawW) * visRange;
            NSTimeInterval newStart = self.anchorStartTime + timeDelta;
            NSTimeInterval newEnd = self.anchorEndTime + timeDelta;
            if (newStart < self.currentMinTime) { newEnd += (self.currentMinTime - newStart); newStart = self.currentMinTime; }
            if (newEnd > self.currentMaxTime) { newStart -= (newEnd - self.currentMaxTime); newEnd = self.currentMaxTime; }
            newStart = MAX(newStart, self.currentMinTime);
            newEnd = MIN(newEnd, self.currentMaxTime);
            self.visibleStartTime = newStart;
            self.visibleEndTime = newEnd;
            [self setNeedsLayout];
            [self layoutIfNeeded];
        } else if (gesture.state == UIGestureRecognizerStateEnded) {
            if ([self.delegate respondsToSelector:@selector(graphView:didZoomToStartTime:endTime:)]) {
                [self.delegate graphView:self didZoomToStartTime:self.visibleStartTime endTime:self.visibleEndTime];
            }
        }
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    [self resetZoom];
}

- (void)resetZoom {
    self.visibleStartTime = 0;
    self.visibleEndTime = 0;
    _zoomScale = 1.0;
    [self setNeedsLayout];
    [self layoutIfNeeded];
    if ([self.delegate respondsToSelector:@selector(graphView:didZoomToStartTime:endTime:)]) {
        [self.delegate graphView:self didZoomToStartTime:self.currentMinTime endTime:self.currentMaxTime];
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.panGesture) {
        CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self];
        return fabs(velocity.x) > fabs(velocity.y) * 1.5;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ((gestureRecognizer == self.pinchGesture && otherGestureRecognizer == self.panGesture) ||
        (gestureRecognizer == self.panGesture && otherGestureRecognizer == self.pinchGesture)) {
        return YES;
    }
    return NO;
}

#pragma mark - Device Max Points

+ (NSUInteger)maxPointsForDevice {
#if !TARGET_OS_SIMULATOR
    struct utsname systemInfo;
    if (uname(&systemInfo) == 0) {
        NSString *machine = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
        if ([machine hasPrefix:@"iPad2"] || [machine hasPrefix:@"iPad3"] ||
            [machine hasPrefix:@"iPhone4"] || [machine hasPrefix:@"iPod5"]) {
            return 150;
        }
    }
#endif
    return 300;
}

@end
