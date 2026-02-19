#import "HAThermostatGaugeCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"

// Gauge geometry -- proportions matched to HA web's ha-control-circular-slider:
// SVG viewBox 320x320, center (160,160), RADIUS=145, stroke=24
// The slider fills the FULL available width as a square container.
// Everything (arc, text, +/- buttons) is overlaid inside this square.
// Mode bar sits below the square.
static const CGFloat kStrokeSVG      = 24.0;     // stroke width in SVG units
static const CGFloat kSVGSize        = 320.0;    // SVG viewBox dimension

// min/max temp now read from entity attributes (entityMinTemp/entityMaxTemp properties)
// Arc sweep: 270 degrees, starting from bottom-left (135deg) to bottom-right (405deg)
static const CGFloat kStartAngle = 135.0 * M_PI / 180.0;
static const CGFloat kEndAngle   = 405.0 * M_PI / 180.0;

// Thumb hit radius for gesture recognition
static const CGFloat kThumbHitRadius = 40.0;

// Temperature snap step
static const CGFloat kTempStep = 0.5;

// +/- button size (matches HA web 48x48 outlined-icon-button)
static const CGFloat kButtonSize = 48.0;
static const CGFloat kButtonGap  = 24.0; // gap between the two buttons (--ha-space-6)

// Layout constants
static const CGFloat kArcPadding      = 8.0;   // HA web: .container > * { padding: 8px }
static const CGFloat kModeBarHeight   = 42.0;   // HA web: ha-control-button-group ~42px
static const CGFloat kModeBarBottomPad = 12.0;   // HA web: hui-card-features padding 0 12px 12px
static const CGFloat kModeBarSidePad   = 12.0;   // HA web: hui-card-features padding 0 12px 12px
static const CGFloat kArcToModeGap     = 4.0;   // tiny gap between arc square and mode bar
static const CGFloat kModeBarCornerRadius = 12.0; // HA web: subtle rounded corners, NOT pill

// Max arc square size to prevent absurdly tall cells on wide screens
static const CGFloat kMaxArcSquare = 400.0;

// HVAC mode icon mapping
static NSDictionary *_modeIconNames = nil;

// Fill direction for arc
typedef NS_ENUM(NSInteger, HAGaugeFillDirection) {
    HAGaugeFillLeftToRight,  // heat, fan_only, dry: colored arc min->target
    HAGaugeFillRightToLeft,  // cool: colored arc target->max
    HAGaugeFillFull,         // auto, heat_cool: colored arc full range
    HAGaugeFillNone,         // off
};

@interface HAThermostatGaugeCell () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) CAShapeLayer *bgArcLayer;
@property (nonatomic, strong) CAShapeLayer *coloredArcLayer;  // directional range at 0.5 opacity
@property (nonatomic, strong) CAShapeLayer *fgArcLayer;        // active portion at 1.0 opacity
@property (nonatomic, strong) CAShapeLayer *currentTempDotLayer;
@property (nonatomic, strong) CALayer *glowLayer;               // radial glow behind arc
@property (nonatomic, strong) UILabel *tempLabel;
@property (nonatomic, strong) UILabel *targetLabel;
@property (nonatomic, strong) UILabel *modeLabel;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIStackView *modeStack;
@property (nonatomic, strong) NSArray<NSString *> *availableModes;
@property (nonatomic, copy) NSString *currentMode;

// Thumb + drag
@property (nonatomic, strong) UIView *thumbView;
@property (nonatomic, strong) UIPanGestureRecognizer *thumbPanGesture;
@property (nonatomic, assign) BOOL thumbDragging;
@property (nonatomic, assign) CGPoint arcCenter;
@property (nonatomic, assign) CGFloat arcRadius;
@property (nonatomic, assign) CGFloat sliderSize; // cached for scaling calculations
@property (nonatomic, assign) double dragTargetTemp;
@property (nonatomic, strong) UIColor *currentModeColor;
@property (nonatomic, assign) double lastHapticTemp;
@property (nonatomic, assign) HAGaugeFillDirection fillDirection;
@property (nonatomic, strong) UIView *modeBar;
@property (nonatomic, assign) BOOL buttonsVisible;
// Cached current hvac_action for active arc logic
@property (nonatomic, copy) NSString *currentAction;
@property (nonatomic, assign) double entityMinTemp; // from entity.min_temp (fallback 7)
@property (nonatomic, assign) double entityMaxTemp; // from entity.max_temp (fallback 35)
@property (nonatomic, copy) NSString *tempUnitString; // e.g. "°C", "°F", or "°"
// Caches for layout skip / glow bitmap reuse
@property (nonatomic, assign) CGFloat lastLayoutSlider;   // cached slider size for geometry-unchanged skip
@property (nonatomic, strong) UIColor *cachedGlowColor;   // glow bitmap was drawn for this color
@property (nonatomic, assign) CGFloat cachedGlowSize;     // glow bitmap was drawn at this size
@property (nonatomic, strong) UIImage *cachedGlowImage;   // pre-drawn glow bitmap (pre-iOS 12 only)
@property (nonatomic, copy) NSArray<NSString *> *lastBuiltModes; // modes the buttons were built for
@property (nonatomic, copy) NSString *lastBuiltCurrentMode;      // active mode when buttons were built
@end

@implementation HAThermostatGaugeCell

+ (void)initialize {
    if (self != [HAThermostatGaugeCell class]) return;
    _modeIconNames = @{
        @"off":       @"power",
        @"heat":      @"fire",
        @"cool":      @"snowflake",
        @"auto":      @"autorenew",
        @"heat_cool": @"autorenew",
        @"dry":       @"water-percent",
        @"fan_only":  @"fan",
    };
}

+ (CGFloat)preferredHeight {
    return 320.0;
}

+ (CGFloat)preferredHeightForWidth:(CGFloat)width {
    if (width <= 0) return 320.0;
    // HA web architecture: single square container (arc + text + buttons overlaid)
    // followed by mode bar below.
    // arcSquare = full width, capped at kMaxArcSquare.
    CGFloat arcSquare = MIN(width, kMaxArcSquare);
    CGFloat modeArea = kModeBarHeight + kModeBarBottomPad;
    return arcSquare + kArcToModeGap + modeArea;
}

#pragma mark - Geometry Helpers

- (CGFloat)fractionForTemperature:(double)temp {
    CGFloat f = (temp - self.entityMinTemp) / (self.entityMaxTemp - self.entityMinTemp);
    return MIN(MAX(f, 0.0), 1.0);
}

- (CGFloat)angleForFraction:(CGFloat)fraction {
    return kStartAngle + fraction * (kEndAngle - kStartAngle);
}

- (CGPoint)pointOnArcForAngle:(CGFloat)angle {
    return CGPointMake(
        self.arcCenter.x + self.arcRadius * cos(angle),
        self.arcCenter.y + self.arcRadius * sin(angle)
    );
}

