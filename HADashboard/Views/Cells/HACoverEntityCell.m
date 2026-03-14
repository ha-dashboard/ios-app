#import "HAAutoLayout.h"
#import "HACoverEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "UIFont+HACompat.h"

@interface HACoverEntityCell ()
@property (nonatomic, strong) UIButton *openButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *positionLabel;
@property (nonatomic, strong) UISlider *positionSlider;
@property (nonatomic, strong) UISlider *tiltSlider;
@property (nonatomic, strong) UILabel *tiltLabel;
@property (nonatomic, assign) BOOL isTrackingSlider;
@end

@implementation HACoverEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat btnHeight = 30.0;
    CGFloat btnWidth  = 56.0;
    CGFloat spacing   = 6.0;
    CGFloat padding   = 10.0;

    self.openButton = [self makeButtonWithTitle:@"\u25B2 Open" action:@selector(openTapped)];
    self.stopButton = [self makeButtonWithTitle:@"\u25A0 Stop" action:@selector(stopTapped)];
    self.closeButton = [self makeButtonWithTitle:@"\u25BC Close" action:@selector(closeTapped)];

    self.stopButton.backgroundColor = [HATheme buttonBackgroundColor];

    self.positionLabel = [self labelWithFont:[UIFont ha_monospacedDigitSystemFontOfSize:12 weight:HAFontWeightRegular] color:[HATheme secondaryTextColor] lines:1];
    self.positionLabel.textAlignment = NSTextAlignmentRight;

    // Position label: top-right
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.positionLabel attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.positionLabel attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]),
    ]);

    // Buttons: bottom row, centered
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.stopButton attribute:NSLayoutAttributeCenterX
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]),
        HACon([NSLayoutConstraint constraintWithItem:self.stopButton attribute:NSLayoutAttributeBottom
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.stopButton attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:btnWidth]),
        HACon([NSLayoutConstraint constraintWithItem:self.stopButton attribute:NSLayoutAttributeHeight
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:btnHeight]),
        HACon([NSLayoutConstraint constraintWithItem:self.openButton attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.stopButton attribute:NSLayoutAttributeLeading multiplier:1 constant:-spacing]),
        HACon([NSLayoutConstraint constraintWithItem:self.openButton attribute:NSLayoutAttributeCenterY
            relatedBy:NSLayoutRelationEqual toItem:self.stopButton attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]),
        HACon([NSLayoutConstraint constraintWithItem:self.openButton attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:btnWidth]),
        HACon([NSLayoutConstraint constraintWithItem:self.openButton attribute:NSLayoutAttributeHeight
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:btnHeight]),
        HACon([NSLayoutConstraint constraintWithItem:self.closeButton attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.stopButton attribute:NSLayoutAttributeTrailing multiplier:1 constant:spacing]),
        HACon([NSLayoutConstraint constraintWithItem:self.closeButton attribute:NSLayoutAttributeCenterY
            relatedBy:NSLayoutRelationEqual toItem:self.stopButton attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]),
        HACon([NSLayoutConstraint constraintWithItem:self.closeButton attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:btnWidth]),
        HACon([NSLayoutConstraint constraintWithItem:self.closeButton attribute:NSLayoutAttributeHeight
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:btnHeight]),
    ]);

    // Position slider — between buttons and name area
    self.positionSlider = [[UISlider alloc] init];
    self.positionSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.positionSlider.minimumValue = 0;
    self.positionSlider.maximumValue = 100;
    self.positionSlider.hidden = YES;
    [self.positionSlider addTarget:self action:@selector(posSliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [self.positionSlider addTarget:self action:@selector(posSliderChanged) forControlEvents:UIControlEventValueChanged];
    [self.positionSlider addTarget:self action:@selector(posSliderTouchUp) forControlEvents:UIControlEventTouchUpInside];
    [self.positionSlider addTarget:self action:@selector(posSliderTouchUp) forControlEvents:UIControlEventTouchUpOutside];
    [self.contentView addSubview:self.positionSlider];

    HAActivateConstraints(@[
        HACon([self.positionSlider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]),
        HACon([self.positionSlider.trailingAnchor constraintEqualToAnchor:self.positionLabel.leadingAnchor constant:-8]),
        HACon([self.positionSlider.bottomAnchor constraintEqualToAnchor:self.openButton.topAnchor constant:-6]),
    ]);

    // Tilt slider + label
    self.tiltLabel = [self labelWithFont:[UIFont ha_monospacedDigitSystemFontOfSize:10 weight:HAFontWeightRegular]
                                   color:[HATheme secondaryTextColor] lines:1];
    self.tiltLabel.hidden = YES;

    self.tiltSlider = [[UISlider alloc] init];
    self.tiltSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.tiltSlider.minimumValue = 0;
    self.tiltSlider.maximumValue = 100;
    self.tiltSlider.hidden = YES;
    [self.tiltSlider addTarget:self action:@selector(tiltSliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [self.tiltSlider addTarget:self action:@selector(tiltSliderChanged) forControlEvents:UIControlEventValueChanged];
    [self.tiltSlider addTarget:self action:@selector(tiltSliderTouchUp) forControlEvents:UIControlEventTouchUpInside];
    [self.tiltSlider addTarget:self action:@selector(tiltSliderTouchUp) forControlEvents:UIControlEventTouchUpOutside];
    [self.contentView addSubview:self.tiltSlider];

    HAActivateConstraints(@[
        HACon([self.tiltLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding]),
        HACon([self.tiltLabel.centerYAnchor constraintEqualToAnchor:self.positionSlider.centerYAnchor]),
        HACon([self.tiltSlider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]),
        HACon([self.tiltSlider.trailingAnchor constraintEqualToAnchor:self.tiltLabel.leadingAnchor constant:-4]),
        HACon([self.tiltSlider.bottomAnchor constraintEqualToAnchor:self.positionSlider.topAnchor constant:-4]),
    ]);
}

- (UIButton *)makeButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *btn = HASystemButton();
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont ha_systemFontOfSize:11 weight:HAFontWeightMedium];
    btn.backgroundColor = [HATheme buttonBackgroundColor];
    btn.layer.cornerRadius = 4.0;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:btn];
    return btn;
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    BOOL available = entity.isAvailable;
    // Filter buttons by supported_features bitmask (HA cover feature flags)
    // SUPPORT_OPEN=0x01, SUPPORT_CLOSE=0x02, SUPPORT_STOP=0x08
    NSInteger features = [entity supportedFeatures];
    BOOL hasFeatures = (features > 0); // 0 means not reported — show all
    self.openButton.hidden  = hasFeatures && !(features & 0x01);
    self.closeButton.hidden = hasFeatures && !(features & 0x02);
    self.stopButton.hidden  = hasFeatures && !(features & 0x08);
    self.openButton.enabled = available;
    self.stopButton.enabled = available;
    self.closeButton.enabled = available;

    // Position slider + label
    NSInteger position = [entity coverPosition];
    NSNumber *posAttr = HAAttrNumber(entity.attributes, HAAttrCurrentPosition);
    BOOL hasPosition = (posAttr != nil) && (features == 0 || (features & 0x04)); // SUPPORT_SET_POSITION=0x04
    if (hasPosition) {
        self.positionLabel.text = [NSString stringWithFormat:@"%ld%%", (long)position];
        self.positionLabel.hidden = NO;
        self.positionSlider.hidden = NO;
        self.positionSlider.enabled = available;
        if (!self.isTrackingSlider) {
            self.positionSlider.value = position;
        }
        self.positionSlider.minimumTrackTintColor = [HATheme activeTintColor];
    } else {
        self.positionLabel.hidden = YES;
        self.positionSlider.hidden = YES;
    }

    // Tilt slider
    NSNumber *tiltAttr = entity.attributes[@"current_tilt_position"];
    BOOL hasTilt = ([tiltAttr isKindOfClass:[NSNumber class]]);
    if (hasTilt) {
        self.tiltSlider.hidden = NO;
        self.tiltSlider.enabled = available;
        self.tiltLabel.hidden = NO;
        self.tiltLabel.text = [NSString stringWithFormat:@"Tilt %ld%%", (long)[tiltAttr integerValue]];
        if (!self.isTrackingSlider) {
            self.tiltSlider.value = [tiltAttr floatValue];
        }
        self.tiltSlider.minimumTrackTintColor = [HATheme activeTintColor];
    } else {
        self.tiltSlider.hidden = YES;
        self.tiltLabel.hidden = YES;
    }

    // Highlight state
    NSString *state = entity.state;
    if ([state isEqualToString:@"open"]) {
        self.contentView.backgroundColor = [HATheme activeTintColor];
    } else if ([state isEqualToString:@"opening"] || [state isEqualToString:@"closing"]) {
        self.contentView.backgroundColor = [HATheme onTintColor];
    } else {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    }
}

