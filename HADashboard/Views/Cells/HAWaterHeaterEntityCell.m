#import "HAWaterHeaterEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "HAEntityDisplayHelper.h"
#import "HAIconMapper.h"
#import "UIView+HAUtilities.h"

@interface HAWaterHeaterEntityCell ()
@property (nonatomic, strong) UILabel *tempLabel;
@property (nonatomic, strong) UILabel *currentTempLabel;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *modeButton;
@end

@implementation HAWaterHeaterEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Target temperature (large, centered)
    self.tempLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:28 weight:UIFontWeightMedium]
                                   color:[HATheme primaryTextColor] lines:1];
    self.tempLabel.textAlignment = NSTextAlignmentCenter;

    // Current temperature (smaller, below target)
    self.currentTempLabel = [self labelWithFont:[UIFont systemFontOfSize:12] color:[HATheme secondaryTextColor] lines:1];
    self.currentTempLabel.textAlignment = NSTextAlignmentCenter;

    // +/- buttons
    self.minusButton = [self actionButtonWithTitle:@"\u2212" target:self action:@selector(minusTapped)];
    self.plusButton = [self actionButtonWithTitle:@"+" target:self action:@selector(plusTapped)];

    // Mode button
    self.modeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.modeButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [self.modeButton setTitleColor:[HATheme secondaryTextColor] forState:UIControlStateNormal];
    self.modeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modeButton addTarget:self action:@selector(modeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.modeButton];

    [NSLayoutConstraint activateConstraints:@[
        // Temp label centered
        [self.tempLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.tempLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:8],
        // Current temp below target
        [self.currentTempLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.currentTempLabel.topAnchor constraintEqualToAnchor:self.tempLabel.bottomAnchor constant:2],
        // - button left of temp
        [self.minusButton.trailingAnchor constraintEqualToAnchor:self.tempLabel.leadingAnchor constant:-12],
        [self.minusButton.centerYAnchor constraintEqualToAnchor:self.tempLabel.centerYAnchor],
        [self.minusButton.widthAnchor constraintEqualToConstant:36],
        [self.minusButton.heightAnchor constraintEqualToConstant:36],
        // + button right of temp
        [self.plusButton.leadingAnchor constraintEqualToAnchor:self.tempLabel.trailingAnchor constant:12],
        [self.plusButton.centerYAnchor constraintEqualToAnchor:self.tempLabel.centerYAnchor],
        [self.plusButton.widthAnchor constraintEqualToConstant:36],
        [self.plusButton.heightAnchor constraintEqualToConstant:36],
        // Mode button at bottom
        [self.modeButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.modeButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding],
    ]];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];
    self.stateLabel.hidden = YES;

    BOOL available = entity.isAvailable;

    // Target temperature
    NSNumber *target = entity.attributes[@"temperature"];
    NSString *unit = entity.attributes[@"temperature_unit"] ?: @"\u00B0C";
    self.tempLabel.text = target
        ? [NSString stringWithFormat:@"%@%@", target, unit]
        : @"--";

    // Current temperature
    NSNumber *current = entity.attributes[@"current_temperature"];
    if ([current isKindOfClass:[NSNumber class]]) {
        self.currentTempLabel.text = [NSString stringWithFormat:@"Currently %@%@", current, unit];
        self.currentTempLabel.hidden = NO;
    } else {
        self.currentTempLabel.hidden = YES;
    }

    // Operation mode
    NSString *opMode = entity.attributes[@"operation_mode"];
    if ([opMode isKindOfClass:[NSString class]]) {
        [self.modeButton setTitle:[NSString stringWithFormat:@"%@ \u25BE", [opMode capitalizedString]]
                         forState:UIControlStateNormal];
        self.modeButton.hidden = NO;
    } else {
        self.modeButton.hidden = YES;
    }

    self.plusButton.enabled = available;
    self.minusButton.enabled = available;
    self.modeButton.enabled = available;

    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
}

#pragma mark - Actions

- (void)plusTapped {
    [HAHaptics lightImpact];
    NSNumber *target = self.entity.attributes[@"temperature"];
    double step = 1.0;
    NSNumber *attrStep = self.entity.attributes[@"target_temp_step"];
    if (attrStep) step = [attrStep doubleValue];
    double newTemp = target ? [target doubleValue] + step : 50.0;
    double maxTemp = [self.entity.attributes[@"max_temp"] doubleValue] ?: 65.0;
    newTemp = MIN(newTemp, maxTemp);
    [self callService:@"set_temperature" inDomain:@"water_heater"
             withData:@{@"temperature": @(newTemp)}];
}

- (void)minusTapped {
    [HAHaptics lightImpact];
    NSNumber *target = self.entity.attributes[@"temperature"];
    double step = 1.0;
    NSNumber *attrStep = self.entity.attributes[@"target_temp_step"];
    if (attrStep) step = [attrStep doubleValue];
    double newTemp = target ? [target doubleValue] - step : 50.0;
    double minTemp = [self.entity.attributes[@"min_temp"] doubleValue] ?: 30.0;
    newTemp = MAX(newTemp, minTemp);
    [self callService:@"set_temperature" inDomain:@"water_heater"
             withData:@{@"temperature": @(newTemp)}];
}

- (void)modeTapped {
    NSArray *modes = self.entity.attributes[@"operation_list"];
    if (![modes isKindOfClass:[NSArray class]] || modes.count == 0) return;

    NSString *current = self.entity.attributes[@"operation_mode"];
    [self presentOptionsWithTitle:nil options:modes current:current sourceView:self.modeButton
                          handler:^(NSString *selected) {
        [HAHaptics lightImpact];
        [self callService:@"set_operation_mode" inDomain:@"water_heater"
                 withData:@{@"operation_mode": selected}];
    }];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.tempLabel.text = nil;
    self.currentTempLabel.text = nil;
    self.currentTempLabel.hidden = YES;
    self.modeButton.hidden = YES;
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
}

@end