- (double)temperatureForAngle:(CGFloat)angle {
    CGFloat sweep = kEndAngle - kStartAngle;
    CGFloat fraction = (angle - kStartAngle) / sweep;
    fraction = MIN(MAX(fraction, 0.0), 1.0);
    double temp = self.entityMinTemp + fraction * (self.entityMaxTemp - self.entityMinTemp);
    // Snap to step
    temp = round(temp / kTempStep) * kTempStep;
    return MIN(MAX(temp, self.entityMinTemp), self.entityMaxTemp);
}

- (CGFloat)angleForPoint:(CGPoint)point {
    CGFloat rawAngle = atan2(point.y - self.arcCenter.y, point.x - self.arcCenter.x);
    // atan2 returns -PI..PI. Our arc is 135deg (3pi/4) to 405deg (9pi/4).
    // Normalize into positive range
    if (rawAngle < 0) rawAngle += 2.0 * M_PI;

    // Dead zone detection: the gap is roughly 45deg..135deg (pi/4..3pi/4)
    // If the touch is in this zone, snap to the nearest endpoint
    if (rawAngle > M_PI / 4.0 && rawAngle < 3.0 * M_PI / 4.0) {
        CGFloat distToStart = fabs(rawAngle - 3.0 * M_PI / 4.0);
        CGFloat distToEnd = fabs(rawAngle - M_PI / 4.0);
        return (distToStart < distToEnd) ? kStartAngle : kEndAngle;
    }

    // Shift into arc range
    if (rawAngle < kStartAngle) rawAngle += 2.0 * M_PI;

    // Clamp
    if (rawAngle < kStartAngle) rawAngle = kStartAngle;
    if (rawAngle > kEndAngle) rawAngle = kEndAngle;
    return rawAngle;
}

- (void)positionThumbAtTemperature:(double)temp {
    CGFloat fraction = [self fractionForTemperature:temp];
    CGFloat angle = [self angleForFraction:fraction];
    CGPoint point = [self pointOnArcForAngle:angle];
    self.thumbView.center = point;
}

- (void)getRGBAComponents:(UIColor *)color out:(CGFloat *)out {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    // Try getRed:green:blue:alpha: first (works for RGB colors)
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        // Fallback for grayscale colors
        CGFloat w = 0;
        [color getWhite:&w alpha:&a];
        r = g = b = w;
    }
    out[0] = r; out[1] = g; out[2] = b; out[3] = a;
}

- (HAGaugeFillDirection)fillDirectionForMode:(NSString *)mode action:(NSString *)action {
    if ([mode isEqualToString:@"off"]) return HAGaugeFillNone;
    if ([action isEqualToString:@"cooling"] || [mode isEqualToString:@"cool"]) return HAGaugeFillRightToLeft;
    if ([mode isEqualToString:@"auto"] || [mode isEqualToString:@"heat_cool"]) return HAGaugeFillFull;
    return HAGaugeFillLeftToRight; // heat, fan_only, dry, default
}

/// Apply the colored arc (0.5 opacity) and active/foreground arc (1.0 opacity).
///
/// HA web architecture (ha-control-circular-slider.ts renderArc):
///   coloredArc: partial range showing the mode's side
///     - heat (mode="start"): min -> target
///     - cool (mode="end"): target -> max
///     - auto/full: min -> max
///   activeArc: shows demand (current actively heating/cooling)
///     - heat: current -> target (only when current < target, i.e. heating)
///     - cool: target -> current (only when target < current, i.e. cooling)
///     - idle: no active arc (just the colored range)
- (void)applyArcFillForTarget:(double)targetTemp
                  currentTemp:(NSNumber *)currentTemp
                    direction:(HAGaugeFillDirection)direction
                       action:(NSString *)action {
    CGFloat targetFraction = [self fractionForTemperature:targetTemp];
    CGFloat currentFraction = currentTemp ? [self fractionForTemperature:currentTemp.doubleValue] : targetFraction;

    switch (direction) {
        case HAGaugeFillLeftToRight: {
            // Heat mode: colored arc from min (0.0) to target
            self.coloredArcLayer.strokeStart = 0.0;
            self.coloredArcLayer.strokeEnd   = targetFraction;

            // Active arc: current -> target ONLY when actively heating
            BOOL isActivelyHeating = [action isEqualToString:@"heating"];
            if (isActivelyHeating && currentTemp && currentTemp.doubleValue < targetTemp) {
                self.fgArcLayer.strokeStart = currentFraction;
                self.fgArcLayer.strokeEnd   = targetFraction;
            } else {
                // Idle: no active arc, just show a dot at target via strokeStart~=strokeEnd
                self.fgArcLayer.strokeStart = targetFraction;
                self.fgArcLayer.strokeEnd   = targetFraction;
            }
            break;
        }
        case HAGaugeFillRightToLeft: {
            // Cool mode: colored arc from target to max (1.0)
            self.coloredArcLayer.strokeStart = targetFraction;
            self.coloredArcLayer.strokeEnd   = 1.0;

            // Active arc: target -> current ONLY when actively cooling
            BOOL isActivelyCooling = [action isEqualToString:@"cooling"];
            if (isActivelyCooling && currentTemp && targetTemp < currentTemp.doubleValue) {
                self.fgArcLayer.strokeStart = targetFraction;
                self.fgArcLayer.strokeEnd   = currentFraction;
            } else {
                self.fgArcLayer.strokeStart = targetFraction;
                self.fgArcLayer.strokeEnd   = targetFraction;
            }
            break;
        }
        case HAGaugeFillFull: {
            // Auto/heat_cool: colored arc = full range
            self.coloredArcLayer.strokeStart = 0.0;
            self.coloredArcLayer.strokeEnd   = 1.0;
            // Active arc also full for auto mode
            self.fgArcLayer.strokeStart = 0.0;
            self.fgArcLayer.strokeEnd   = 1.0;
            break;
        }
        case HAGaugeFillNone: {
            // Off: no colored or active arcs
            self.coloredArcLayer.strokeStart = 0.0;
            self.coloredArcLayer.strokeEnd   = 0.0;
            self.fgArcLayer.strokeStart = 0.0;
            self.fgArcLayer.strokeEnd   = 0.0;
            break;
        }
    }
}

/// Simplified version for drag (no current temp / action context)
- (void)applyArcFillDragWithFraction:(CGFloat)fraction direction:(HAGaugeFillDirection)direction {
    switch (direction) {
        case HAGaugeFillLeftToRight:
            self.coloredArcLayer.strokeStart = 0.0;
            self.coloredArcLayer.strokeEnd   = fraction;
            self.fgArcLayer.strokeStart = 0.0;
            self.fgArcLayer.strokeEnd   = fraction;
            break;
        case HAGaugeFillRightToLeft:
            self.coloredArcLayer.strokeStart = fraction;
            self.coloredArcLayer.strokeEnd   = 1.0;
            self.fgArcLayer.strokeStart = fraction;
            self.fgArcLayer.strokeEnd   = 1.0;
            break;
        case HAGaugeFillFull:
            self.coloredArcLayer.strokeStart = 0.0;
            self.coloredArcLayer.strokeEnd   = 1.0;
            self.fgArcLayer.strokeStart = 0.0;
            self.fgArcLayer.strokeEnd   = 1.0;
            break;
        case HAGaugeFillNone:
            self.coloredArcLayer.strokeStart = 0.0;
            self.coloredArcLayer.strokeEnd   = 0.0;
            self.fgArcLayer.strokeStart = 0.0;
            self.fgArcLayer.strokeEnd   = 0.0;
            break;
    }
}