#pragma mark - Actions

- (NSString *)serviceDomain {
    // Support both cover and valve domains — same UI, different service names
    return [self.entity domain] ?: @"cover";
}

- (void)openTapped {
    [HAHaptics mediumImpact];
    NSString *domain = [self serviceDomain];
    NSString *service = [domain isEqualToString:@"valve"] ? @"open_valve" : @"open_cover";
    [self callService:service inDomain:domain];
}

- (void)stopTapped {
    [HAHaptics mediumImpact];
    NSString *domain = [self serviceDomain];
    NSString *service = [domain isEqualToString:@"valve"] ? @"stop_valve" : @"stop_cover";
    [self callService:service inDomain:domain];
}

- (void)closeTapped {
    [HAHaptics mediumImpact];
    NSString *domain = [self serviceDomain];
    NSString *service = [domain isEqualToString:@"valve"] ? @"close_valve" : @"close_cover";
    [self callService:service inDomain:domain];
}

#pragma mark - Position Slider

- (void)posSliderTouchDown { self.isTrackingSlider = YES; }

- (void)posSliderChanged {
    self.positionLabel.text = [NSString stringWithFormat:@"%.0f%%", self.positionSlider.value];
}

- (void)posSliderTouchUp {
    self.isTrackingSlider = NO;
    [HAHaptics lightImpact];
    NSString *domain = [self serviceDomain];
    NSString *service = [domain isEqualToString:@"valve"] ? @"set_valve_position" : @"set_cover_position";
    [self callService:service inDomain:domain
             withData:@{@"position": @((NSInteger)self.positionSlider.value)}];
}

