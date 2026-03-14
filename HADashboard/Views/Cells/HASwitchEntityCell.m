#import "HAAutoLayout.h"
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

    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-10]),
        HACon([NSLayoutConstraint constraintWithItem:self.toggleSwitch attribute:NSLayoutAttributeCenterY
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeCenterY multiplier:1 constant:8]),
    ]);

    // Hide the state label — the switch is the state indicator
    self.stateLabel.hidden = YES;
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.toggleSwitch.on = entity.isOn;
    self.toggleSwitch.enabled = entity.isAvailable;

    [self applyOnStateTint:entity.isOn];
}

- (void)switchToggled:(UISwitch *)sender {
    if (!self.entity) return;

    [HAHaptics lightImpact];

    NSString *service = sender.isOn ? [self.entity turnOnService] : [self.entity turnOffService];
    [self callService:service inDomain:[self.entity domain]];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGSize switchSize = [self.toggleSwitch sizeThatFits:CGSizeZero];
        self.toggleSwitch.frame = CGRectMake(w - 10 - switchSize.width,
                                             (h / 2.0) + 8 - switchSize.height / 2.0,
                                             switchSize.width, switchSize.height);
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.toggleSwitch.on = NO;
    self.toggleSwitch.enabled = YES;
}

@end
