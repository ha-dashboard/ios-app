#import "HAAutoLayout.h"
#import "HAFanEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HASwitch.h"
#import "HAHaptics.h"
#import "UIFont+HACompat.h"

@interface HAFanEntityCell ()
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UIButton *presetButton;
@property (nonatomic, strong) UIButton *oscillateButton;
@property (nonatomic, strong) UIButton *directionButton;
@property (nonatomic, strong) UIButton *speedDownButton;
@property (nonatomic, strong) UIButton *speedUpButton;
@end

@implementation HAFanEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // On/off toggle
    self.toggleSwitch = [[HASwitch alloc] init];
    self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleSwitch addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.toggleSwitch];

    // Speed percentage label
    self.speedLabel = [self labelWithFont:[UIFont ha_monospacedDigitSystemFontOfSize:12 weight:HAFontWeightRegular] color:[HATheme secondaryTextColor] lines:1];
    self.speedLabel.textAlignment = NSTextAlignmentRight;

    // Preset mode button (below name, tappable for action sheet)
    self.presetButton = HASystemButton();
    self.presetButton.titleLabel.font = [UIFont ha_systemFontOfSize:11 weight:HAFontWeightMedium];
    [self.presetButton setTitleColor:[HATheme secondaryTextColor] forState:UIControlStateNormal];
    self.presetButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.presetButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.presetButton.hidden = YES;
    [self.presetButton addTarget:self action:@selector(presetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.presetButton];

    // Oscillate button (small icon toggle)
    self.oscillateButton = HASystemButton();
    self.oscillateButton.titleLabel.font = [UIFont ha_systemFontOfSize:11 weight:HAFontWeightMedium];
    self.oscillateButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.oscillateButton.hidden = YES;
    [self.oscillateButton addTarget:self action:@selector(oscillateTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.oscillateButton];

    // Direction button
    self.directionButton = HASystemButton();
    self.directionButton.titleLabel.font = [UIFont ha_systemFontOfSize:11 weight:HAFontWeightMedium];
    self.directionButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.directionButton.hidden = YES;
    [self.directionButton addTarget:self action:@selector(directionTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.directionButton];

    // Speed slider
    self.speedSlider = [[UISlider alloc] init];
    self.speedSlider.minimumValue = 0;
    self.speedSlider.maximumValue = 100;
    self.speedSlider.minimumTrackTintColor = [HATheme switchTintColor];
    self.speedSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.speedSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.speedSlider addTarget:self action:@selector(sliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.speedSlider addTarget:self action:@selector(sliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.contentView addSubview:self.speedSlider];

    // Switch: top-right
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]),
    ]);

    // Preset button: below name
    HAActivateConstraints(@[
        HACon([self.presetButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]),
        HACon([self.presetButton.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2]),
        // Oscillate + direction: right of preset, same Y
        HACon([self.oscillateButton.leadingAnchor constraintEqualToAnchor:self.presetButton.trailingAnchor constant:8]),
        HACon([self.oscillateButton.centerYAnchor constraintEqualToAnchor:self.presetButton.centerYAnchor]),
        HACon([self.directionButton.leadingAnchor constraintEqualToAnchor:self.oscillateButton.trailingAnchor constant:4]),
        HACon([self.directionButton.centerYAnchor constraintEqualToAnchor:self.presetButton.centerYAnchor]),
    ]);

    // Speed slider: bottom
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.speedSlider attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.speedSlider attribute:NSLayoutAttributeBottom
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]),
    ]);

    // Speed label: right of slider
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.speedLabel attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.speedSlider attribute:NSLayoutAttributeTrailing multiplier:1 constant:8]),
        HACon([NSLayoutConstraint constraintWithItem:self.speedLabel attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.speedLabel attribute:NSLayoutAttributeCenterY
            relatedBy:NSLayoutRelationEqual toItem:self.speedSlider attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]),
        HACon([NSLayoutConstraint constraintWithItem:self.speedLabel attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:44]),
    ]);

    // Speed +/- buttons (right side, above/below speed label)
    CGFloat btnSize = 24.0;
    self.speedUpButton = HASystemButton();
    [self.speedUpButton setTitle:@"+" forState:UIControlStateNormal];
    self.speedUpButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.speedUpButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedUpButton.hidden = YES;
    [self.speedUpButton addTarget:self action:@selector(speedUpTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.speedUpButton];

    self.speedDownButton = HASystemButton();
    [self.speedDownButton setTitle:@"\u2212" forState:UIControlStateNormal]; // minus sign
    self.speedDownButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.speedDownButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedDownButton.hidden = YES;
    [self.speedDownButton addTarget:self action:@selector(speedDownTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.speedDownButton];

    HAActivateConstraints(@[
        HACon([self.speedUpButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-2]),
        HACon([self.speedUpButton.bottomAnchor constraintEqualToAnchor:self.speedSlider.topAnchor constant:-2]),
        HACon([self.speedUpButton.widthAnchor constraintEqualToConstant:btnSize]),
        HACon([self.speedUpButton.heightAnchor constraintEqualToConstant:btnSize]),
        HACon([self.speedDownButton.trailingAnchor constraintEqualToAnchor:self.speedUpButton.leadingAnchor constant:-2]),
        HACon([self.speedDownButton.centerYAnchor constraintEqualToAnchor:self.speedUpButton.centerYAnchor]),
        HACon([self.speedDownButton.widthAnchor constraintEqualToConstant:btnSize]),
        HACon([self.speedDownButton.heightAnchor constraintEqualToConstant:btnSize]),
    ]);
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.speedSlider.minimumTrackTintColor = [HATheme switchTintColor];

    BOOL isOn = entity.isOn;
    self.toggleSwitch.on = isOn;
    self.toggleSwitch.enabled = entity.isAvailable;

    NSInteger speedPct = [entity fanSpeedPercent];
    if (!self.sliderDragging) {
        self.speedSlider.value = speedPct;
    }
    self.speedSlider.enabled = isOn && entity.isAvailable;
    self.speedSlider.hidden = !isOn;
    self.speedLabel.hidden = !isOn;
    self.speedLabel.text = [NSString stringWithFormat:@"%ld%%", (long)speedPct];
    self.speedUpButton.hidden = !isOn;
    self.speedDownButton.hidden = !isOn;
    self.speedUpButton.enabled = entity.isAvailable;
    self.speedDownButton.enabled = entity.isAvailable;

    // Preset mode (tappable)
    NSString *preset = [entity fanPresetMode];
    NSArray *presetModes = entity.attributes[@"preset_modes"];
    if (preset && isOn && [presetModes isKindOfClass:[NSArray class]] && presetModes.count > 0) {
        [self.presetButton setTitle:[NSString stringWithFormat:@"%@ \u25BE", [preset capitalizedString]]
                           forState:UIControlStateNormal];
        self.presetButton.hidden = NO;
        self.presetButton.enabled = entity.isAvailable;
    } else {
        self.presetButton.hidden = YES;
    }

    // Oscillate toggle
    NSNumber *oscillating = entity.attributes[@"oscillating"];
    if ([oscillating isKindOfClass:[NSNumber class]] && isOn) {
        NSString *title = [oscillating boolValue] ? @"\u223F On" : @"\u223F Off"; // ∿
        [self.oscillateButton setTitle:title forState:UIControlStateNormal];
        [self.oscillateButton setTitleColor:[oscillating boolValue] ? [HATheme accentColor] : [HATheme secondaryTextColor]
                                   forState:UIControlStateNormal];
        self.oscillateButton.hidden = NO;
        self.oscillateButton.enabled = entity.isAvailable;
    } else {
        self.oscillateButton.hidden = YES;
    }

    // Direction control
    NSString *direction = entity.attributes[@"direction"];
    if ([direction isKindOfClass:[NSString class]] && isOn) {
        NSString *title = [direction isEqualToString:@"reverse"] ? @"\u21BA" : @"\u21BB"; // ↺ ↻
        [self.directionButton setTitle:title forState:UIControlStateNormal];
        self.directionButton.hidden = NO;
        self.directionButton.enabled = entity.isAvailable;
    } else {
        self.directionButton.hidden = YES;
    }

    [self applyOnStateTint:isOn];
}

#pragma mark - Actions

- (void)switchToggled:(UISwitch *)sender {
    [HAHaptics lightImpact];

    NSString *service = sender.isOn ? @"turn_on" : @"turn_off";
    [self callService:service inDomain:@"fan"];
}

- (void)sliderChanged:(UISlider *)sender {
    NSInteger pct = (NSInteger)sender.value;
    self.speedLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pct];
}