#pragma mark - Tilt Slider

- (void)tiltSliderTouchDown { self.isTrackingSlider = YES; }

- (void)tiltSliderChanged {
    self.tiltLabel.text = [NSString stringWithFormat:@"Tilt %.0f%%", self.tiltSlider.value];
}

- (void)tiltSliderTouchUp {
    self.isTrackingSlider = NO;
    [HAHaptics lightImpact];
    NSString *domain = [self serviceDomain];
    // Valve doesn't have tilt, but keep the service call generic
    [self callService:@"set_cover_tilt_position" inDomain:domain
             withData:@{@"tilt_position": @((NSInteger)self.tiltSlider.value)}];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat padding = 10.0;
        CGFloat btnH = 30.0;
        CGFloat btnW = 56.0;
        CGFloat spacing = 6.0;

        // Position label: top-right
        CGSize posSize = [self.positionLabel sizeThatFits:CGSizeMake(60, CGFLOAT_MAX)];
        self.positionLabel.frame = CGRectMake(w - padding - posSize.width, padding, posSize.width, posSize.height);

        // Buttons: bottom row, centered
        CGFloat btnY = h - padding - btnH;
        CGFloat totalW = btnW * 3 + spacing * 2;
        CGFloat startX = (w - totalW) / 2.0;
        self.openButton.frame = CGRectMake(startX, btnY, btnW, btnH);
        self.stopButton.frame = CGRectMake(startX + btnW + spacing, btnY, btnW, btnH);
        self.closeButton.frame = CGRectMake(startX + (btnW + spacing) * 2, btnY, btnW, btnH);

        // Position slider: above buttons
        CGFloat sliderY = btnY - 6 - 31;
        CGFloat sliderTrailX = self.positionLabel.hidden ? (w - padding) : CGRectGetMinX(self.positionLabel.frame) - 8;
        self.positionSlider.frame = CGRectMake(padding, sliderY, sliderTrailX - padding, 31);

        // Tilt label + slider: above position slider
        if (!self.tiltSlider.hidden) {
            CGSize tiltLblSize = [self.tiltLabel sizeThatFits:CGSizeMake(80, CGFLOAT_MAX)];
            self.tiltLabel.frame = CGRectMake(w - padding - tiltLblSize.width, sliderY - 4 - 31 + (31 - tiltLblSize.height) / 2.0, tiltLblSize.width, tiltLblSize.height);
            self.tiltSlider.frame = CGRectMake(padding, sliderY - 4 - 31, CGRectGetMinX(self.tiltLabel.frame) - 4 - padding, 31);
        }
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.positionLabel.text = nil;
    self.positionLabel.hidden = YES;
    self.positionSlider.hidden = YES;
    self.tiltSlider.hidden = YES;
    self.tiltLabel.hidden = YES;
    self.isTrackingSlider = NO;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.positionLabel.textColor = [HATheme secondaryTextColor];
    self.openButton.backgroundColor = [HATheme buttonBackgroundColor];
    self.stopButton.backgroundColor = [HATheme buttonBackgroundColor];
    self.closeButton.backgroundColor = [HATheme buttonBackgroundColor];
}

@end
