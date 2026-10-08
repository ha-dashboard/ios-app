#import "HAThermostatGaugeCell.h"
#import "HAStrings.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"
#import "HAStateLocalizer.h"
#import "UIView+HAUtilities.h"

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
static const CGFloat kDualSetpointMinGap = 1.0;

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
// Extra mode selectors (preset, fan, swing) — tappable labels below mode bar
@property (nonatomic, strong) UIStackView *extraModesStack;
// Dual setpoint (heat_cool mode)
@property (nonatomic, strong) CAShapeLayer *coloredArcHighLayer; // cool side arc
@property (nonatomic, strong) UIView *thumbHighView;             // cool setpoint thumb
@property (nonatomic, assign) BOOL thumbHighDragging;
@property (nonatomic, assign) double dragTargetTempLow;
@property (nonatomic, assign) double dragTargetTempHigh;
@property (nonatomic, assign) BOOL isDualSetpointMode;
// Dual setpoint UI: two tappable temp buttons replacing tempLabel
@property (nonatomic, strong) UIButton *dualLowButton;
@property (nonatomic, strong) UIButton *dualHighButton;
@property (nonatomic, assign) BOOL selectedSetpointIsHigh; // YES = cool thumb selected
// +/- button debounce: accumulate taps locally, send one service call after idle period
@property (nonatomic, strong) NSTimer *buttonDebounceTimer;
@property (nonatomic, assign) double pendingTargetTemp;
@property (nonatomic, assign) double pendingTargetTempLow;
@property (nonatomic, assign) double pendingTargetTempHigh;
@property (nonatomic, assign) BOOL showCurrentAsPrimary;

// Label helpers
- (NSAttributedString *)secondaryTempAttributedStringForValue:(double)temp;
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

- (void)positionHighThumbAtTemperature:(double)temp {
    CGFloat fraction = [self fractionForTemperature:temp];
    CGFloat angle = [self angleForFraction:fraction];
    CGPoint point = [self pointOnArcForAngle:angle];
    self.thumbHighView.center = point;
}

- (void)dualLowTapped {
    if (self.selectedSetpointIsHigh) {
        self.selectedSetpointIsHigh = NO;
        [self updateDualSetpointSelection];
    }
}

- (void)dualHighTapped {
    if (!self.selectedSetpointIsHigh) {
        self.selectedSetpointIsHigh = YES;
        [self updateDualSetpointSelection];
    }
}

/// Applies colors to the dual temp buttons and +/- buttons based on the active setpoint.
- (void)updateDualSetpointSelection {
    UIColor *heatColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0];
    UIColor *coolColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0];
    UIColor *dimColor  = [HATheme secondaryTextColor];

    if (self.selectedSetpointIsHigh) {
        [self.dualLowButton  setTitleColor:dimColor  forState:UIControlStateNormal];
        [self.dualHighButton setTitleColor:coolColor forState:UIControlStateNormal];
        self.plusButton.tintColor           = coolColor;
        self.minusButton.tintColor          = coolColor;
        self.plusButton.layer.borderColor   = coolColor.CGColor;
        self.minusButton.layer.borderColor  = coolColor.CGColor;
    } else {
        [self.dualLowButton  setTitleColor:heatColor forState:UIControlStateNormal];
        [self.dualHighButton setTitleColor:dimColor  forState:UIControlStateNormal];
        self.plusButton.tintColor           = heatColor;
        self.minusButton.tintColor          = heatColor;
        self.plusButton.layer.borderColor   = heatColor.CGColor;
        self.minusButton.layer.borderColor  = heatColor.CGColor;
    }
}

- (void)applyDualArcFillForLow:(double)lowTemp
                           high:(double)highTemp
                    currentTemp:(NSNumber *)currentTemp
                         action:(NSString *)action {
    if (!self.coloredArcHighLayer) return;
    CGFloat lowFraction  = [self fractionForTemperature:lowTemp];
    CGFloat highFraction = [self fractionForTemperature:highTemp];

    // Heat arc: min → low (orange, 0.5 opacity via coloredArcLayer)
    self.coloredArcLayer.strokeStart = 0.0;
    self.coloredArcLayer.strokeEnd   = lowFraction;

    // Cool arc: high → max (blue, 0.5 opacity via coloredArcHighLayer)
    self.coloredArcHighLayer.strokeStart = highFraction;
    self.coloredArcHighLayer.strokeEnd   = 1.0;

    // Active arc: full opacity on the side currently running
    if ([action isEqualToString:@"heating"] && currentTemp && currentTemp.doubleValue < lowTemp) {
        CGFloat curFraction = [self fractionForTemperature:currentTemp.doubleValue];
        self.fgArcLayer.strokeColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0].CGColor;
        self.fgArcLayer.strokeStart = curFraction;
        self.fgArcLayer.strokeEnd   = lowFraction;
    } else if ([action isEqualToString:@"cooling"] && currentTemp && currentTemp.doubleValue > highTemp) {
        CGFloat curFraction = [self fractionForTemperature:currentTemp.doubleValue];
        self.fgArcLayer.strokeColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0].CGColor;
        self.fgArcLayer.strokeStart = highFraction;
        self.fgArcLayer.strokeEnd   = curFraction;
    } else {
        self.fgArcLayer.strokeStart = 0.0;
        self.fgArcLayer.strokeEnd   = 0.0;
    }
}