- (void)sliderTouchUp:(UISlider *)sender {
    [super sliderTouchUp:sender];

    [HAHaptics lightImpact];

    NSInteger pct = (NSInteger)round(sender.value);
    NSDictionary *data = @{@"percentage": @(pct)};
    [self callService:@"set_percentage" inDomain:@"fan" withData:data];
}

- (void)presetTapped {
    NSArray *modes = self.entity.attributes[@"preset_modes"];
    if (![modes isKindOfClass:[NSArray class]] || modes.count == 0) return;
    NSString *current = [self.entity fanPresetMode];
    [self presentOptionsWithTitle:nil options:modes current:current sourceView:self.presetButton handler:^(NSString *selected) {
        [self callService:@"set_preset_mode" inDomain:@"fan" withData:@{@"preset_mode": selected}];
    }];
}

- (void)oscillateTapped {
    [HAHaptics lightImpact];
    NSNumber *current = self.entity.attributes[@"oscillating"];
    BOOL newValue = ![current boolValue];
    [self callService:@"oscillate" inDomain:@"fan" withData:@{@"oscillating": @(newValue)}];
}

- (void)directionTapped {
    [HAHaptics lightImpact];
    NSString *current = self.entity.attributes[@"direction"];
    NSString *newDir = [current isEqualToString:@"reverse"] ? @"forward" : @"reverse";
    [self callService:@"set_direction" inDomain:@"fan" withData:@{@"direction": newDir}];
}

