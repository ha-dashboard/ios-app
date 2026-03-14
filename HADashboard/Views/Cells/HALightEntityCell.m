#import "HAAutoLayout.h"
#import "HALightEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HASwitch.h"
#import "HAHaptics.h"
#import "UIFont+HACompat.h"

@interface HALightEntityCell ()
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UISlider *brightnessSlider;
@property (nonatomic, strong) UILabel *brightnessLabel;
@property (nonatomic, strong) UISlider *colorTempSlider;
@property (nonatomic, strong) UILabel *colorTempLabel;
@property (nonatomic, assign) BOOL colorTempDragging;
/// Brightness slider bottom constraint — deactivated when color temp slider is visible
@property (nonatomic, strong) NSLayoutConstraint *brightnessBottomConstraint;
/// Color temp slider bottom constraint — activated when color temp slider is visible
@property (nonatomic, strong) NSLayoutConstraint *colorTempBottomConstraint;
/// Brightness slider pinned above color temp slider
@property (nonatomic, strong) NSLayoutConstraint *brightnessAboveColorTempConstraint;
@property (nonatomic, strong) UIButton *effectButton;
@property (nonatomic, strong) UILabel *colorModeLabel;
@property (nonatomic, strong) NSNumber *transitionSeconds;
@end

@implementation HALightEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    // Toggle switch
    self.toggleSwitch = [[HASwitch alloc] init];
    self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleSwitch addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.toggleSwitch];

    // Brightness slider
    self.brightnessSlider = [[UISlider alloc] init];
    self.brightnessSlider.minimumValue = 0;
    self.brightnessSlider.maximumValue = 100;
    self.brightnessSlider.minimumTrackTintColor = [HATheme switchTintColor];
    self.brightnessSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.brightnessSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.brightnessSlider addTarget:self action:@selector(sliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.brightnessSlider addTarget:self action:@selector(sliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.contentView addSubview:self.brightnessSlider];

    // Brightness percentage label
    self.brightnessLabel = [self labelWithFont:[UIFont ha_monospacedDigitSystemFontOfSize:12 weight:HAFontWeightRegular] color:[HATheme secondaryTextColor] lines:1];
    self.brightnessLabel.textAlignment = NSTextAlignmentRight;

    // Color mode label (secondary text below name, e.g. "Color Temp · 3000K")
    self.colorModeLabel = [self labelWithFont:[UIFont systemFontOfSize:11] color:[HATheme secondaryTextColor] lines:1];
    self.colorModeLabel.hidden = YES;

    // Effect button (shown when entity has effect_list)
    self.effectButton = HASystemButton();
    self.effectButton.titleLabel.font = [UIFont ha_systemFontOfSize:11 weight:HAFontWeightMedium];
    [self.effectButton setTitleColor:[HATheme accentColor] forState:UIControlStateNormal];
    self.effectButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.effectButton.hidden = YES;
    [self.effectButton addTarget:self action:@selector(effectButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.effectButton];

    CGFloat padding = 10.0;
    UIView *cv = self.contentView;

    // Color mode label: below name label
    HAActivateConstraints(@[
        HACon([self.colorModeLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:padding]),
        HACon([self.colorModeLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2]),
    ]);

    // Effect button: right of color mode label or top-right below switch
    HAActivateConstraints(@[
        HACon([self.effectButton.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-padding]),
        HACon([self.effectButton.centerYAnchor constraintEqualToAnchor:self.colorModeLabel.centerYAnchor]),
    ]);

    // Switch: top-right
    HAActivateConstraints(@[
        HACon([self.toggleSwitch.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-padding]),
        HACon([self.toggleSwitch.topAnchor constraintEqualToAnchor:cv.topAnchor constant:padding]),
    ]);

    // Color temperature slider (warm ↔ cool)
    self.colorTempSlider = [[UISlider alloc] init];
    self.colorTempSlider.minimumValue = 2000;
    self.colorTempSlider.maximumValue = 6500;
    self.colorTempSlider.minimumTrackTintColor = [UIColor colorWithRed:1.0 green:0.7 blue:0.3 alpha:1.0]; // warm
    self.colorTempSlider.maximumTrackTintColor = [UIColor colorWithRed:0.6 green:0.8 blue:1.0 alpha:1.0]; // cool
    self.colorTempSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.colorTempSlider.hidden = YES;
    [self.colorTempSlider addTarget:self action:@selector(colorTempSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.colorTempSlider addTarget:self action:@selector(colorTempSliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.colorTempSlider addTarget:self action:@selector(colorTempSliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.contentView addSubview:self.colorTempSlider];

    // Color temp label (e.g. "3000K")
    self.colorTempLabel = [self labelWithFont:[UIFont ha_monospacedDigitSystemFontOfSize:12 weight:HAFontWeightRegular] color:[HATheme secondaryTextColor] lines:1];
    self.colorTempLabel.textAlignment = NSTextAlignmentRight;
    self.colorTempLabel.hidden = YES;

    // Brightness slider: leading edge + bottom (default, swapped when color temp visible)
    HAActivateConstraints(@[
        HACon([self.brightnessSlider.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:padding]),
    ]);
    self.brightnessBottomConstraint = HAMakeConstraint(
        [self.brightnessSlider.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-padding]);
    HASetConstraintActive(self.brightnessBottomConstraint, YES);

    // Color temp slider: below brightness slider, pinned to bottom
    HAActivateConstraints(@[
        HACon([self.colorTempSlider.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:padding]),
        HACon([self.colorTempLabel.leadingAnchor constraintEqualToAnchor:self.colorTempSlider.trailingAnchor constant:8]),
        HACon([self.colorTempLabel.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-padding]),
        HACon([self.colorTempLabel.centerYAnchor constraintEqualToAnchor:self.colorTempSlider.centerYAnchor]),
        HACon([self.colorTempLabel.widthAnchor constraintEqualToConstant:44]),
    ]);
    self.colorTempBottomConstraint = HAMakeConstraint(
        [self.colorTempSlider.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-padding]);
    HASetConstraintActive(self.colorTempBottomConstraint, NO); // activated when visible
    self.brightnessAboveColorTempConstraint = HAMakeConstraint(
        [self.brightnessSlider.bottomAnchor constraintEqualToAnchor:self.colorTempSlider.topAnchor constant:-6]);
    HASetConstraintActive(self.brightnessAboveColorTempConstraint, NO);

    // Brightness label: right of slider
    HAActivateConstraints(@[
        HACon([self.brightnessLabel.leadingAnchor constraintEqualToAnchor:self.brightnessSlider.trailingAnchor constant:8]),
        HACon([self.brightnessLabel.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-padding]),
        HACon([self.brightnessLabel.centerYAnchor constraintEqualToAnchor:self.brightnessSlider.centerYAnchor]),
        HACon([self.brightnessLabel.widthAnchor constraintEqualToConstant:44]),
    ]);
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.brightnessSlider.minimumTrackTintColor = [HATheme switchTintColor];

    // Read transition from card config (seconds)
    id transition = configItem.customProperties[@"transition"];
    self.transitionSeconds = [transition isKindOfClass:[NSNumber class]] ? transition : nil;

    BOOL isOn = entity.isOn;
    self.toggleSwitch.on = isOn;
    self.toggleSwitch.enabled = entity.isAvailable;

    NSInteger pct = [entity brightnessPercent];
    self.brightnessSlider.value = pct;
    self.brightnessSlider.enabled = isOn && entity.isAvailable;
    self.brightnessSlider.hidden = !isOn;
    self.brightnessLabel.hidden = !isOn;
    self.brightnessLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pct];

    // Color temperature slider: only when on and entity supports color_temp
    BOOL showColorTemp = isOn && entity.isAvailable && [entity supportsColorTemp];
    self.colorTempSlider.hidden = !showColorTemp;
    self.colorTempLabel.hidden = !showColorTemp;

    if (showColorTemp) {
        NSNumber *minK = [entity minColorTempKelvin];
        NSNumber *maxK = [entity maxColorTempKelvin];
        self.colorTempSlider.minimumValue = minK ? minK.floatValue : 2000;
        self.colorTempSlider.maximumValue = maxK ? maxK.floatValue : 6500;
        NSNumber *currentK = [entity colorTempKelvin];
        if (currentK && !self.colorTempDragging) {
            self.colorTempSlider.value = currentK.floatValue;
        }
        self.colorTempLabel.text = [NSString stringWithFormat:@"%ldK", (long)self.colorTempSlider.value];

        // Swap constraints: brightness above color temp, color temp at bottom
        HASetConstraintActive(self.brightnessBottomConstraint, NO);
        HASetConstraintActive(self.brightnessAboveColorTempConstraint, YES);
        HASetConstraintActive(self.colorTempBottomConstraint, YES);
    } else {
        // Brightness at bottom (default)
        HASetConstraintActive(self.brightnessAboveColorTempConstraint, NO);
        HASetConstraintActive(self.colorTempBottomConstraint, NO);
        HASetConstraintActive(self.brightnessBottomConstraint, YES);
    }

    // Color mode display (Task 2.4)
    NSString *colorMode = [entity colorMode];
    if (isOn && colorMode.length > 0) {
        NSString *modeDisplay = [[colorMode stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString];
        self.colorModeLabel.text = modeDisplay;
        self.colorModeLabel.hidden = NO;
    } else {
        self.colorModeLabel.hidden = YES;
    }

    // Effects selector (Task 2.3)
    NSArray *effects = [entity effectList];
    NSString *currentEffect = [entity effect];
    if (isOn && effects.count > 0) {
        NSString *title = currentEffect.length > 0
            ? [NSString stringWithFormat:@"\u2728 %@", [currentEffect capitalizedString]]
            : @"\u2728 Effects";
        [self.effectButton setTitle:title forState:UIControlStateNormal];
        self.effectButton.hidden = NO;
    } else {
        self.effectButton.hidden = YES;
    }

    [self applyOnStateTint:isOn];
}

#pragma mark - Helpers

/// Merge transition parameter into service data if configured.
- (NSDictionary *)dataWithTransition:(NSDictionary *)data {
    if (!self.transitionSeconds) return data;
    NSMutableDictionary *merged = data ? [data mutableCopy] : [NSMutableDictionary dictionary];
    merged[@"transition"] = self.transitionSeconds;
    return [merged copy];
}

#pragma mark - Actions

- (void)switchToggled:(UISwitch *)sender {
    [HAHaptics lightImpact];

    NSString *service = sender.isOn ? @"turn_on" : @"turn_off";
    [self callService:service inDomain:[self.entity domain] withData:[self dataWithTransition:nil]];
}

- (void)sliderChanged:(UISlider *)sender {
    NSInteger pct = (NSInteger)sender.value;
    self.brightnessLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pct];
}

- (void)sliderTouchUp:(UISlider *)sender {
    [super sliderTouchUp:sender];

    [HAHaptics lightImpact];

    // Convert 0-100 to 0-255 for HA
    NSInteger brightness = (NSInteger)round((sender.value / 100.0) * 255.0);
    NSDictionary *data = [self dataWithTransition:@{HAAttrBrightness: @(brightness)}];

    [self callService:@"turn_on" inDomain:[self.entity domain] withData:data];
}

- (void)effectButtonTapped {
    if (!self.entity) return;
    NSArray *effects = [self.entity effectList];
    if (effects.count == 0) return;
    NSString *current = [self.entity effect];
    [self presentOptionsWithTitle:@"Light Effect" options:effects current:current sourceView:self.effectButton handler:^(NSString *selected) {
        [self callService:@"turn_on" inDomain:[self.entity domain] withData:[self dataWithTransition:@{HAAttrEffect: selected}]];
    }];
}

- (void)colorTempSliderTouchDown:(UISlider *)sender {
    self.colorTempDragging = YES;
}

- (void)colorTempSliderChanged:(UISlider *)sender {
    self.colorTempLabel.text = [NSString stringWithFormat:@"%ldK", (long)sender.value];
}

- (void)colorTempSliderTouchUp:(UISlider *)sender {
    self.colorTempDragging = NO;

    [HAHaptics lightImpact];

    NSInteger kelvin = (NSInteger)round(sender.value);
    NSDictionary *data = [self dataWithTransition:@{HAAttrColorTempKelvin: @(kelvin)}];
    [self callService:@"turn_on" inDomain:[self.entity domain] withData:data];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat padding = 10.0;
        CGFloat lblW = 44.0;

        // Toggle: top-right
        CGSize switchSize = [self.toggleSwitch sizeThatFits:CGSizeMake(60, 31)];
        self.toggleSwitch.frame = CGRectMake(w - padding - switchSize.width, padding, switchSize.width, switchSize.height);

        // Color mode label: below name
        CGSize cmSize = [self.colorModeLabel sizeThatFits:CGSizeMake(w / 2.0, CGFLOAT_MAX)];
        self.colorModeLabel.frame = CGRectMake(padding, CGRectGetMaxY(self.nameLabel.frame) + 2, cmSize.width, cmSize.height);

        // Effect button: right, same Y as color mode
        CGSize effSize = [self.effectButton sizeThatFits:CGSizeMake(120, CGFLOAT_MAX)];
        self.effectButton.frame = CGRectMake(w - padding - effSize.width, self.colorModeLabel.frame.origin.y, effSize.width, effSize.height);

        // Color temp slider + label: bottom (when visible)
        if (!self.colorTempSlider.hidden) {
            self.colorTempSlider.frame = CGRectMake(padding, h - padding - 31, w - padding * 2 - lblW - 8, 31);
            self.colorTempLabel.frame = CGRectMake(w - padding - lblW, h - padding - 31, lblW, 31);

            // Brightness slider: above color temp
            self.brightnessSlider.frame = CGRectMake(padding, h - padding - 31 - 6 - 31, w - padding * 2 - lblW - 8, 31);
            self.brightnessLabel.frame = CGRectMake(w - padding - lblW, self.brightnessSlider.frame.origin.y, lblW, 31);
        } else {
            // Brightness slider: bottom
            self.brightnessSlider.frame = CGRectMake(padding, h - padding - 31, w - padding * 2 - lblW - 8, 31);
            self.brightnessLabel.frame = CGRectMake(w - padding - lblW, h - padding - 31, lblW, 31);
        }
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.toggleSwitch.on = NO;
    self.brightnessSlider.value = 0;
    self.brightnessSlider.hidden = YES;
    self.brightnessLabel.hidden = YES;
    self.sliderDragging = NO;
    self.colorTempDragging = NO;
    self.colorTempSlider.hidden = YES;
    self.colorTempSlider.value = 4000;
    self.colorTempLabel.hidden = YES;
    // Reset constraints to default (brightness at bottom)
    HASetConstraintActive(self.brightnessAboveColorTempConstraint, NO);
    HASetConstraintActive(self.colorTempBottomConstraint, NO);
    HASetConstraintActive(self.brightnessBottomConstraint, YES);
    self.colorModeLabel.hidden = YES;
    self.colorModeLabel.text = nil;
    self.effectButton.hidden = YES;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.brightnessLabel.textColor = [HATheme secondaryTextColor];
    self.colorTempLabel.textColor = [HATheme secondaryTextColor];
}

@end
