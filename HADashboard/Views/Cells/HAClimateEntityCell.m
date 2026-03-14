#import "HAAutoLayout.h"
#import "HAClimateEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAEntityDisplayHelper.h"
#import "UIFont+HACompat.h"

@interface HAClimateEntityCell ()
@property (nonatomic, strong) UILabel *currentTempLabel;
@property (nonatomic, strong) UILabel *targetTempLabel;
@property (nonatomic, strong) UIStepper *tempStepper;
@property (nonatomic, strong) UILabel *modeLabel;
@end

@implementation HAClimateEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    // Current temperature: large display
    self.currentTempLabel = [[UILabel alloc] init];
    self.currentTempLabel.font = [UIFont ha_monospacedDigitSystemFontOfSize:26 weight:HAFontWeightMedium];
    self.currentTempLabel.textColor = [HATheme primaryTextColor];
    self.currentTempLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.currentTempLabel];

    // HVAC mode label
    self.modeLabel = [[UILabel alloc] init];
    self.modeLabel.font = [UIFont systemFontOfSize:11];
    self.modeLabel.textColor = [HATheme secondaryTextColor];
    self.modeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.modeLabel];

    // Target temperature label
    self.targetTempLabel = [[UILabel alloc] init];
    self.targetTempLabel.font = [UIFont ha_monospacedDigitSystemFontOfSize:14 weight:HAFontWeightRegular];
    self.targetTempLabel.textColor = [HATheme primaryTextColor];
    self.targetTempLabel.textAlignment = NSTextAlignmentRight;
    self.targetTempLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.targetTempLabel];

    // Stepper for target temperature
    self.tempStepper = [[UIStepper alloc] init];
    self.tempStepper.minimumValue = 10;
    self.tempStepper.maximumValue = 35;
    self.tempStepper.stepValue = 0.5;
    self.tempStepper.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tempStepper addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.tempStepper];

    CGFloat padding = 10.0;

    // Current temp: left side, vertically centered
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.currentTempLabel attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.currentTempLabel attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.nameLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:2]),
    ]);

    // Mode label: below current temp
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.modeLabel attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.modeLabel attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.currentTempLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:2]),
    ]);

    // Stepper: bottom-right
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.tempStepper attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.tempStepper attribute:NSLayoutAttributeBottom
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]),
    ]);

    // Target label: above stepper
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.targetTempLabel attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.targetTempLabel attribute:NSLayoutAttributeBottom
            relatedBy:NSLayoutRelationEqual toItem:self.tempStepper attribute:NSLayoutAttributeTop multiplier:1 constant:-4]),
    ]);
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    NSNumber *currentTemp = [entity currentTemperature];
    NSNumber *targetTemp  = [entity targetTemperature];

    if (currentTemp) {
        self.currentTempLabel.text = [NSString stringWithFormat:@"%.1f\u00B0", currentTemp.doubleValue];
    } else {
        self.currentTempLabel.text = @"—";
    }

    NSString *mode = [entity hvacMode];
    self.modeLabel.text = [HAEntityDisplayHelper humanReadableState:mode];

    BOOL hasTarget = targetTemp != nil && ![mode isEqualToString:@"off"];
    self.tempStepper.hidden = !hasTarget;
    self.tempStepper.enabled = hasTarget && entity.isAvailable;
    self.targetTempLabel.hidden = !hasTarget;

    if (hasTarget) {
        // Update stepper range/step from entity attributes (matches detail view behavior)
        self.tempStepper.minimumValue = entity.minTemperature.doubleValue;
        self.tempStepper.maximumValue = entity.maxTemperature.doubleValue;
        double stepVal = HAAttrDouble(entity.attributes, @"target_temp_step", 0.5);
        if (stepVal > 0) self.tempStepper.stepValue = stepVal;
        self.tempStepper.value = targetTemp.doubleValue;
        self.targetTempLabel.text = [NSString stringWithFormat:@"Target: %.1f\u00B0", targetTemp.doubleValue];
    }

    // Background color based on mode
    if ([mode isEqualToString:@"heat"]) {
        self.contentView.backgroundColor = [HATheme heatTintColor];
    } else if ([mode isEqualToString:@"cool"]) {
        self.contentView.backgroundColor = [HATheme coolTintColor];
    } else {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    }
}

- (void)stepperChanged:(UIStepper *)sender {
    double target = sender.value;
    self.targetTempLabel.text = [NSString stringWithFormat:@"Target: %.1f\u00B0", target];

    if (!self.entity) return;
    NSDictionary *data = @{@"temperature": @(target)};
    [[HAConnectionManager sharedManager] callService:@"set_temperature"
                                            inDomain:@"climate"
                                            withData:data
                                            entityId:self.entity.entityId];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat padding = 10.0;

        // currentTempLabel: left, below name
        CGSize tempSize = [self.currentTempLabel sizeThatFits:CGSizeMake(w / 2.0, CGFLOAT_MAX)];
        self.currentTempLabel.frame = CGRectMake(padding, CGRectGetMaxY(self.nameLabel.frame) + 2, tempSize.width, tempSize.height);

        // modeLabel: below current temp
        CGSize modeSize = [self.modeLabel sizeThatFits:CGSizeMake(w / 2.0, CGFLOAT_MAX)];
        self.modeLabel.frame = CGRectMake(padding, CGRectGetMaxY(self.currentTempLabel.frame) + 2, modeSize.width, modeSize.height);

        // tempStepper: bottom-right
        CGSize stepSize = self.tempStepper.intrinsicContentSize;
        self.tempStepper.frame = CGRectMake(w - padding - stepSize.width, h - padding - stepSize.height, stepSize.width, stepSize.height);

        // targetTempLabel: above stepper, right-aligned
        CGSize targetSize = [self.targetTempLabel sizeThatFits:CGSizeMake(w / 2.0, CGFLOAT_MAX)];
        self.targetTempLabel.frame = CGRectMake(w - padding - targetSize.width, CGRectGetMinY(self.tempStepper.frame) - 4 - targetSize.height, targetSize.width, targetSize.height);
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.currentTempLabel.text = nil;
    self.targetTempLabel.text = nil;
    self.modeLabel.text = nil;
    self.tempStepper.value = 20;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.currentTempLabel.textColor = [HATheme primaryTextColor];
    self.modeLabel.textColor = [HATheme secondaryTextColor];
    self.targetTempLabel.textColor = [HATheme primaryTextColor];
}

@end