#pragma mark - Setup

- (void)setupSubviews {
    [super setupSubviews];
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    // Mode/action label -- centered inside the arc, above the temperature
    // HA web: 16px, weight 500 (medium)
    self.modeLabel = [[UILabel alloc] init];
    self.modeLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.modeLabel.textColor = [HATheme secondaryTextColor];
    self.modeLabel.textAlignment = NSTextAlignmentCenter;
    self.modeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.modeLabel];

    // Temperature label (centered in gauge arc)
    // HA web: 57px (lg), 44px (md), 36px (sm), weight 400 (regular)
    self.tempLabel = [[UILabel alloc] init];
    self.tempLabel.font = [UIFont monospacedDigitSystemFontOfSize:57 weight:UIFontWeightRegular];
    self.tempLabel.textColor = [HATheme primaryTextColor];
    self.tempLabel.textAlignment = NSTextAlignmentCenter;
    self.tempLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.tempLabel];

    // Target/current label below temp (with icon)
    // HA web: 16px, weight 500 (medium)
    self.targetLabel = [[UILabel alloc] init];
    self.targetLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.targetLabel.textColor = [HATheme secondaryTextColor];
    self.targetLabel.textAlignment = NSTextAlignmentCenter;
    self.targetLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.targetLabel];

    // Labels: position constraints are set in updateGaugeArcs via manual frames
    // We use translatesAutoresizingMaskIntoConstraints = NO but position manually
    // to keep them centered within the arc square (not contentView).
    // Remove auto layout for labels -- we'll set frames manually
    self.modeLabel.translatesAutoresizingMaskIntoConstraints = YES;
    self.tempLabel.translatesAutoresizingMaskIntoConstraints = YES;
    self.targetLabel.translatesAutoresizingMaskIntoConstraints = YES;

    // +/- buttons -- overlaid at bottom of SVG square (bottom: 10px)
    self.minusButton = [self makeOutlinedButtonWithTitle:@"\u2212" action:@selector(minusTapped)];
    self.plusButton  = [self makeOutlinedButtonWithTitle:@"+" action:@selector(plusTapped)];

    // Draggable thumb on arc -- size set dynamically in updateGaugeArcs
    self.thumbView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
    self.thumbView.layer.cornerRadius = 12;
    self.thumbView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.thumbView.layer.borderWidth = 2.5;
    self.thumbView.backgroundColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0];
    self.thumbView.hidden = YES;
    self.thumbView.userInteractionEnabled = NO;
    [self.contentView addSubview:self.thumbView];

    self.thumbPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleThumbPan:)];
    self.thumbPanGesture.delegate = self;
    self.thumbPanGesture.delaysTouchesBegan = NO;
    self.thumbPanGesture.delaysTouchesEnded = NO;
    [self.contentView addGestureRecognizer:self.thumbPanGesture];

    // HVAC mode button row -- HA web: ha-control-button-group
    // border-radius: 12px (NOT pill), background: rgba(0,0,0,0.06) in light mode
    self.modeBar = [[UIView alloc] init];
    self.modeBar.backgroundColor = [HATheme effectiveDarkMode]
        ? [[UIColor whiteColor] colorWithAlphaComponent:0.08]
        : [[UIColor blackColor] colorWithAlphaComponent:0.06];
    self.modeBar.layer.cornerRadius = kModeBarCornerRadius;
    self.modeBar.clipsToBounds = YES;
    self.modeBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.modeBar];

    self.modeStack = [[UIStackView alloc] init];
    self.modeStack.axis = UILayoutConstraintAxisHorizontal;
    self.modeStack.distribution = UIStackViewDistributionFillEqually;
    self.modeStack.spacing = 4;
    self.modeStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modeBar addSubview:self.modeStack];

    // Mode bar: always pinned to bottom with HA web padding (0 12px 12px)
    [NSLayoutConstraint activateConstraints:@[
        [self.modeBar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kModeBarSidePad],
        [self.modeBar.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kModeBarSidePad],
        [self.modeBar.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-kModeBarBottomPad],
        [self.modeBar.heightAnchor constraintEqualToConstant:kModeBarHeight],
        [self.modeStack.leadingAnchor constraintEqualToAnchor:self.modeBar.leadingAnchor constant:8],
        [self.modeStack.trailingAnchor constraintEqualToAnchor:self.modeBar.trailingAnchor constant:-8],
        [self.modeStack.topAnchor constraintEqualToAnchor:self.modeBar.topAnchor constant:4],
        [self.modeStack.bottomAnchor constraintEqualToAnchor:self.modeBar.bottomAnchor constant:-4],
    ]];
}

- (UIButton *)makeOutlinedButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightLight];
    btn.backgroundColor = [UIColor clearColor];
    btn.layer.borderWidth = 1.5;
    btn.layer.borderColor = [HATheme tertiaryTextColor].CGColor;
    btn.layer.cornerRadius = kButtonSize / 2.0;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:btn];
    // Manual frame positioning -- no auto layout
    btn.translatesAutoresizingMaskIntoConstraints = YES;
    return btn;
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateGaugeArcs];
}