- (void)applyDualArcFillDragWithLowFraction:(CGFloat)lowFraction highFraction:(CGFloat)highFraction {
    if (!self.coloredArcHighLayer) return;
    self.coloredArcLayer.strokeStart     = 0.0;
    self.coloredArcLayer.strokeEnd       = lowFraction;
    self.coloredArcHighLayer.strokeStart = highFraction;
    self.coloredArcHighLayer.strokeEnd   = 1.0;
    self.fgArcLayer.strokeStart = 0.0;
    self.fgArcLayer.strokeEnd   = 0.0;
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

    // Dual setpoint temp buttons (replace tempLabel in heat_cool mode)
    self.dualLowButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.dualLowButton.translatesAutoresizingMaskIntoConstraints = YES;
    self.dualLowButton.hidden = YES;
    [self.dualLowButton addTarget:self action:@selector(dualLowTapped)
                 forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.dualLowButton];

    self.dualHighButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.dualHighButton.translatesAutoresizingMaskIntoConstraints = YES;
    self.dualHighButton.hidden = YES;
    [self.dualHighButton addTarget:self action:@selector(dualHighTapped)
                  forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.dualHighButton];

    // Cool setpoint thumb (heat_cool dual mode)
    self.thumbHighView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
    self.thumbHighView.layer.cornerRadius = 12;
    self.thumbHighView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.thumbHighView.layer.borderWidth = 2.5;
    self.thumbHighView.backgroundColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0];
    self.thumbHighView.hidden = YES;
    self.thumbHighView.userInteractionEnabled = NO;
    [self.contentView addSubview:self.thumbHighView];

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

    // Extra modes stack (preset, fan, swing) — compact tappable labels below mode bar
    self.extraModesStack = [[UIStackView alloc] init];
    self.extraModesStack.axis = UILayoutConstraintAxisHorizontal;
    self.extraModesStack.distribution = UIStackViewDistributionFillEqually;
    self.extraModesStack.spacing = 8;
    self.extraModesStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.extraModesStack.hidden = YES;
    [self.contentView addSubview:self.extraModesStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.modeBar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kModeBarSidePad],
        [self.modeBar.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kModeBarSidePad],
        [self.modeBar.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-kModeBarBottomPad],
        [self.modeBar.heightAnchor constraintEqualToConstant:kModeBarHeight],
        [self.modeStack.leadingAnchor constraintEqualToAnchor:self.modeBar.leadingAnchor constant:8],
        [self.modeStack.trailingAnchor constraintEqualToAnchor:self.modeBar.trailingAnchor constant:-8],
        [self.modeStack.topAnchor constraintEqualToAnchor:self.modeBar.topAnchor constant:4],
        [self.modeStack.bottomAnchor constraintEqualToAnchor:self.modeBar.bottomAnchor constant:-4],
        // Extra modes: overlaid inside the arc area above mode bar (small text)
        [self.extraModesStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:kModeBarSidePad],
        [self.extraModesStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-kModeBarSidePad],
        [self.extraModesStack.bottomAnchor constraintEqualToAnchor:self.modeBar.topAnchor constant:-4],
        [self.extraModesStack.heightAnchor constraintEqualToConstant:24],
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
        if (self.entity && !self.thumbDragging && !self.thumbHighDragging) {
            NSString *mode = [self.entity hvacMode];
            if (self.isDualSetpointMode && ![mode isEqualToString:@"off"]) {
                NSNumber *low  = self.entity.attributes[@"target_temp_low"];
                NSNumber *high = self.entity.attributes[@"target_temp_high"];
                if (low && high) {
                    [self applyDualArcFillForLow:low.doubleValue high:high.doubleValue
                                     currentTemp:[self.entity currentTemperature]
                                          action:self.currentAction];
                    [self positionThumbAtTemperature:low.doubleValue];
                    [self positionHighThumbAtTemperature:high.doubleValue];
                }
            } else {
                // Clear cool arc when not in dual mode
                self.coloredArcHighLayer.strokeStart = 0.0;
                self.coloredArcHighLayer.strokeEnd   = 0.0;
                NSNumber *targetTemp = [self.entity targetTemperature];
                NSNumber *currentTemp = [self.entity currentTemperature];
                if (targetTemp && ![mode isEqualToString:@"off"]) {
                    [self applyArcFillForTarget:targetTemp.doubleValue
                                    currentTemp:currentTemp
                                      direction:self.fillDirection
                                         action:self.currentAction];
                    [self positionThumbAtTemperature:targetTemp.doubleValue];
                }
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

    // Set dual button fonts before measurement so sizeThatFits: returns correct values
    CGFloat dualFontSize = isLg ? 44.0 : isMd ? 36.0 : 28.0;
    self.dualLowButton.titleLabel.font  = [UIFont monospacedDigitSystemFontOfSize:dualFontSize weight:UIFontWeightRegular];
    self.dualHighButton.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:dualFontSize weight:UIFontWeightRegular];

    // Show +/- buttons only if entity wants them AND size class allows (lg)
    BOOL sizeAllowsButtons = isLg;
    self.plusButton.hidden = !(self.buttonsVisible && sizeAllowsButtons);
    self.minusButton.hidden = !(self.buttonsVisible && sizeAllowsButtons);

    // Hide mode label in xs
    self.modeLabel.hidden = (slider < 130.0);
    self.targetLabel.hidden = self.targetLabel.hidden || (slider < 130.0);

    self.modeLabel.font = [UIFont systemFontOfSize:secondaryFontSize weight:UIFontWeightMedium];

    // Measure label sizes for manual centering
    CGFloat labelAreaWidth = slider * 0.6; // HA web .label { width: 60% }
    CGSize modeLabelSize = [self.modeLabel sizeThatFits:CGSizeMake(labelAreaWidth, CGFLOAT_MAX)];
    CGSize tempLabelSize;
    if (self.isDualSetpointMode) {
        // Use dual button sizes — font was set above so measurement is accurate
        CGSize lowSz  = [self.dualLowButton  sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
        CGSize highSz = [self.dualHighButton sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
        CGFloat h = MAX(lowSz.height, highSz.height);
        if (h < 1.0) h = ceil(self.tempLabel.font.lineHeight); // fallback before text is set
        tempLabelSize = CGSizeMake(lowSz.width + 8.0 + highSz.width, h);
    } else {
        tempLabelSize = [self.tempLabel sizeThatFits:CGSizeMake(labelAreaWidth, CGFLOAT_MAX)];
    }
    // Measure unconstrained so the icon glyph + text never gets artificially truncated,
    // then clamp to the slider width as a hard ceiling.
    CGSize targetLabelSize = [self.targetLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    targetLabelSize.width = MIN(targetLabelSize.width, slider);

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

    // Position temp label (or dual setpoint buttons in heat_cool mode)
    self.tempLabel.frame = CGRectMake(
        sliderLeft + (slider - tempLabelSize.width) / 2.0,
        currentY,
        tempLabelSize.width, tempLabelSize.height);

    if (self.isDualSetpointMode) {
        // Replace tempLabel with two tappable buttons (fonts set above, sizes in tempLabelSize)
        self.tempLabel.hidden = YES;
        self.dualLowButton.hidden = NO;
        self.dualHighButton.hidden = NO;
        CGSize lowSz  = [self.dualLowButton  sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
        CGSize highSz = [self.dualHighButton sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
        CGFloat btnH  = MAX(lowSz.height, highSz.height);
        CGFloat totalW = lowSz.width + 8.0 + highSz.width;
        CGFloat btnX  = sliderLeft + (slider - totalW) / 2.0;
        self.dualLowButton.frame  = CGRectMake(btnX, currentY, lowSz.width,  btnH);
        self.dualHighButton.frame = CGRectMake(btnX + lowSz.width + 8.0, currentY, highSz.width, btnH);
    } else {
        self.tempLabel.hidden = NO;
        self.dualLowButton.hidden  = YES;
        self.dualHighButton.hidden = YES;
        self.coloredArcHighLayer.strokeStart = 0.0;
        self.coloredArcHighLayer.strokeEnd   = 0.0;
    }
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
    if (self.buttonsVisible && sizeAllowsButtons) {
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
    [self.coloredArcHighLayer removeFromSuperlayer];
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
    // In dual mode the heat (low) arc is always orange regardless of modeColor
    UIColor *heatArcColor = self.isDualSetpointMode
        ? [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0]
        : modeColor;
    self.coloredArcLayer = [CAShapeLayer layer];
    self.coloredArcLayer.path = arcPath.CGPath;
    self.coloredArcLayer.fillColor   = [UIColor clearColor].CGColor;
    self.coloredArcLayer.lineWidth   = lineWidth;
    self.coloredArcLayer.lineCap     = kCALineCapRound;
    self.coloredArcLayer.strokeStart = 0.0;
    self.coloredArcLayer.strokeEnd   = 0.0;
    self.coloredArcLayer.strokeColor = heatArcColor.CGColor;
    self.coloredArcLayer.opacity     = 0.5;
    [self.contentView.layer insertSublayer:self.coloredArcLayer above:self.bgArcLayer];

    // Cool arc layer for heat_cool dual setpoint (blue, high→max, 0.5 opacity)
    self.coloredArcHighLayer = [CAShapeLayer layer];
    self.coloredArcHighLayer.path        = arcPath.CGPath;
    self.coloredArcHighLayer.fillColor   = [UIColor clearColor].CGColor;
    self.coloredArcHighLayer.lineWidth   = lineWidth;
    self.coloredArcHighLayer.lineCap     = kCALineCapRound;
    self.coloredArcHighLayer.strokeStart = 0.0;
    self.coloredArcHighLayer.strokeEnd   = 0.0;
    self.coloredArcHighLayer.strokeColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0].CGColor;
    self.coloredArcHighLayer.opacity     = 0.5;
    [self.contentView.layer insertSublayer:self.coloredArcHighLayer above:self.coloredArcLayer];

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
    self.fgArcLayer.strokeColor = heatArcColor.CGColor; // matches coloredArcLayer side
    self.fgArcLayer.opacity     = 1.0;
    [self.contentView.layer insertSublayer:self.fgArcLayer above:self.currentTempDotLayer];

    // Re-apply arc fill (layers were recreated, so strokeStart/End were reset)
    if (self.entity && !self.thumbDragging && !self.thumbHighDragging) {
        NSNumber *targetTemp = [self.entity targetTemperature];
        NSNumber *currentTemp = [self.entity currentTemperature];
        NSString *mode = [self.entity hvacMode];
        if (self.isDualSetpointMode && ![mode isEqualToString:@"off"]) {
            NSNumber *low  = self.entity.attributes[@"target_temp_low"];
            NSNumber *high = self.entity.attributes[@"target_temp_high"];
            if (low && high) {
                [self applyDualArcFillForLow:low.doubleValue high:high.doubleValue
                                 currentTemp:currentTemp action:self.currentAction];
            }
        } else if (targetTemp && ![mode isEqualToString:@"off"]) {
            [self applyArcFillForTarget:targetTemp.doubleValue
                            currentTemp:currentTemp
                              direction:self.fillDirection
                                 action:self.currentAction];
        }
    } else if (self.thumbDragging) {
        CGFloat fraction = [self fractionForTemperature:self.dragTargetTemp];
        [self applyArcFillDragWithFraction:fraction direction:self.fillDirection];
    } else if (self.thumbHighDragging) {
        [self applyDualArcFillDragWithLowFraction:[self fractionForTemperature:self.dragTargetTempLow]
                                     highFraction:[self fractionForTemperature:self.dragTargetTempHigh]];
    }

    // Scale thumbs to match HA web proportions:
    // Thumb outer = arc stroke width (24 SVG), inner stroke = 18 SVG
    CGFloat thumbDiameter = lineWidth;
    thumbDiameter = MAX(thumbDiameter, 16.0);
    CGFloat thumbBorder = 18.0 * scale;
    thumbBorder = MAX(thumbBorder, 2.0);
    for (UIView *thumb in @[self.thumbView, self.thumbHighView]) {
        thumb.bounds = CGRectMake(0, 0, thumbDiameter, thumbDiameter);
        thumb.layer.cornerRadius = thumbDiameter / 2.0;
        thumb.layer.borderWidth = MIN(thumbBorder, thumbDiameter * 0.3);
    }

    // Reposition thumbs if visible
    if (self.arcRadius > 0) {
        if (!self.thumbView.hidden) {
            double temp = self.thumbDragging ? self.dragTargetTemp
                : (self.isDualSetpointMode
                    ? ([self.entity.attributes[@"target_temp_low"] doubleValue] ?: 18.0)
                    : (self.entity.targetTemperature ? self.entity.targetTemperature.doubleValue : 20.0));
            [self positionThumbAtTemperature:temp];
        }
        if (!self.thumbHighView.hidden) {
            double highTemp = self.thumbHighDragging ? self.dragTargetTempHigh
                : ([self.entity.attributes[@"target_temp_high"] doubleValue] ?: 24.0);
            [self positionHighThumbAtTemperature:highTemp];
        }
    }

    // Reposition current temp indicator
    [self updateCurrentTempDot];

    // Ensure thumbs and buttons are above arc layers
    [self.contentView bringSubviewToFront:self.minusButton];
    [self.contentView bringSubviewToFront:self.plusButton];
    [self.contentView bringSubviewToFront:self.thumbHighView];
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
    if (self.thumbView.hidden && self.thumbHighView.hidden) return NO;

    CGPoint location = [gestureRecognizer locationInView:self.contentView];

    // Don't steal touches from +/- buttons or mode bar
    if (!self.plusButton.hidden && CGRectContainsPoint(self.plusButton.frame, location)) return NO;
    if (!self.minusButton.hidden && CGRectContainsPoint(self.minusButton.frame, location)) return NO;
    if (CGRectContainsPoint(self.modeBar.frame, location)) return NO;

    CGFloat distLow  = self.thumbView.hidden ? CGFLOAT_MAX
        : hypot(location.x - self.thumbView.center.x, location.y - self.thumbView.center.y);
    CGFloat distHigh = self.thumbHighView.hidden ? CGFLOAT_MAX
        : hypot(location.x - self.thumbHighView.center.x, location.y - self.thumbHighView.center.y);
    return (distLow < kThumbHitRadius || distHigh < kThumbHitRadius);
}

#pragma mark - Thumb Pan

- (void)handleThumbPan:(UIPanGestureRecognizer *)gesture {
    if (self.thumbView.hidden && self.thumbHighView.hidden) return;
    if (!self.entity.isAvailable) return;

    CGPoint location = [gesture locationInView:self.contentView];

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            // If the user starts dragging while a button debounce is pending, flush it immediately
            // so drag starts from the confirmed pending value, not the stale entity value
            if (self.buttonDebounceTimer) {
                [self.buttonDebounceTimer invalidate];
                self.buttonDebounceTimer = nil;
                [self flushPendingButtonChange];
            }
            // Determine which thumb to drag by proximity
            CGFloat distLow  = self.thumbView.hidden ? CGFLOAT_MAX
                : hypot(location.x - self.thumbView.center.x, location.y - self.thumbView.center.y);
            CGFloat distHigh = self.thumbHighView.hidden ? CGFLOAT_MAX
                : hypot(location.x - self.thumbHighView.center.x, location.y - self.thumbHighView.center.y);
            self.thumbHighDragging = (distHigh < distLow);

            if (self.isDualSetpointMode) {
                // Seed from displayed (optimistic) values so drag continues from where +/- left off
                NSNumber *low  = self.entity.attributes[@"target_temp_low"];
                NSNumber *high = self.entity.attributes[@"target_temp_high"];
                self.dragTargetTempLow  = self.pendingTargetTempLow  ?: (low  ? low.doubleValue  : 18.0);
                self.dragTargetTempHigh = self.pendingTargetTempHigh ?: (high ? high.doubleValue : 24.0);
            } else {
                NSNumber *target = [self.entity targetTemperature];
                self.dragTargetTemp = self.pendingTargetTemp ?: (target ? target.doubleValue : 20.0);
            }

            if (self.thumbHighDragging) {
                self.thumbDragging = NO;
                if (self.isDualSetpointMode && !self.selectedSetpointIsHigh) {
                    self.selectedSetpointIsHigh = YES;
                    [self updateDualSetpointSelection];
                }
                [UIView animateWithDuration:0.15 animations:^{
                    self.thumbHighView.transform = CGAffineTransformMakeScale(1.2, 1.2);
                }];
            } else {
                self.thumbDragging = YES;
                if (!self.isDualSetpointMode) {
                    double entityTarget = self.entity.targetTemperature ? self.entity.targetTemperature.doubleValue : 20.0;
                    self.dragTargetTemp = self.pendingTargetTemp > 0 ? self.pendingTargetTemp : entityTarget;
                } else if (self.selectedSetpointIsHigh) {
                    self.selectedSetpointIsHigh = NO;
                    [self updateDualSetpointSelection];
                }
                [UIView animateWithDuration:0.15 animations:^{
                    self.thumbView.transform = CGAffineTransformMakeScale(1.2, 1.2);
                }];
            }
            self.lastHapticTemp = -999;
            [HAHaptics lightImpact];
            // Fall through to compute position
        }
        case UIGestureRecognizerStateChanged: {
            CGFloat angle = [self angleForPoint:location];
            double temp = [self temperatureForAngle:angle];

            if (self.isDualSetpointMode) {
                if (self.thumbHighDragging) {
                    temp = MAX(temp, self.dragTargetTempLow + kDualSetpointMinGap);
                    temp = MIN(temp, self.entityMaxTemp);
                    self.dragTargetTempHigh = temp;
                    [self positionHighThumbAtTemperature:temp];
                } else {
                    temp = MIN(temp, self.dragTargetTempHigh - kDualSetpointMinGap);
                    temp = MAX(temp, self.entityMinTemp);
                    self.dragTargetTempLow = temp;
                    [self positionThumbAtTemperature:temp];
                }
                [self applyDualArcFillDragWithLowFraction:[self fractionForTemperature:self.dragTargetTempLow]
                                             highFraction:[self fractionForTemperature:self.dragTargetTempHigh]];
                [self.dualLowButton  setTitle:[NSString stringWithFormat:@"%.0f%@", self.dragTargetTempLow,  self.tempUnitString] forState:UIControlStateNormal];
                [self.dualHighButton setTitle:[NSString stringWithFormat:@"%.0f%@", self.dragTargetTempHigh, self.tempUnitString] forState:UIControlStateNormal];
            } else {
                self.dragTargetTemp = temp;
                [self positionThumbAtTemperature:temp];
                [self applyArcFillDragWithFraction:[self fractionForTemperature:temp]
                                         direction:self.fillDirection];
                if (self.showCurrentAsPrimary) {
                    // tempLabel stays on current room temp; live-update the setpoint shown
                    // in targetLabel so dragging the thumb reflects the new value, matching
                    // what the +/- buttons already do via applyOptimisticSingleTemp:.
                    self.targetLabel.attributedText = [self secondaryTempAttributedStringForValue:temp];
                    self.targetLabel.hidden = NO;
                } else {
                    self.tempLabel.text = [NSString stringWithFormat:@"%.1f%@", temp, self.tempUnitString];
                }
            }

            if (fabs(temp - self.lastHapticTemp) >= kTempStep) {
                [HAHaptics selectionChanged];
                self.lastHapticTemp = temp;
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            BOOL wasActive = self.thumbDragging || self.thumbHighDragging;
            self.thumbDragging = NO;
            self.thumbHighDragging = NO;
            // Drag takes ownership — clear pending button values so they don't interfere
            self.pendingTargetTemp = 0;
            self.pendingTargetTempLow = 0;
            self.pendingTargetTempHigh = 0;
            [UIView animateWithDuration:0.15 animations:^{
                self.thumbView.transform = CGAffineTransformIdentity;
                self.thumbHighView.transform = CGAffineTransformIdentity;
            }];

            if (gesture.state == UIGestureRecognizerStateEnded && self.entity && wasActive) {
                [HAHaptics mediumImpact];
                if (self.isDualSetpointMode) {
                    [[HAConnectionManager sharedManager] callService:@"set_temperature"
                                                            inDomain:@"climate"
                                                            withData:@{
                                                                @"target_temp_low":  @(self.dragTargetTempLow),
                                                                @"target_temp_high": @(self.dragTargetTempHigh),
                                                            }
                                                            entityId:self.entity.entityId];
                } else {
                    [[HAConnectionManager sharedManager] callService:@"set_temperature"
                                                            inDomain:@"climate"
                                                            withData:@{@"temperature": @(self.dragTargetTemp)}
                                                            entityId:self.entity.entityId];
                }
            }
            break;
        }
        default:
            break;
    }
}

#pragma mark - Label Helpers

/// Builds the "icon + value" attributed string used for the secondary (targetLabel) text —
/// e.g. the target setpoint shown under the current temp in show_current_as_primary mode, or
/// the current temp shown under the setpoint in default mode. Shared by configureWithEntity:
/// and the optimistic nudge/drag paths so the format never drifts between them.
- (NSAttributedString *)secondaryTempAttributedStringForValue:(double)temp {
    NSString *tempIcon = [HAIconMapper glyphForIconName:@"home-thermometer-outline"]
                      ?: [HAIconMapper glyphForIconName:@"thermometer"]
                      ?: @"◎";
    CGFloat secondarySize = 16.0;
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:tempIcon
        attributes:@{NSFontAttributeName: [HAIconMapper mdiFontOfSize:secondarySize],
                     NSForegroundColorAttributeName: [HATheme secondaryTextColor]}];
    [attr appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@" %.1f %@", temp, self.tempUnitString]
        attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:secondarySize weight:UIFontWeightMedium],
                     NSForegroundColorAttributeName: [HATheme secondaryTextColor]}]];
    return attr;
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
    // Dual setpoint: heat_cool mode uses target_temp_high/target_temp_low
    NSNumber *targetTempHigh = entity.attributes[@"target_temp_high"];
    NSNumber *targetTempLow = entity.attributes[@"target_temp_low"];
    BOOL isDualSetpoint = ([targetTempHigh isKindOfClass:[NSNumber class]] &&
                           [targetTempLow isKindOfClass:[NSNumber class]]);
    BOOL wasDualSetpointMode = self.isDualSetpointMode;
    self.isDualSetpointMode = isDualSetpoint;
    if (wasDualSetpointMode != isDualSetpoint) {
        self.lastLayoutSlider = 0; // force full rebuild when dual mode changes
    }
    BOOL showDualButtons = isDualSetpoint && ![[entity hvacMode] isEqualToString:@"off"];
    self.dualLowButton.hidden  = !showDualButtons;
    self.dualHighButton.hidden = !showDualButtons;
    self.tempLabel.hidden = showDualButtons; // eagerly un-hide for single modes
    // Clear cool arc immediately when not in dual mode (fast path may not reach it)
    if (!isDualSetpoint) {
        self.coloredArcHighLayer.strokeStart = 0.0;
        self.coloredArcHighLayer.strokeEnd   = 0.0;
    }
    NSString *mode = [entity hvacMode];
    NSString *action = [entity hvacAction];
    self.currentMode = mode;
    self.currentAction = action;

    // Determine fill direction
    self.fillDirection = [self fillDirectionForMode:mode action:action];

    // Check if card config says show_current_as_primary
    BOOL showCurrentAsPrimary = [configItem.customProperties[@"show_current_as_primary"] boolValue];
    self.showCurrentAsPrimary = showCurrentAsPrimary;

    // Status label -- show hvac_action if available, else mode. Append humidity if available.
    // `mode` is the entity's own `state` (climate domain) -- HA-translated
    // the same way as any other entity state (plan §2.2), so route it
    // through the shared localizer. `action` is the `hvac_action`
    // ATTRIBUTE, translated under a different key template
    // (`…state_attributes.hvac_action.state.{value}`, plan §2.4) that
    // HAStateLocalizer does not yet expose a lookup for -- left on the
    // algorithmic fallback, same as HAModeFeatureView's preset/fan modes.
    NSString *statusText;
    if ([action isKindOfClass:[NSString class]] && action.length > 0) {
        statusText = [HAEntityDisplayHelper humanReadableState:action];
    } else {
        statusText = [[HAStateLocalizer sharedLocalizer] localizedStateForDomain:@"climate"
                                                                       deviceClass:nil
                                                                          platform:nil
                                                                    translationKey:nil
                                                                             state:mode];
    }
    NSNumber *currentHumidity = entity.attributes[@"current_humidity"];
    NSNumber *targetHumidity = entity.attributes[@"target_humidity"];
    if ([currentHumidity isKindOfClass:[NSNumber class]]) {
        statusText = [statusText stringByAppendingFormat:@" · %@%%", currentHumidity];
        if ([targetHumidity isKindOfClass:[NSNumber class]]) {
            statusText = [statusText stringByAppendingFormat:@" → %@%%", targetHumidity];
        }
    }
    self.modeLabel.text = statusText;

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
    // In dual mode the heat (low) arc is always orange — modeColor is used for glow only
    UIColor *arcLayerColor = isDualSetpoint
        ? [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0]
        : modeColor;
    self.coloredArcLayer.strokeColor = arcLayerColor.CGColor;
    self.fgArcLayer.strokeColor = arcLayerColor.CGColor;

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

    // A +/- tap debounce may still be in flight (pendingTargetTemp*): an entity update that
    // arrives during that 5s window reflects the pre-tap state from HA's point of view, not
    // the optimistic value the user just set. Prefer the pending value so this re-render
    // doesn't visibly snap the setpoint back and then forward again once the service call lands.
    BOOL hasPendingDebounce = (self.buttonDebounceTimer != nil);
    NSNumber *effectiveTargetTemp = (hasPendingDebounce && !isDualSetpoint)
        ? @(self.pendingTargetTemp) : targetTemp;
    NSNumber *effectiveTargetTempLow = (hasPendingDebounce && isDualSetpoint)
        ? @(self.pendingTargetTempLow) : targetTempLow;
    NSNumber *effectiveTargetTempHigh = (hasPendingDebounce && isDualSetpoint)
        ? @(self.pendingTargetTempHigh) : targetTempHigh;

    if (!self.thumbDragging) {
        if (showCurrentAsPrimary) {
            if (currentTemp) {
                self.tempLabel.text = [NSString stringWithFormat:@"%.0f%@", currentTemp.doubleValue, self.tempUnitString];
            } else {
                self.tempLabel.text = HALocalizedString(@"cell.thermostat.no_value", @"Temperature label in the thermostat gauge cell, shown when no value is available.");
            }
            if (effectiveTargetTemp && ![mode isEqualToString:@"off"]) {
                self.targetLabel.attributedText = [self secondaryTempAttributedStringForValue:effectiveTargetTemp.doubleValue];
                self.targetLabel.hidden = NO;
            } else {
                self.targetLabel.hidden = YES;
            }
        } else {
            if (isDualSetpoint && ![mode isEqualToString:@"off"]) {
                // Set dual button titles; updateGaugeArcs hides tempLabel and shows these
                [self.dualLowButton  setTitle:[NSString stringWithFormat:@"%.0f%@", effectiveTargetTempLow.doubleValue,  self.tempUnitString] forState:UIControlStateNormal];
                [self.dualHighButton setTitle:[NSString stringWithFormat:@"%.0f%@", effectiveTargetTempHigh.doubleValue, self.tempUnitString] forState:UIControlStateNormal];
                self.tempLabel.text = nil; // hidden in dual mode; won't affect layout (height via dual buttons)
            } else if (effectiveTargetTemp && ![mode isEqualToString:@"off"]) {
                self.tempLabel.text = [NSString stringWithFormat:@"%.1f%@", effectiveTargetTemp.doubleValue, self.tempUnitString];
            } else if (currentTemp) {
                self.tempLabel.text = [NSString stringWithFormat:@"%.0f%@", currentTemp.doubleValue, self.tempUnitString];
            } else {
                self.tempLabel.text = HALocalizedString(@"cell.thermostat.no_value", @"Temperature label in the thermostat gauge cell, shown when no value is available.");
            }
            if (currentTemp) {
                self.targetLabel.attributedText = [self secondaryTempAttributedStringForValue:currentTemp.doubleValue];
                self.targetLabel.hidden = NO;
            } else {
                self.targetLabel.hidden = YES;
            }
        }

        // Arc fill and thumb position/visibility
        if (isDualSetpoint && effectiveTargetTempLow && effectiveTargetTempHigh && ![mode isEqualToString:@"off"]) {
            [self applyDualArcFillForLow:effectiveTargetTempLow.doubleValue
                                    high:effectiveTargetTempHigh.doubleValue
                             currentTemp:currentTemp
                                  action:action];
            // Two thumbs: heat (orange) at low, cool (blue) at high
            self.thumbView.hidden = NO;
            self.thumbView.backgroundColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0];
            self.thumbHighView.hidden = NO;
            self.thumbHighView.backgroundColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0];
            if (self.arcRadius > 0) {
                [self positionThumbAtTemperature:effectiveTargetTempLow.doubleValue];
                [self positionHighThumbAtTemperature:effectiveTargetTempHigh.doubleValue];
            }
        } else if (effectiveTargetTemp && ![mode isEqualToString:@"off"]) {
            [self applyArcFillForTarget:effectiveTargetTemp.doubleValue
                            currentTemp:currentTemp
                              direction:self.fillDirection
                                 action:action];
            self.thumbView.hidden = NO;
            self.thumbHighView.hidden = YES;
            self.thumbView.backgroundColor = modeColor;
            if (self.arcRadius > 0) {
                [self positionThumbAtTemperature:effectiveTargetTemp.doubleValue];
            }
        } else {
            [self applyArcFillForTarget:0.0 currentTemp:nil direction:HAGaugeFillNone action:nil];
            if (self.coloredArcHighLayer) {
                self.coloredArcHighLayer.strokeStart = 0.0;
                self.coloredArcHighLayer.strokeEnd = 0.0;
            }
            self.thumbView.hidden = YES;
            self.thumbHighView.hidden = YES;
        }
    }

    // +/- buttons: show when there's a target temp and mode is not off
    BOOL showButtons = ![mode isEqualToString:@"off"] &&
        (isDualSetpoint ? (targetTempLow != nil && targetTempHigh != nil) : (targetTemp != nil));
    // Don't set button hidden here — layoutSubviews/updateGaugeArcs is the
    // single authority on visibility (it checks both this flag AND size class).
    if (showButtons != self.buttonsVisible) {
        self.buttonsVisible = showButtons;
        self.lastLayoutSlider = 0; // force full rebuild to update button visibility
    }
    [self setNeedsLayout];

    // Update button border color for theme (dual mode overrides this below)
    self.plusButton.tintColor  = nil; // restore system tint
    self.minusButton.tintColor = nil;
    self.plusButton.layer.borderColor  = [HATheme tertiaryTextColor].CGColor;
    self.minusButton.layer.borderColor = [HATheme tertiaryTextColor].CGColor;

    if (isDualSetpoint && ![mode isEqualToString:@"off"]) {
        [self updateDualSetpointSelection];
    }

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

    // Extra mode selectors: preset, fan, swing (compact tappable labels above mode bar)
    // TODO: implement updateExtraModesForEntity: for climate preset/fan/swing modes

    // Mode bar background adapts to theme
    self.modeBar.backgroundColor = [HATheme effectiveDarkMode]
        ? [[UIColor whiteColor] colorWithAlphaComponent:0.08]
        : [[UIColor blackColor] colorWithAlphaComponent:0.06];

    self.contentView.backgroundColor = [HATheme cellBackgroundColor];

    // Ensure thumbs are on top
    [self.contentView bringSubviewToFront:self.thumbHighView];
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

