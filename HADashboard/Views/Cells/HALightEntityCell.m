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
@property (nonatomic, assign) BOOL sliderDragging;
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
    self.brightnessLabel = [[UILabel alloc] init];
    self.brightnessLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.brightnessLabel.textColor = [HATheme secondaryTextColor];
    self.brightnessLabel.textAlignment = NSTextAlignmentRight;
    self.brightnessLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.brightnessLabel];

    CGFloat padding = 10.0;

    // Switch: top-right
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]];

    // Slider: bottom area
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.brightnessSlider attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.brightnessSlider attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]];

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

    BOOL isOn = entity.isOn;
    self.toggleSwitch.on = isOn;
    self.toggleSwitch.enabled = entity.isAvailable;

    NSInteger pct = [entity brightnessPercent];
    self.brightnessSlider.value = pct;
    self.brightnessSlider.enabled = isOn && entity.isAvailable;
    self.brightnessSlider.hidden = !isOn;
    self.brightnessLabel.hidden = !isOn;
    self.brightnessLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pct];

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
                                            inDomain:[self.entity domain]
                                            withData:nil
                                            entityId:self.entity.entityId];
}

- (void)sliderTouchDown:(UISlider *)sender {
    self.sliderDragging = YES;
}

- (void)sliderChanged:(UISlider *)sender {
    NSInteger pct = (NSInteger)sender.value;
    self.brightnessLabel.text = [NSString stringWithFormat:@"%ld%%", (long)pct];
}

- (void)sliderTouchUp:(UISlider *)sender {
    self.sliderDragging = NO;
    if (!self.entity) return;

    [HAHaptics lightImpact];

    // Convert 0-100 to 0-255 for HA
    NSInteger brightness = (NSInteger)round((sender.value / 100.0) * 255.0);
    NSDictionary *data = @{HAAttrBrightness: @(brightness)};

    [[HAConnectionManager sharedManager] callService:@"turn_on"
                                            inDomain:[self.entity domain]
                                            withData:data
                                            entityId:self.entity.entityId];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.toggleSwitch.on = NO;
    self.brightnessSlider.value = 0;
    self.brightnessSlider.hidden = YES;
    self.brightnessLabel.hidden = YES;
    self.sliderDragging = NO;
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.brightnessLabel.textColor = [HATheme secondaryTextColor];
}

@end