- (void)updateGaugeArcs {
    CGFloat cellW = self.contentView.bounds.size.width;
    CGFloat cellH = self.contentView.bounds.size.height;
    if (cellW <= 0 || cellH <= 0) return;

    // HA web architecture: single square container fills the space above the mode bar.
    // Everything (arc, text, +/- buttons) is overlaid inside this square.
    // The container has 8px padding around the SVG (from .container > * { padding: 8px }).
    CGFloat modeArea = kArcToModeGap + kModeBarHeight + kModeBarBottomPad;
    CGFloat availH = cellH - modeArea;
    // The container fills full width, capped by available height and max size
    CGFloat container = MIN(cellW, MIN(availH, kMaxArcSquare));
    container = MAX(container, 100.0); // minimum viable size
    // The SVG slider is inset by kArcPadding (8px) from the container on each side
    CGFloat slider = container - 2 * kArcPadding;
    slider = MAX(slider, 80.0);

    // Fast path: if geometry unchanged and layers exist, just update arc fills + thumb
    if (fabs(slider - self.lastLayoutSlider) < 0.5 && self.bgArcLayer) {
        if (self.entity && !self.thumbDragging) {
            NSNumber *targetTemp = [self.entity targetTemperature];
            NSNumber *currentTemp = [self.entity currentTemperature];
            NSString *mode = [self.entity hvacMode];
            if (targetTemp && ![mode isEqualToString:@"off"]) {
                [self applyArcFillForTarget:targetTemp.doubleValue
                                currentTemp:currentTemp
                                  direction:self.fillDirection
                                     action:self.currentAction];
                [self positionThumbAtTemperature:targetTemp.doubleValue];
            }
        }
        [self updateCurrentTempDot];
        return;
    }
    self.lastLayoutSlider = slider;
    self.sliderSize = slider;

    // Arc geometry -- scaled from SVG 320x320 coordinate system
    CGFloat scale = slider / kSVGSize;
    CGFloat gaugeRadius = 145.0 * scale;  // RADIUS = 145 in SVG coords
    gaugeRadius = MAX(gaugeRadius, 30.0);
    CGFloat lineWidth = kStrokeSVG * scale;  // 24 SVG units
    lineWidth = MAX(lineWidth, 4.0);

    // Container is centered horizontally, starts at top of contentView
    // SVG slider is inset by kArcPadding within the container
    CGFloat containerLeft = (cellW - container) / 2.0;
    CGFloat containerTop  = 0.0;
    CGFloat sliderLeft = containerLeft + kArcPadding;
    CGFloat sliderTop  = containerTop + kArcPadding;
    CGPoint center = CGPointMake(sliderLeft + slider / 2.0, sliderTop + slider / 2.0);

    // Cache for gesture handler
    self.arcCenter = center;
    self.arcRadius = gaugeRadius;

    // -- Position info labels: absolute overlay centered in the SVG square --
    // HA web .info: position absolute, top/left/right/bottom 0, flex column, center, gap 8px

    // HA web size classes (from createStateControlCircularSliderController):
    // width >= 250 -> "lg": 57px temp, 16px labels, buttons visible
    // width >= 190 -> "md": 44px temp, 16px labels, buttons HIDDEN, slider margin-bottom: -16px
    // width >= 130 -> "sm": 36px temp, 14px labels, buttons HIDDEN
    // width <  130 -> "xs": 36px temp, labels HIDDEN, buttons HIDDEN
    BOOL isLg = slider >= 250.0;
    BOOL isMd = !isLg && slider >= 190.0;
    BOOL isSm = !isLg && !isMd && slider >= 130.0;

    CGFloat primaryFontSize;
    CGFloat secondaryFontSize;
    if (isLg) {
        primaryFontSize = 57.0;
        secondaryFontSize = 16.0;
    } else if (isMd) {
        primaryFontSize = 44.0;
        secondaryFontSize = 16.0;
    } else {
        primaryFontSize = 36.0;
        secondaryFontSize = 14.0;
    }
    self.tempLabel.font = [UIFont monospacedDigitSystemFontOfSize:primaryFontSize weight:UIFontWeightRegular];

    // Hide +/- buttons for md/sm/xs size classes (HA web: .container.md .buttons { display: none })
    BOOL sizeAllowsButtons = isLg;
    if (!sizeAllowsButtons) {
        self.plusButton.hidden = YES;
        self.minusButton.hidden = YES;
    }

    // Hide mode label in xs
    self.modeLabel.hidden = (slider < 130.0);
    self.targetLabel.hidden = self.targetLabel.hidden || (slider < 130.0);

    self.modeLabel.font = [UIFont systemFontOfSize:secondaryFontSize weight:UIFontWeightMedium];

    // Measure label sizes for manual centering
    CGFloat labelAreaWidth = slider * 0.6; // HA web .label { width: 60% }
    CGSize modeLabelSize = [self.modeLabel sizeThatFits:CGSizeMake(labelAreaWidth, CGFLOAT_MAX)];
    CGSize tempLabelSize = [self.tempLabel sizeThatFits:CGSizeMake(labelAreaWidth, CGFLOAT_MAX)];
    CGSize targetLabelSize = [self.targetLabel sizeThatFits:CGSizeMake(labelAreaWidth, CGFLOAT_MAX)];

    // Total height of the info block: modeLabel + gap(8) + tempLabel + gap(8) + targetLabel
    // If targetLabel is hidden, omit it.
    BOOL showTarget = !self.targetLabel.hidden;
    BOOL showMode = !self.modeLabel.hidden;
    // HA web: lg gap=8px (--ha-space-2), md gap=6px, sm gap=2px
    CGFloat infoGap = isLg ? 8.0 : isMd ? 6.0 : 2.0;
    CGFloat totalInfoH = tempLabelSize.height;
    if (showMode) {
        totalInfoH += modeLabelSize.height + infoGap;
    }
    if (showTarget) {
        totalInfoH += infoGap + targetLabelSize.height;
    }

    // Center info block vertically in the SVG square
    CGFloat infoTopY = sliderTop + (slider - totalInfoH) / 2.0;
    CGFloat currentY = infoTopY;

    if (showMode) {
        self.modeLabel.frame = CGRectMake(
            sliderLeft + (slider - modeLabelSize.width) / 2.0,
            currentY,
            modeLabelSize.width, modeLabelSize.height);
        currentY += modeLabelSize.height + infoGap;
    }

    // Position temp label (replaces old modeLabel frame code below)
    self.tempLabel.frame = CGRectMake(
        sliderLeft + (slider - tempLabelSize.width) / 2.0,
        currentY,
        tempLabelSize.width, tempLabelSize.height);
    currentY += tempLabelSize.height + infoGap;

    if (showTarget) {
        self.targetLabel.frame = CGRectMake(
            sliderLeft + (slider - targetLabelSize.width) / 2.0,
            currentY,
            targetLabelSize.width,
            targetLabelSize.height
        );
    }

    // -- Position +/- buttons: overlaid at bottom of SVG square, bottom: 10px --
    // Button bottom edge is 10px from SVG bottom.
    // Button center Y = sliderTop + slider - 10 - kButtonSize/2
    if (!self.plusButton.hidden) {
        CGFloat btnBottomEdge = sliderTop + slider - 10.0;
        CGFloat btnY = btnBottomEdge - kButtonSize;
        CGFloat totalBtnW = kButtonSize * 2.0 + kButtonGap;
        CGFloat btnLeft = (cellW - totalBtnW) / 2.0;
        self.minusButton.frame = CGRectMake(btnLeft, btnY, kButtonSize, kButtonSize);
        self.plusButton.frame  = CGRectMake(btnLeft + kButtonSize + kButtonGap, btnY, kButtonSize, kButtonSize);
    }

    // -- Radial glow layer behind the arc (HA web ::after pseudo-element) --
    // Skipped under XCTest (non-deterministic CAGradientLayer rendering).
    [self.glowLayer removeFromSuperlayer];
    BOOL isTestEnvironment = (NSClassFromString(@"XCTestCase") != nil);
    if (!isTestEnvironment && self.currentModeColor && self.fillDirection != HAGaugeFillNone) {
        CGFloat glowInset = -slider * 0.10; // 10% overflow on each side
        CGRect glowRect = CGRectMake(
            sliderLeft + glowInset,
            sliderTop + glowInset,
            slider - 2.0 * glowInset,
            slider - 2.0 * glowInset
        );

        if (@available(iOS 12.0, *)) {
            // Modern path: CAGradientLayer with radial type
            self.glowLayer = [CAGradientLayer layer];
            ((CAGradientLayer *)self.glowLayer).type = kCAGradientLayerRadial;
            ((CAGradientLayer *)self.glowLayer).startPoint = CGPointMake(0.5, 0.5);
            ((CAGradientLayer *)self.glowLayer).endPoint = CGPointMake(1.0, 1.0);
            ((CAGradientLayer *)self.glowLayer).colors = @[
                (id)[self.currentModeColor colorWithAlphaComponent:1.0].CGColor,
                (id)[UIColor clearColor].CGColor,
            ];
        } else {
            // Pre-iOS 12 fallback: draw radial gradient into a bitmap via Core Graphics.
            // Cache the bitmap — only redraw when color or size changes.
            self.glowLayer = [CALayer layer];
            CGFloat side = glowRect.size.width;
            BOOL glowCacheValid = (self.cachedGlowImage &&
                                   self.cachedGlowColor && [self.cachedGlowColor isEqual:self.currentModeColor] &&
                                   fabs(self.cachedGlowSize - side) < 1.0);
            if (!glowCacheValid) {
                CGFloat bitmapScale = [UIScreen mainScreen].scale;
                UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, bitmapScale);
                CGContextRef ctx = UIGraphicsGetCurrentContext();
                if (ctx) {
                    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
                    CGFloat components[8];
                    [self getRGBAComponents:self.currentModeColor out:components];
                    CGFloat colors[] = {
                        components[0], components[1], components[2], 1.0,
                        components[0], components[1], components[2], 0.0,
                    };
                    CGGradientRef gradient = CGGradientCreateWithColorComponents(cs, colors, NULL, 2);
                    CGPoint ctr = CGPointMake(side / 2.0, side / 2.0);
                    CGContextDrawRadialGradient(ctx, gradient, ctr, 0, ctr, side / 2.0,
                        kCGGradientDrawsAfterEndLocation);
                    CGGradientRelease(gradient);
                    CGColorSpaceRelease(cs);
                }
                self.cachedGlowImage = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                self.cachedGlowColor = self.currentModeColor;
                self.cachedGlowSize = side;
            }
            self.glowLayer.contents = (id)self.cachedGlowImage.CGImage;
        }

        self.glowLayer.frame = glowRect;
        self.glowLayer.opacity = 0.15;
        self.glowLayer.cornerRadius = glowRect.size.width / 2.0;
        [self.contentView.layer insertSublayer:self.glowLayer atIndex:0];
    } else {
        self.glowLayer = nil;
    }

    // -- Remove old arc layers and recreate --
    [self.bgArcLayer removeFromSuperlayer];
    [self.coloredArcLayer removeFromSuperlayer];
    [self.fgArcLayer removeFromSuperlayer];
    [self.currentTempDotLayer removeFromSuperlayer];

    // Shared arc path for all layers
    UIBezierPath *arcPath = [UIBezierPath bezierPathWithArcCenter:center radius:gaugeRadius
                                                       startAngle:kStartAngle endAngle:kEndAngle clockwise:YES];

    // Layer 1 (bottom): Background arc track -- rgb(189,189,189) at 0.3 opacity
    self.bgArcLayer = [CAShapeLayer layer];
    self.bgArcLayer.path = arcPath.CGPath;
    self.bgArcLayer.strokeColor = [[UIColor colorWithRed:189.0/255.0 green:189.0/255.0 blue:189.0/255.0 alpha:1.0]
                                   colorWithAlphaComponent:0.3].CGColor;
    self.bgArcLayer.fillColor   = [UIColor clearColor].CGColor;
    self.bgArcLayer.lineWidth   = lineWidth;
    self.bgArcLayer.lineCap     = kCALineCapRound;
    NSUInteger glowIdx = self.glowLayer ? 1 : 0;
    [self.contentView.layer insertSublayer:self.bgArcLayer atIndex:(unsigned)glowIdx];

    // Layer 2 (middle): Colored arc -- partial directional range at 0.5 opacity
    UIColor *modeColor = self.currentModeColor ?: [UIColor colorWithRed:1.0 green:0.6 blue:0.2 alpha:1.0];
    self.coloredArcLayer = [CAShapeLayer layer];
    self.coloredArcLayer.path = arcPath.CGPath;
    self.coloredArcLayer.fillColor   = [UIColor clearColor].CGColor;
    self.coloredArcLayer.lineWidth   = lineWidth;
    self.coloredArcLayer.lineCap     = kCALineCapRound;
    self.coloredArcLayer.strokeStart = 0.0;
    self.coloredArcLayer.strokeEnd   = 0.0;
    self.coloredArcLayer.strokeColor = modeColor.CGColor;
    self.coloredArcLayer.opacity     = 0.5;
    [self.contentView.layer insertSublayer:self.coloredArcLayer above:self.bgArcLayer];

    // Current temp indicator -- 8 SVG unit stroke, rgb(20,20,20) at 0.5 opacity
    CGFloat currentIndicatorStroke = 8.0 * scale;
    currentIndicatorStroke = MAX(currentIndicatorStroke, 2.0);
    self.currentTempDotLayer = [CAShapeLayer layer];
    self.currentTempDotLayer.fillColor = [UIColor clearColor].CGColor;
    self.currentTempDotLayer.strokeColor = [[UIColor colorWithRed:20.0/255.0 green:20.0/255.0 blue:20.0/255.0 alpha:1.0]
                                            colorWithAlphaComponent:0.5].CGColor;
    self.currentTempDotLayer.lineWidth = currentIndicatorStroke;
    self.currentTempDotLayer.lineCap = kCALineCapRound;
    [self.contentView.layer insertSublayer:self.currentTempDotLayer above:self.coloredArcLayer];

    // Layer 3 (top): Active arc -- actual value portion at 1.0 opacity
    self.fgArcLayer = [CAShapeLayer layer];
    self.fgArcLayer.path = arcPath.CGPath;
    self.fgArcLayer.fillColor   = [UIColor clearColor].CGColor;
    self.fgArcLayer.lineWidth   = lineWidth;
    self.fgArcLayer.lineCap     = kCALineCapRound;
    self.fgArcLayer.strokeStart = 0.0;
    self.fgArcLayer.strokeEnd   = 0.0;
    self.fgArcLayer.strokeColor = modeColor.CGColor;
    self.fgArcLayer.opacity     = 1.0;
    [self.contentView.layer insertSublayer:self.fgArcLayer above:self.currentTempDotLayer];

    // Re-apply arc fill (layers were recreated, so strokeStart/End were reset)
    if (self.entity && !self.thumbDragging) {
        NSNumber *targetTemp = [self.entity targetTemperature];
        NSNumber *currentTemp = [self.entity currentTemperature];
        NSString *mode = [self.entity hvacMode];
        if (targetTemp && ![mode isEqualToString:@"off"]) {
            [self applyArcFillForTarget:targetTemp.doubleValue
                            currentTemp:currentTemp
                              direction:self.fillDirection
                                 action:self.currentAction];
        }
    } else if (self.thumbDragging) {
        CGFloat fraction = [self fractionForTemperature:self.dragTargetTemp];
        [self applyArcFillDragWithFraction:fraction direction:self.fillDirection];
    }

    // Scale thumb to match HA web proportions:
    // Thumb outer = arc stroke width (24 SVG), inner stroke = 18 SVG
    CGFloat thumbDiameter = lineWidth;
    thumbDiameter = MAX(thumbDiameter, 16.0);
    CGFloat thumbBorder = 18.0 * scale;
    thumbBorder = MAX(thumbBorder, 2.0);
    self.thumbView.bounds = CGRectMake(0, 0, thumbDiameter, thumbDiameter);
    self.thumbView.layer.cornerRadius = thumbDiameter / 2.0;
    self.thumbView.layer.borderWidth = MIN(thumbBorder, thumbDiameter * 0.3);

    // Reposition thumb if visible
    if (!self.thumbView.hidden && self.arcRadius > 0) {
        double temp = self.thumbDragging ? self.dragTargetTemp
            : (self.entity.targetTemperature ? self.entity.targetTemperature.doubleValue : 20.0);
        [self positionThumbAtTemperature:temp];
    }

    // Reposition current temp indicator
    [self updateCurrentTempDot];

    // Ensure thumb and buttons are above arc layers
    [self.contentView bringSubviewToFront:self.minusButton];
    [self.contentView bringSubviewToFront:self.plusButton];
    [self.contentView bringSubviewToFront:self.thumbView];

}

