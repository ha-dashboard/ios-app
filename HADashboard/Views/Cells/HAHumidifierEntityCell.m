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
@property (nonatomic, assign) BOOL sliderDragging;
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
    self.humidityLabel = [[UILabel alloc] init];
    self.humidityLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium];
    self.humidityLabel.textColor = [HATheme primaryTextColor];
    self.humidityLabel.textAlignment = NSTextAlignmentRight;
    self.humidityLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.humidityLabel];

    // Humidity slider
    self.humiditySlider = [[UISlider alloc] init];
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

    if (entity.isOn) {
        self.contentView.backgroundColor = [HATheme coolTintColor];
    } else {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    }
}

#pragma mark - Actions

- (void)switchToggled:(UISwitch *)sender {
    if (!self.entity) return;

    NSString *service = sender.isOn ? @"turn_on" : @"turn_off";
    [[HAConnectionManager sharedManager] callService:service
                                            inDomain:HAEntityDomainHumidifier
                                            withData:nil
                                            entityId:self.entity.entityId];
}

- (void)sliderTouchDown:(UISlider *)sender {
    self.sliderDragging = YES;
}

- (void)sliderChanged:(UISlider *)sender {
    self.humidityLabel.text = [NSString stringWithFormat:@"%.0f%%", sender.value];
}

- (void)sliderTouchUp:(UISlider *)sender {
    self.sliderDragging = NO;
    if (!self.entity) return;

    float snapped = roundf(sender.value);
    sender.value = snapped;

    NSDictionary *data = @{@"humidity": @((NSInteger)snapped)};
    [[HAConnectionManager sharedManager] callService:@"set_humidity"
                                            inDomain:HAEntityDomainHumidifier
                                            withData:data
                                            entityId:self.entity.entityId];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.toggleSwitch.on = NO;
    self.toggleSwitch.enabled = YES;
    self.humiditySlider.value = 0;
    self.humiditySlider.enabled = YES;
    self.humidityLabel.text = nil;
    self.sliderDragging = NO;
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.humidityLabel.textColor = [HATheme primaryTextColor];
}

@end
