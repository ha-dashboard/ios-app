#import "HASwitchEntityCell.h"
#import "HASwitch.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"

@interface HASwitchEntityCell ()
@property (nonatomic, strong) UISwitch *toggleSwitch;
@end

@implementation HASwitchEntityCell

- (void)setupSubviews {
    [super setupSubviews];

    self.toggleSwitch = [[HASwitch alloc] init];
    self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleSwitch addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.toggleSwitch];

    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-10]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeCenterY multiplier:1 constant:8]];

    // Hide the state label — the switch is the state indicator
    self.stateLabel.hidden = YES;
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.toggleSwitch.on = entity.isOn;
    self.toggleSwitch.enabled = entity.isAvailable;

    // Tint based on state
    if (entity.isOn) {
        self.contentView.backgroundColor = [HATheme onTintColor];
    } else {
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    }
}

- (void)switchToggled:(UISwitch *)sender {
    if (!self.entity) return;

    [HAHaptics lightImpact];

    NSString *service = sender.isOn ? [self.entity turnOnService] : [self.entity turnOffService];
    [[HAConnectionManager sharedManager] callService:service
                                            inDomain:[self.entity domain]
                                            withData:nil
                                            entityId:self.entity.entityId];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.toggleSwitch.on = NO;
    self.toggleSwitch.enabled = YES;
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
}

@end