- (void)updateCurrentTempDot {
    if (self.arcRadius <= 0) {
        self.currentTempDotLayer.path = nil;
        return;
    }

    NSNumber *currentTemp = [self.entity currentTemperature];
    if (!currentTemp) {
        self.currentTempDotLayer.path = nil;
        return;
    }

    // Draw a small arc segment at the current temperature position (like HA web's
    // 8-unit stroke indicator). We approximate it as a tiny arc span (~4deg).
    CGFloat fraction = [self fractionForTemperature:currentTemp.doubleValue];
    CGFloat angle = [self angleForFraction:fraction];
    CGFloat halfSpan = 2.0 * M_PI / 180.0; // +/-2deg for a subtle indicator

    UIBezierPath *indicator = [UIBezierPath bezierPathWithArcCenter:self.arcCenter
                                                             radius:self.arcRadius
                                                         startAngle:angle - halfSpan
                                                           endAngle:angle + halfSpan
                                                          clockwise:YES];
    self.currentTempDotLayer.path = indicator.CGPath;
}

#pragma mark - Gesture Delegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.thumbPanGesture) return YES;
    if (self.thumbView.hidden) return NO;

    CGPoint location = [gestureRecognizer locationInView:self.contentView];

    // Don't steal touches from +/- buttons or mode bar
    if (!self.plusButton.hidden && CGRectContainsPoint(self.plusButton.frame, location)) return NO;
    if (!self.minusButton.hidden && CGRectContainsPoint(self.minusButton.frame, location)) return NO;
    if (CGRectContainsPoint(self.modeBar.frame, location)) return NO;

    CGPoint thumbCenter = self.thumbView.center;
    CGFloat distance = hypot(location.x - thumbCenter.x, location.y - thumbCenter.y);
    return distance < kThumbHitRadius;
}