- (void)speedUpTapped {
    [HAHaptics lightImpact];
    [self callService:@"increase_speed" inDomain:@"fan"];
}

- (void)speedDownTapped {
    [HAHaptics lightImpact];
    [self callService:@"decrease_speed" inDomain:@"fan"];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat padding = 10.0;

        // Toggle: top-right
        CGSize switchSize = [self.toggleSwitch sizeThatFits:CGSizeMake(60, 31)];
        self.toggleSwitch.frame = CGRectMake(w - padding - switchSize.width, padding, switchSize.width, switchSize.height);

        // Preset button: below name
        CGSize presetSize = [self.presetButton sizeThatFits:CGSizeMake(w / 2.0, CGFLOAT_MAX)];
        self.presetButton.frame = CGRectMake(padding, CGRectGetMaxY(self.nameLabel.frame) + 2, presetSize.width, presetSize.height);

        // Oscillate + direction: right of preset
        CGSize oscSize = [self.oscillateButton sizeThatFits:CGSizeMake(60, CGFLOAT_MAX)];
        self.oscillateButton.frame = CGRectMake(CGRectGetMaxX(self.presetButton.frame) + 8, self.presetButton.frame.origin.y, oscSize.width, oscSize.height);
        CGSize dirSize = [self.directionButton sizeThatFits:CGSizeMake(30, CGFLOAT_MAX)];
        self.directionButton.frame = CGRectMake(CGRectGetMaxX(self.oscillateButton.frame) + 4, self.presetButton.frame.origin.y, dirSize.width, dirSize.height);

        // Speed slider: bottom
        self.speedSlider.frame = CGRectMake(padding, h - padding - 31, w - padding * 2 - 52, 31);

        // Speed label: right of slider
        self.speedLabel.frame = CGRectMake(w - padding - 44, h - padding - 31, 44, 31);

        // Speed +/- buttons: above slider, right
        CGFloat btnSize = 24.0;
        self.speedUpButton.frame = CGRectMake(w - 2 - btnSize, h - padding - 31 - 2 - btnSize, btnSize, btnSize);
        self.speedDownButton.frame = CGRectMake(CGRectGetMinX(self.speedUpButton.frame) - 2 - btnSize, self.speedUpButton.frame.origin.y, btnSize, btnSize);
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.toggleSwitch.on = NO;
    self.speedSlider.value = 0;
    self.speedSlider.hidden = YES;
    self.speedLabel.hidden = YES;
    self.speedLabel.text = nil;
    self.presetButton.hidden = YES;
    self.oscillateButton.hidden = YES;
    self.directionButton.hidden = YES;
    self.speedUpButton.hidden = YES;
    self.speedDownButton.hidden = YES;
    self.sliderDragging = NO;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.speedLabel.textColor = [HATheme secondaryTextColor];
}

@end
