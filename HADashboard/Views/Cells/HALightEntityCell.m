#import "HALightEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HASwitch.h"
#import "HAHaptics.h"

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
    self.brightnessSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.brightnessSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.brightnessSlider addTarget:self action:@selector(sliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.brightnessSlider addTarget:self action:@selector(sliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.contentView addSubview:self.brightnessSlider];

    // Brightness percentage label
    self.brightnessLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular] color:[HATheme secondaryTextColor] lines:1];
    self.brightnessLabel.textAlignment = NSTextAlignmentRight;

    // Color mode label (secondary text below name, e.g. "Color Temp · 3000K")
    self.colorModeLabel = [self labelWithFont:[UIFont systemFontOfSize:11] color:[HATheme secondaryTextColor] lines:1];
    self.colorModeLabel.hidden = YES;

    // Effect button (shown when entity has effect_list)
    self.effectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.effectButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [self.effectButton setTitleColor:[HATheme accentColor] forState:UIControlStateNormal];
    self.effectButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.effectButton.hidden = YES;
    [self.effectButton addTarget:self action:@selector(effectButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.effectButton];

    CGFloat padding = 10.0;

    // Color mode label: below name label
    [NSLayoutConstraint activateConstraints:@[
        [self.colorModeLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [self.colorModeLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2],
    ]];

    // Effect button: right of color mode label or top-right below switch
    [NSLayoutConstraint activateConstraints:@[
        [self.effectButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
        [self.effectButton.centerYAnchor constraintEqualToAnchor:self.colorModeLabel.centerYAnchor],
    ]];

    // Switch: top-right
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]];

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
    self.colorTempLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular] color:[HATheme secondaryTextColor] lines:1];
    self.colorTempLabel.textAlignment = NSTextAlignmentRight;
    self.colorTempLabel.hidden = YES;

    // Brightness slider: leading edge
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.brightnessSlider attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];

    // Brightness slider bottom: pinned to contentView bottom (default) or above color temp slider
    self.brightnessBottomConstraint = [NSLayoutConstraint constraintWithItem:self.brightnessSlider attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding];
    self.brightnessBottomConstraint.active = YES;

    // Color temp slider: below brightness slider, pinned to bottom
    [NSLayoutConstraint activateConstraints:@[
        [self.colorTempSlider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [self.colorTempLabel.leadingAnchor constraintEqualToAnchor:self.colorTempSlider.trailingAnchor constant:8],
        [self.colorTempLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
        [self.colorTempLabel.centerYAnchor constraintEqualToAnchor:self.colorTempSlider.centerYAnchor],
        [self.colorTempLabel.widthAnchor constraintEqualToConstant:44],
    ]];
    self.colorTempBottomConstraint = [self.colorTempSlider.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding];
    self.colorTempBottomConstraint.active = NO; // activated when visible
    self.brightnessAboveColorTempConstraint = [self.brightnessSlider.bottomAnchor constraintEqualToAnchor:self.colorTempSlider.topAnchor constant:-6];
    self.brightnessAboveColorTempConstraint.active = NO;

    // Brightness label: right of slider
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.brightnessLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.brightnessSlider attribute:NSLayoutAttributeTrailing multiplier:1 constant:8]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.brightnessLabel attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.brightnessLabel attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:self.brightnessSlider attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.brightnessLabel attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:44]];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

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
        self.brightnessBottomConstraint.active = NO;
        self.brightnessAboveColorTempConstraint.active = YES;
        self.colorTempBottomConstraint.active = YES;
    } else {
        // Brightness at bottom (default)
        self.brightnessAboveColorTempConstraint.active = NO;
        self.colorTempBottomConstraint.active = NO;
        self.brightnessBottomConstraint.active = YES;
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

    // Background tint when on
    if (isOn) {
        self.contentView.backgroundColor = [HATheme onTintColor];
    } else {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    }
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
    self.brightnessAboveColorTempConstraint.active = NO;
    self.colorTempBottomConstraint.active = NO;
    self.brightnessBottomConstraint.active = YES;
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.brightnessLabel.textColor = [HATheme secondaryTextColor];
    self.colorTempLabel.textColor = [HATheme secondaryTextColor];
    self.colorModeLabel.hidden = YES;
    self.colorModeLabel.text = nil;
    self.effectButton.hidden = YES;
}

@end