#pragma mark - Thumb Pan

- (void)handleThumbPan:(UIPanGestureRecognizer *)gesture {
    if (self.thumbView.hidden) return;
    if (!self.entity.isAvailable) return;

    CGPoint location = [gesture locationInView:self.contentView];

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            self.thumbDragging = YES;
            self.lastHapticTemp = -999;
            [UIView animateWithDuration:0.15 animations:^{
                self.thumbView.transform = CGAffineTransformMakeScale(1.2, 1.2);
            }];
            [HAHaptics lightImpact];
            // Fall through to compute position
        }
        case UIGestureRecognizerStateChanged: {
            CGFloat angle = [self angleForPoint:location];
            double temp = [self temperatureForAngle:angle];
            self.dragTargetTemp = temp;

            // Update thumb position
            [self positionThumbAtTemperature:temp];

            // Update arc fill during drag (full fill, no active/idle distinction)
            CGFloat fraction = [self fractionForTemperature:temp];
            [self applyArcFillDragWithFraction:fraction direction:self.fillDirection];

            // Update temp label live
            self.tempLabel.text = [NSString stringWithFormat:@"%.1f%@", temp, self.tempUnitString];

            // Haptic tick on step boundaries
            if (fabs(temp - self.lastHapticTemp) >= kTempStep) {
                [HAHaptics selectionChanged];
                self.lastHapticTemp = temp;
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            self.thumbDragging = NO;
            [UIView animateWithDuration:0.15 animations:^{
                self.thumbView.transform = CGAffineTransformIdentity;
            }];

            if (gesture.state == UIGestureRecognizerStateEnded && self.entity) {
                [HAHaptics mediumImpact];
                [[HAConnectionManager sharedManager] callService:@"set_temperature"
                                                        inDomain:@"climate"
                                                        withData:@{@"temperature": @(self.dragTargetTemp)}
                                                        entityId:self.entity.entityId];
            }
            break;
        }
        default:
            break;
    }
}

