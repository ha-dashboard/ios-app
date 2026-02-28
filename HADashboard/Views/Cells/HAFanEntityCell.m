#import "HAFanEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HASwitch.h"
#import "HAHaptics.h"

@interface HAFanEntityCell ()
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UILabel *presetLabel;
@property (nonatomic, assign) BOOL sliderDragging;
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
    self.speedLabel = [[UILabel alloc] init];
    self.speedLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.speedLabel.textColor = [HATheme secondaryTextColor];
    self.speedLabel.textAlignment = NSTextAlignmentRight;
    self.speedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.speedLabel];

    // Preset mode label (below name when applicable)
    self.presetLabel = [[UILabel alloc] init];
    self.presetLabel.font = [UIFont systemFontOfSize:11];
    self.presetLabel.textColor = [HATheme secondaryTextColor];
    self.presetLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.presetLabel];

    // Speed slider
    self.speedSlider = [[UISlider alloc] init];
    self.speedSlider.minimumValue = 0;
    self.speedSlider.maximumValue = 100;
    self.speedSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.speedSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.speedSlider addTarget:self action:@selector(sliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.speedSlider addTarget:self action:@selector(sliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.contentView addSubview:self.speedSlider];

    // Switch: top-right
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]];

    // Preset label: below name
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.presetLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.presetLabel attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.nameLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:2]];

    // Speed slider: bottom
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.speedSlider attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.speedSlider attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]];

    // Speed label: right of slider
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.speedLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.speedSlider attribute:NSLayoutAttributeTrailing multiplier:1 constant:8]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.speedLabel attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.speedLabel attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:self.speedSlider attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.speedLabel attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:44]];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

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

    // Show preset mode if active
    NSString *preset = [entity fanPresetMode];
    if (preset && isOn) {
        self.presetLabel.text = preset;
        self.presetLabel.hidden = NO;
    } else {
        self.presetLabel.hidden = YES;
    }

    // Background tint when on
    if (isOn) {
        self.contentView.backgroundColor = [HATheme onTintColor];
    } else {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    }
}

#pragma mark - Actions

- (void)switchToggled:(UISwitch *)sender {
    if (!self.entity) return;

    [HAHaptics lightImpact];

    NSString *service = sender.isOn ? @"turn_on" : @"turn_off";
    [[HAConnectionManager sharedManager] callService:service
                                            inDomain:@"fan"
                                            withData:nil
                                            entityId:self.entity.entityId];
}

- (void)sliderTouchDown:(UISlider *)sender {
    self.sliderDragging = YES;
}

- (void)sliderChanged:(UISlider *)sender {
    NSInteger pct = (NSInteger)sender.value;
    self.speedLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pct];
}

- (void)sliderTouchUp:(UISlider *)sender {
    self.sliderDragging = NO;
    if (!self.entity) return;

    [HAHaptics lightImpact];

    NSInteger pct = (NSInteger)round(sender.value);
    NSDictionary *data = @{@"percentage": @(pct)};
    [[HAConnectionManager sharedManager] callService:@"set_percentage"
                                            inDomain:@"fan"
                                            withData:data
                                            entityId:self.entity.entityId];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.toggleSwitch.on = NO;
    self.speedSlider.value = 0;
    self.speedSlider.hidden = YES;
    self.speedLabel.hidden = YES;
    self.speedLabel.text = nil;
    self.presetLabel.hidden = YES;
    self.sliderDragging = NO;
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.speedLabel.textColor = [HATheme secondaryTextColor];
    self.presetLabel.textColor = [HATheme secondaryTextColor];
}

@end