#pragma mark - Extra Mode Selectors (Preset / Fan / Swing)

- (void)updateExtraModesForEntity:(HAEntity *)entity {
    for (UIView *v in self.extraModesStack.arrangedSubviews) {
        [self.extraModesStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    BOOL hasExtras = NO;

    // Preset mode
    NSArray *presetModes = entity.attributes[@"preset_modes"];
    NSString *currentPreset = entity.attributes[@"preset_mode"];
    if ([presetModes isKindOfClass:[NSArray class]] && presetModes.count > 0) {
        NSString *title = currentPreset
            ? [NSString stringWithFormat:@"%@ \u25BE", [currentPreset capitalizedString]]
            : HALocalizedString(@"cell.thermostat.preset_label", @"Collapsed preset-mode button in the thermostat gauge cell, shown when no preset is set. Keep the trailing triangle glyph.");
        [self.extraModesStack addArrangedSubview:[self makeExtraModeButton:title tag:100]];
        hasExtras = YES;
    }
    // Fan mode
    NSArray *fanModes = entity.attributes[@"fan_modes"];
    NSString *currentFan = entity.attributes[@"fan_mode"];
    if ([fanModes isKindOfClass:[NSArray class]] && fanModes.count > 0) {
        NSString *title = currentFan
            ? [NSString stringWithFormat:@"%@ \u25BE", [currentFan capitalizedString]]
            : HALocalizedString(@"cell.thermostat.fan_label", @"Collapsed fan-mode button in the thermostat gauge cell, shown when no fan mode is set. Keep the trailing triangle glyph.");
        [self.extraModesStack addArrangedSubview:[self makeExtraModeButton:title tag:101]];
        hasExtras = YES;
    }
    // Swing mode
    NSArray *swingModes = entity.attributes[@"swing_modes"];
    NSString *currentSwing = entity.attributes[@"swing_mode"];
    if ([swingModes isKindOfClass:[NSArray class]] && swingModes.count > 0) {
        NSString *title = currentSwing
            ? [NSString stringWithFormat:@"%@ \u25BE", [currentSwing capitalizedString]]
            : HALocalizedString(@"cell.thermostat.swing_label", @"Collapsed swing-mode button in the thermostat gauge cell, shown when no swing mode is set. Keep the trailing triangle glyph.");
        [self.extraModesStack addArrangedSubview:[self makeExtraModeButton:title tag:102]];
        hasExtras = YES;
    }
    self.extraModesStack.hidden = !hasExtras;
}

- (UIButton *)makeExtraModeButton:(NSString *)title tag:(NSInteger)tag {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [btn setTitleColor:[HATheme secondaryTextColor] forState:UIControlStateNormal];
    btn.tag = tag;
    [btn addTarget:self action:@selector(extraModeTapped:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)extraModeTapped:(UIButton *)sender {
    if (!self.entity) return;
    NSString *service, *serviceKey;
    NSArray *options;
    NSString *current;
    if (sender.tag == 100) {
        options = self.entity.attributes[@"preset_modes"];
        current = self.entity.attributes[@"preset_mode"];
        service = @"set_preset_mode"; serviceKey = @"preset_mode";
    } else if (sender.tag == 101) {
        options = self.entity.attributes[@"fan_modes"];
        current = self.entity.attributes[@"fan_mode"];
        service = @"set_fan_mode"; serviceKey = @"fan_mode";
    } else if (sender.tag == 102) {
        options = self.entity.attributes[@"swing_modes"];
        current = self.entity.attributes[@"swing_mode"];
        service = @"set_swing_mode"; serviceKey = @"swing_mode";
    } else { return; }
    if (![options isKindOfClass:[NSArray class]] || options.count == 0) return;

    UIViewController *vc = [self ha_parentViewController];
    if (!vc) return;

    NSString *entityId = self.entity.entityId; // capture before block
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *option in options) {
        BOOL isActive = [option isEqualToString:current];
        NSString *title = isActive
            ? [NSString stringWithFormat:@"\u2713 %@", [option capitalizedString]]
            : [option capitalizedString];
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *a) {
            [HAHaptics lightImpact];
            [[HAConnectionManager sharedManager] callService:service inDomain:@"climate"
                                                    withData:@{serviceKey: option}
                                                    entityId:entityId];
        }];
        [sheet addAction:action];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:HALocalizedString(@"action.cancel", @"Cancel button in alerts and action sheets throughout Settings.") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = sender;
    sheet.popoverPresentationController.sourceRect = sender.bounds;
    [vc presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Actions

- (void)applyOptimisticSingleTemp:(double)newTarget {
    if (self.showCurrentAsPrimary) {
        // tempLabel shows current room temp — keep it; update the secondary label with the new target
        self.targetLabel.attributedText = [self secondaryTempAttributedStringForValue:newTarget];
        self.targetLabel.hidden = NO;
    } else {
        self.tempLabel.text = [NSString stringWithFormat:@"%.1f%@", newTarget, self.tempUnitString];
    }
    [self applyArcFillForTarget:newTarget
                    currentTemp:[self.entity currentTemperature]
                      direction:self.fillDirection
                         action:self.currentAction];
    if (self.arcRadius > 0) {
        [self positionThumbAtTemperature:newTarget];
    }
}

- (void)applyOptimisticDualLow:(double)newLow high:(double)newHigh {
    [self.dualLowButton  setTitle:[NSString stringWithFormat:@"%.0f%@", newLow,  self.tempUnitString] forState:UIControlStateNormal];
    [self.dualHighButton setTitle:[NSString stringWithFormat:@"%.0f%@", newHigh, self.tempUnitString] forState:UIControlStateNormal];
    [self applyDualArcFillForLow:newLow high:newHigh
                     currentTemp:[self.entity currentTemperature] action:self.currentAction];
    if (self.arcRadius > 0) {
        [self positionThumbAtTemperature:newLow];
        [self positionHighThumbAtTemperature:newHigh];
    }
}

- (void)scheduleButtonDebounce {
    [self.buttonDebounceTimer invalidate];
    self.buttonDebounceTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                                target:self
                                                              selector:@selector(flushPendingButtonChange)
                                                              userInfo:nil
                                                               repeats:NO];
}

- (void)flushPendingButtonChange {
    self.buttonDebounceTimer = nil;
    if (!self.entity) return;
    if (self.isDualSetpointMode) {
        [[HAConnectionManager sharedManager] callService:@"set_temperature"
                                                inDomain:@"climate"
                                                withData:@{@"target_temp_low":  @(self.pendingTargetTempLow),
                                                           @"target_temp_high": @(self.pendingTargetTempHigh)}
                                                entityId:self.entity.entityId];
    } else {
        [[HAConnectionManager sharedManager] callService:@"set_temperature"
                                                inDomain:@"climate"
                                                withData:@{@"temperature": @(self.pendingTargetTemp)}
                                                entityId:self.entity.entityId];
    }
}

- (void)plusTapped {
    if (!self.entity) return;
    [HAHaptics lightImpact];
    double step = 0.5;
    NSNumber *attrStep = self.entity.attributes[@"target_temp_step"];
    if (attrStep) step = [attrStep doubleValue];

    if (self.isDualSetpointMode) {
        // Read from pending if a debounce is in flight, else from entity
        double curLow  = self.buttonDebounceTimer ? self.pendingTargetTempLow  : ([self.entity.attributes[@"target_temp_low"]  doubleValue] ?: 18.0);
        double curHigh = self.buttonDebounceTimer ? self.pendingTargetTempHigh : ([self.entity.attributes[@"target_temp_high"] doubleValue] ?: 24.0);
        if (self.selectedSetpointIsHigh) {
            self.pendingTargetTempLow  = curLow;
            self.pendingTargetTempHigh = MIN(curHigh + step, self.entityMaxTemp);
        } else {
            self.pendingTargetTempLow  = MIN(curLow + step, curHigh - kDualSetpointMinGap);
            self.pendingTargetTempHigh = curHigh;
        }
        [self applyOptimisticDualLow:self.pendingTargetTempLow high:self.pendingTargetTempHigh];
    } else {
        double cur = self.buttonDebounceTimer ? self.pendingTargetTemp : ([[self.entity targetTemperature] doubleValue] ?: 20.0);
        self.pendingTargetTemp = MIN(cur + step, self.entityMaxTemp);
        [self applyOptimisticSingleTemp:self.pendingTargetTemp];
    }
    [self scheduleButtonDebounce];
}

- (void)minusTapped {
    if (!self.entity) return;
    [HAHaptics lightImpact];
    double step = 0.5;
    NSNumber *attrStep = self.entity.attributes[@"target_temp_step"];
    if (attrStep) step = [attrStep doubleValue];

    if (self.isDualSetpointMode) {
        double curLow  = self.buttonDebounceTimer ? self.pendingTargetTempLow  : ([self.entity.attributes[@"target_temp_low"]  doubleValue] ?: 18.0);
        double curHigh = self.buttonDebounceTimer ? self.pendingTargetTempHigh : ([self.entity.attributes[@"target_temp_high"] doubleValue] ?: 24.0);
        if (self.selectedSetpointIsHigh) {
            self.pendingTargetTempLow  = curLow;
            self.pendingTargetTempHigh = MAX(curHigh - step, curLow + kDualSetpointMinGap);
        } else {
            self.pendingTargetTempLow  = MAX(curLow - step, self.entityMinTemp);
            self.pendingTargetTempHigh = curHigh;
        }
        [self applyOptimisticDualLow:self.pendingTargetTempLow high:self.pendingTargetTempHigh];
    } else {
        double cur = self.buttonDebounceTimer ? self.pendingTargetTemp : ([[self.entity targetTemperature] doubleValue] ?: 20.0);
        self.pendingTargetTemp = MAX(cur - step, self.entityMinTemp);
        [self applyOptimisticSingleTemp:self.pendingTargetTemp];
    }
    [self scheduleButtonDebounce];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.buttonsVisible = NO;
    self.plusButton.hidden = YES;
    self.minusButton.hidden = YES;
    self.nameLabel.attributedText = nil;
    self.tempLabel.text = nil;
    self.targetLabel.attributedText = nil;
    self.modeLabel.text = nil;
    self.coloredArcLayer.strokeStart = 0.0;
    self.coloredArcLayer.strokeEnd = 0.0;
    self.fgArcLayer.strokeStart = 0.0;
    self.fgArcLayer.strokeEnd = 0.0;
    self.availableModes = nil;
    self.currentMode = nil;
    self.currentAction = nil;

    // Preserve the user's last thermostat change even if the collection view
    // recycles this cell before the debounce interval expires.
    if (self.buttonDebounceTimer) {
        [self.buttonDebounceTimer invalidate];
        [self flushPendingButtonChange];
    }

    // Thumb/drag state
    self.thumbDragging = NO;
    self.thumbHighDragging = NO;
    self.thumbView.hidden = YES;
    self.thumbHighView.hidden = YES;
    self.thumbView.transform = CGAffineTransformIdentity;
    self.thumbHighView.transform = CGAffineTransformIdentity;
    self.dragTargetTemp = 0;
    self.dragTargetTempLow = 0;
    self.dragTargetTempHigh = 0;
    self.isDualSetpointMode = NO;
    self.selectedSetpointIsHigh = NO;
    self.dualLowButton.hidden = YES;
    self.dualHighButton.hidden = YES;
    self.coloredArcHighLayer.strokeStart = 0.0;
    self.coloredArcHighLayer.strokeEnd = 0.0;
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
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.tempLabel.textColor = [HATheme primaryTextColor];
    self.targetLabel.textColor = [HATheme secondaryTextColor];
    self.modeLabel.textColor = [HATheme secondaryTextColor];
}

@end