#pragma mark - Configure

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.nameLabel.hidden = YES;

    // Read temperature range from entity attributes (HA provides min_temp/max_temp)
    self.entityMinTemp = [entity minTemperature].doubleValue;
    self.entityMaxTemp = [entity maxTemperature].doubleValue;
    if (self.entityMaxTemp <= self.entityMinTemp) {
        self.entityMinTemp = 7.0;
        self.entityMaxTemp = 35.0;
    }

    // Read temperature unit from entity attributes (°C, °F, or fallback °)
    NSString *rawUnit = HAAttrString(entity.attributes, HAAttrTemperatureUnit);
    self.tempUnitString = (rawUnit.length > 0) ? rawUnit : @"\u00B0";

    NSNumber *currentTemp = [entity currentTemperature];
    NSNumber *targetTemp  = [entity targetTemperature];
    NSString *mode = [entity hvacMode];
    NSString *action = [entity hvacAction];
    self.currentMode = mode;
    self.currentAction = action;

    // Determine fill direction
    self.fillDirection = [self fillDirectionForMode:mode action:action];

    // Check if card config says show_current_as_primary
    BOOL showCurrentAsPrimary = [configItem.customProperties[@"show_current_as_primary"] boolValue];

    // Status label -- show hvac_action if available, else mode
    if ([action isKindOfClass:[NSString class]] && action.length > 0) {
        self.modeLabel.text = [HAEntityDisplayHelper humanReadableState:action];
    } else {
        self.modeLabel.text = [HAEntityDisplayHelper humanReadableState:mode];
    }

    // Gauge arc color based on hvac_action first, then mode
    UIColor *modeColor;
    if ([action isEqualToString:@"heating"]) {
        modeColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0];
    } else if ([action isEqualToString:@"cooling"]) {
        modeColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0];
    } else if ([mode isEqualToString:@"heat"]) {
        modeColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0];
    } else if ([mode isEqualToString:@"cool"]) {
        modeColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0];
    } else if ([mode isEqualToString:@"auto"] || [mode isEqualToString:@"heat_cool"]) {
        modeColor = [UIColor colorWithRed:0.3 green:0.8 blue:0.4 alpha:1.0];
    } else if ([mode isEqualToString:@"fan_only"]) {
        modeColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.75 alpha:1.0];
    } else if ([mode isEqualToString:@"dry"]) {
        modeColor = [UIColor colorWithRed:0.9 green:0.7 blue:0.2 alpha:1.0];
    } else if ([mode isEqualToString:@"off"]) {
        modeColor = [HATheme secondaryTextColor];
    } else {
        modeColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.75 alpha:1.0];
    }
    self.currentModeColor = modeColor;
    self.coloredArcLayer.strokeColor = modeColor.CGColor;
    self.fgArcLayer.strokeColor = modeColor.CGColor;

    // Update the glow layer color to match the new mode immediately
    if (self.glowLayer) {
        if (@available(iOS 12.0, *)) {
            if ([self.glowLayer isKindOfClass:[CAGradientLayer class]]) {
                ((CAGradientLayer *)self.glowLayer).colors = @[
                    (id)[modeColor colorWithAlphaComponent:1.0].CGColor,
                    (id)[UIColor clearColor].CGColor,
                ];
            }
        } else {
            // Pre-iOS 12 bitmap path: invalidate cache so next layout redraws
            self.cachedGlowColor = nil;
            [self setNeedsLayout];
        }
    }

    // Temperature display -- respect show_current_as_primary
    NSString *tempIcon = [HAIconMapper glyphForIconName:@"home-thermometer-outline"]
                      ?: [HAIconMapper glyphForIconName:@"thermometer"]
                      ?: @"\u25CE";

    CGFloat secondarySize = 16.0;

    if (!self.thumbDragging) {
        if (showCurrentAsPrimary) {
            if (currentTemp) {
                self.tempLabel.text = [NSString stringWithFormat:@"%.0f%@", currentTemp.doubleValue, self.tempUnitString];
            } else {
                self.tempLabel.text = @"--";
            }
            if (targetTemp && ![mode isEqualToString:@"off"]) {
                NSMutableAttributedString *targetAttr = [[NSMutableAttributedString alloc] initWithString:tempIcon
                    attributes:@{NSFontAttributeName: [HAIconMapper mdiFontOfSize:secondarySize],
                                 NSForegroundColorAttributeName: [HATheme secondaryTextColor]}];
                [targetAttr appendAttributedString:[[NSAttributedString alloc]
                    initWithString:[NSString stringWithFormat:@" %.1f %@", targetTemp.doubleValue, self.tempUnitString]
                    attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:secondarySize weight:UIFontWeightMedium],
                                 NSForegroundColorAttributeName: [HATheme secondaryTextColor]}]];
                self.targetLabel.attributedText = targetAttr;
                self.targetLabel.hidden = NO;
            } else {
                self.targetLabel.hidden = YES;
            }
        } else {
            if (targetTemp && ![mode isEqualToString:@"off"]) {
                self.tempLabel.text = [NSString stringWithFormat:@"%.1f%@", targetTemp.doubleValue, self.tempUnitString];
            } else if (currentTemp) {
                self.tempLabel.text = [NSString stringWithFormat:@"%.0f%@", currentTemp.doubleValue, self.tempUnitString];
            } else {
                self.tempLabel.text = @"--";
            }
            if (currentTemp) {
                NSMutableAttributedString *currentAttr = [[NSMutableAttributedString alloc] initWithString:tempIcon
                    attributes:@{NSFontAttributeName: [HAIconMapper mdiFontOfSize:secondarySize],
                                 NSForegroundColorAttributeName: [HATheme secondaryTextColor]}];
                [currentAttr appendAttributedString:[[NSAttributedString alloc]
                    initWithString:[NSString stringWithFormat:@" %.1f %@", currentTemp.doubleValue, self.tempUnitString]
                    attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:secondarySize weight:UIFontWeightMedium],
                                 NSForegroundColorAttributeName: [HATheme secondaryTextColor]}]];
                self.targetLabel.attributedText = currentAttr;
                self.targetLabel.hidden = NO;
            } else {
                self.targetLabel.hidden = YES;
            }
        }

        // Arc fill: use proper HA web logic with current temp and action
        if (targetTemp && ![mode isEqualToString:@"off"]) {
            [self applyArcFillForTarget:targetTemp.doubleValue
                            currentTemp:currentTemp
                              direction:self.fillDirection
                                 action:action];
        } else {
            [self applyArcFillForTarget:0.0 currentTemp:nil direction:HAGaugeFillNone action:nil];
        }

        // Thumb position and visibility
        if (targetTemp && ![mode isEqualToString:@"off"]) {
            self.thumbView.hidden = NO;
            self.thumbView.backgroundColor = modeColor;
            if (self.arcRadius > 0) {
                [self positionThumbAtTemperature:targetTemp.doubleValue];
            }
        } else {
            self.thumbView.hidden = YES;
        }
    }

    // +/- buttons: show when there's a target temp and mode is not off
    BOOL showButtons = NO;
    if (targetTemp && ![mode isEqualToString:@"off"]) {
        showButtons = YES;
    }
    self.plusButton.hidden = !showButtons;
    self.minusButton.hidden = !showButtons;

    // Track button visibility for layout
    if (showButtons != self.buttonsVisible) {
        self.buttonsVisible = showButtons;
        [self setNeedsLayout];
    }

    // Update button border color for theme
    self.plusButton.layer.borderColor = [HATheme tertiaryTextColor].CGColor;
    self.minusButton.layer.borderColor = [HATheme tertiaryTextColor].CGColor;

    // Current temp indicator (always update, even during drag)
    [self updateCurrentTempDot];

    // HVAC mode buttons — sorted in HA canonical order then reversed
    // (from climate.ts HVAC_MODES + hui-climate-hvac-modes-card-feature.ts .sort().reverse())
    NSArray *modes = [entity hvacModes];
    if (modes.count > 0) {
        // HA canonical order: auto, heat_cool, heat, cool, dry, fan_only, off
        // Reversed: off, fan_only, dry, cool, heat, heat_cool, auto
        NSDictionary *modeOrder = @{
            @"off": @0, @"fan_only": @1, @"dry": @2, @"cool": @3,
            @"heat": @4, @"heat_cool": @5, @"auto": @6,
        };
        NSArray *sortedModes = [modes sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            NSNumber *oa = modeOrder[a] ?: @99;
            NSNumber *ob = modeOrder[b] ?: @99;
            return [oa compare:ob];
        }];
        self.availableModes = sortedModes;
        // Skip rebuilding mode buttons if modes and active mode haven't changed
        BOOL modesChanged = ![sortedModes isEqualToArray:self.lastBuiltModes]
                         || ![mode isEqualToString:self.lastBuiltCurrentMode];
        if (modesChanged) {
            [self buildModeButtons:sortedModes currentMode:mode modeColor:modeColor];
            self.lastBuiltModes = sortedModes;
            self.lastBuiltCurrentMode = mode;
        }
    }

    // Mode bar background adapts to theme
    self.modeBar.backgroundColor = [HATheme effectiveDarkMode]
        ? [[UIColor whiteColor] colorWithAlphaComponent:0.08]
        : [[UIColor blackColor] colorWithAlphaComponent:0.06];

    self.contentView.backgroundColor = [HATheme cellBackgroundColor];

    // Ensure thumb is on top
    [self.contentView bringSubviewToFront:self.thumbView];

}

