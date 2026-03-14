#import "HAHumidifierEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HASwitch.h"

@interface HAHumidifierEntityCell ()
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UISlider *humiditySlider;
@property (nonatomic, strong) UILabel *humidityLabel;
@property (nonatomic, strong) UILabel *currentHumidityLabel;
@property (nonatomic, strong) UIButton *modeButton;
@end

@implementation HAHumidifierEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Toggle switch
    self.toggleSwitch = [[HASwitch alloc] init];
    self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleSwitch addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.toggleSwitch];

    // Humidity label
    self.humidityLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium] color:[HATheme primaryTextColor] lines:1];
    self.humidityLabel.textAlignment = NSTextAlignmentRight;

    // Humidity slider
    self.humiditySlider = [[UISlider alloc] init];
    self.humiditySlider.minimumTrackTintColor = [HATheme switchTintColor];
    self.humiditySlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.humiditySlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.humiditySlider addTarget:self action:@selector(sliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.humiditySlider addTarget:self action:@selector(sliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.contentView addSubview:self.humiditySlider];

    // Toggle: top-right
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]];

    // Humidity label: between name and toggle
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.humidityLabel attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.toggleSwitch attribute:NSLayoutAttributeLeading multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.humidityLabel attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:self.toggleSwitch attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];

    // Current humidity + mode label row: below name
    self.currentHumidityLabel = [self labelWithFont:[UIFont systemFontOfSize:11] color:[HATheme secondaryTextColor] lines:1];

    // Mode button
    self.modeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.modeButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [self.modeButton setTitleColor:[HATheme accentColor] forState:UIControlStateNormal];
    self.modeButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeButton.hidden = YES;
    [self.modeButton addTarget:self action:@selector(modeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.modeButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.currentHumidityLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [self.currentHumidityLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2],
        [self.modeButton.trailingAnchor constraintEqualToAnchor:self.toggleSwitch.leadingAnchor constant:-8],
        [self.modeButton.centerYAnchor constraintEqualToAnchor:self.currentHumidityLabel.centerYAnchor],
    ]];

    // Slider: bottom
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.humiditySlider attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.humiditySlider attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.humiditySlider attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.humiditySlider.minimumTrackTintColor = [HATheme switchTintColor];

    self.toggleSwitch.on = entity.isOn;
    self.toggleSwitch.enabled = entity.isAvailable;

    float minH = [[entity humidifierMinHumidity] floatValue];
    float maxH = [[entity humidifierMaxHumidity] floatValue];
    self.humiditySlider.minimumValue = minH;
    self.humiditySlider.maximumValue = maxH;
    self.humiditySlider.enabled = entity.isAvailable && entity.isOn;

    NSNumber *target = [entity humidifierTargetHumidity];
    if (!self.sliderDragging && target) {
        self.humiditySlider.value = [target floatValue];
    }

    NSString *display = target ? [NSString stringWithFormat:@"%.0f%%", [target floatValue]] : @"--%%";
    self.humidityLabel.text = display;

    // Current humidity + action display (Tasks 3.10, 3.11)
    NSNumber *currentH = [entity humidifierCurrentHumidity];
    NSString *action = HAAttrString(entity.attributes, @"action");
    NSMutableArray *infoParts = [NSMutableArray array];
    if (currentH) [infoParts addObject:[NSString stringWithFormat:@"Current: %.0f%%", currentH.floatValue]];
    if (action.length > 0) [infoParts addObject:[action capitalizedString]];
    self.currentHumidityLabel.text = infoParts.count > 0 ? [infoParts componentsJoinedByString:@" · "] : nil;
    self.currentHumidityLabel.hidden = (infoParts.count == 0);

    // Mode selector (Task 3.9)
    NSArray *modes = HAAttrArray(entity.attributes, HAAttrAvailableModes);
    NSString *currentMode = HAAttrString(entity.attributes, HAAttrMode);
    if (entity.isOn && modes.count > 0) {
        NSString *title = currentMode.length > 0 ? [currentMode capitalizedString] : @"Mode";
        [self.modeButton setTitle:title forState:UIControlStateNormal];
        self.modeButton.hidden = NO;
    } else {
        self.modeButton.hidden = YES;
    }

    if (entity.isOn) {
        self.contentView.backgroundColor = [HATheme coolTintColor];
    } else {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    }
}

#pragma mark - Actions

- (void)switchToggled:(UISwitch *)sender {
    NSString *service = sender.isOn ? @"turn_on" : @"turn_off";
    [self callService:service inDomain:HAEntityDomainHumidifier];
}

- (void)modeTapped {
    if (!self.entity) return;
    NSArray *modes = HAAttrArray(self.entity.attributes, HAAttrAvailableModes);
    if (modes.count == 0) return;
    NSString *current = HAAttrString(self.entity.attributes, HAAttrMode);
    [self presentOptionsWithTitle:@"Mode" options:modes current:current sourceView:self.modeButton handler:^(NSString *selected) {
        [self callService:@"set_mode" inDomain:HAEntityDomainHumidifier withData:@{@"mode": selected}];
    }];
}

- (void)sliderChanged:(UISlider *)sender {
    self.humidityLabel.text = [NSString stringWithFormat:@"%.0f%%", sender.value];
}

- (void)sliderTouchUp:(UISlider *)sender {
    [super sliderTouchUp:sender];

    float snapped = roundf(sender.value);
    sender.value = snapped;

    NSDictionary *data = @{@"humidity": @((NSInteger)snapped)};
    [self callService:@"set_humidity" inDomain:HAEntityDomainHumidifier withData:data];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.toggleSwitch.on = NO;
    self.toggleSwitch.enabled = YES;
    self.humiditySlider.value = 0;
    self.humiditySlider.enabled = YES;
    self.humidityLabel.text = nil;
    self.sliderDragging = NO;
    self.currentHumidityLabel.hidden = YES;
    self.currentHumidityLabel.text = nil;
    self.modeButton.hidden = YES;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.humidityLabel.textColor = [HATheme primaryTextColor];
}

@end