- (void)buildModeButtons:(NSArray *)modes currentMode:(NSString *)currentMode modeColor:(UIColor *)modeColor {
    for (UIView *sub in self.modeStack.arrangedSubviews) {
        [self.modeStack removeArrangedSubview:sub];
        [sub removeFromSuperview];
    }

    // HA web mode bar: ha-control-button-group with ha-control-button children.
    // Buttons are slightly rounded rectangles (NOT circles).
    // Height fills the bar (~34px inside the 42px bar with 4px padding).
    // Width: each button takes equal share. With padding, about 34x34 or wider.
    CGFloat modeBtnHeight = 34.0;
    CGFloat modeBtnWidth = 34.0;
    CGFloat modeIconSize = 20.0;
    CGFloat modeBtnCornerRadius = 8.0; // subtle rounding, not circle

    for (NSString *mode in modes) {
        if (![mode isKindOfClass:[NSString class]]) continue;

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        NSString *iconName = _modeIconNames[mode];
        NSString *icon = iconName ? [HAIconMapper glyphForIconName:iconName] : @"?";
        [btn setTitle:icon forState:UIControlStateNormal];
        btn.titleLabel.font = [HAIconMapper mdiFontOfSize:modeIconSize];
        btn.layer.cornerRadius = modeBtnCornerRadius;
        btn.clipsToBounds = YES;
        btn.tag = [modes indexOfObject:mode];
        [btn addTarget:self action:@selector(modeTapped:) forControlEvents:UIControlEventTouchUpInside];

        // Height only — width is managed by FillEqually stack distribution
        [btn.heightAnchor constraintEqualToConstant:modeBtnHeight].active = YES;

        BOOL isActive = [mode isEqualToString:currentMode];
        if (isActive) {
            btn.backgroundColor = modeColor;
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            btn.backgroundColor = [UIColor clearColor];
            [btn setTitleColor:[HATheme secondaryTextColor] forState:UIControlStateNormal];
        }

        [self.modeStack addArrangedSubview:btn];
    }
}

- (void)modeTapped:(UIButton *)sender {
    if (!self.entity || !self.availableModes) return;
    NSUInteger idx = (NSUInteger)sender.tag;
    if (idx >= self.availableModes.count) return;

    NSString *newMode = self.availableModes[idx];
    if ([newMode isEqualToString:self.currentMode]) return;

    [HAHaptics mediumImpact];
    [[HAConnectionManager sharedManager] callService:@"set_hvac_mode"
                                            inDomain:@"climate"
                                            withData:@{@"hvac_mode": newMode}
                                            entityId:self.entity.entityId];
}

#pragma mark - Actions

- (void)plusTapped {
    if (!self.entity) return;
    [HAHaptics lightImpact];
    NSNumber *target = [self.entity targetTemperature];
    double newTarget = target ? target.doubleValue + 0.5 : 20.0;
    newTarget = MIN(newTarget, self.entityMaxTemp);
    [[HAConnectionManager sharedManager] callService:@"set_temperature"
                                            inDomain:@"climate"
                                            withData:@{@"temperature": @(newTarget)}
                                            entityId:self.entity.entityId];
}

- (void)minusTapped {
    if (!self.entity) return;
    [HAHaptics lightImpact];
    NSNumber *target = [self.entity targetTemperature];
    double newTarget = target ? target.doubleValue - 0.5 : 20.0;
    newTarget = MAX(newTarget, self.entityMinTemp);
    [[HAConnectionManager sharedManager] callService:@"set_temperature"
                                            inDomain:@"climate"
                                            withData:@{@"temperature": @(newTarget)}
                                            entityId:self.entity.entityId];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.nameLabel.attributedText = nil;
    self.tempLabel.text = nil;
    self.targetLabel.attributedText = nil;
    self.modeLabel.text = nil;
    self.coloredArcLayer.strokeStart = 0.0;
    self.coloredArcLayer.strokeEnd = 0.0;
    self.fgArcLayer.strokeStart = 0.0;
    self.fgArcLayer.strokeEnd = 0.0;
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.availableModes = nil;
    self.currentMode = nil;
    self.currentAction = nil;

    // Thumb/drag state
    self.thumbDragging = NO;
    self.thumbView.hidden = YES;
    self.thumbView.transform = CGAffineTransformIdentity;
    self.dragTargetTemp = 0;
    self.currentModeColor = nil;
    self.lastHapticTemp = -999;
    self.fillDirection = HAGaugeFillNone;

    // Reset to safe defaults so fraction calculations don't divide by zero
    self.entityMinTemp = 7.0;
    self.entityMaxTemp = 35.0;
    self.tempUnitString = nil;

    // Current temp indicator
    self.currentTempDotLayer.path = nil;

    // Glow layer
    [self.glowLayer removeFromSuperlayer];
    self.glowLayer = nil;

    // Layout caches — force full rebuild on reuse
    self.lastLayoutSlider = 0;
    // Keep cachedGlowImage/cachedGlowColor/cachedGlowSize — bitmap is color-keyed, safe to reuse
    self.lastBuiltModes = nil;
    self.lastBuiltCurrentMode = nil;

    // Refresh theme colors (static on iOS 9-12)
    self.tempLabel.textColor = [HATheme primaryTextColor];
    self.targetLabel.textColor = [HATheme secondaryTextColor];
    self.modeLabel.textColor = [HATheme secondaryTextColor];
}

@end
