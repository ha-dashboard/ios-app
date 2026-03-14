#import "HAAutoLayout.h"
#import "HARemoteEntityCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HASwitch.h"
#import "HAHaptics.h"
#import "UIView+HAUtilities.h"
#import "UIFont+HACompat.h"

@interface HARemoteEntityCell ()
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UIButton *activityButton;
@end

@implementation HARemoteEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    self.toggleSwitch = [[HASwitch alloc] init];
    self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleSwitch addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.toggleSwitch];

    self.activityButton = HASystemButton();
    self.activityButton.titleLabel.font = [UIFont ha_systemFontOfSize:11 weight:HAFontWeightMedium];
    [self.activityButton setTitleColor:[HATheme secondaryTextColor] forState:UIControlStateNormal];
    self.activityButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityButton.hidden = YES;
    [self.activityButton addTarget:self action:@selector(activityTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.activityButton];

    HAActivateConstraints(@[
        HACon([self.toggleSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding]),
        HACon([self.toggleSwitch.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:padding]),
        HACon([self.activityButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]),
        HACon([self.activityButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding]),
    ]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat padding = 10.0;
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;

        CGSize switchSize = [self.toggleSwitch sizeThatFits:CGSizeZero];
        self.toggleSwitch.frame = CGRectMake(w - padding - switchSize.width, padding, switchSize.width, switchSize.height);

        CGSize actSize = [self.activityButton sizeThatFits:CGSizeMake(w - padding * 2, CGFLOAT_MAX)];
        self.activityButton.frame = CGRectMake(padding, h - padding - actSize.height, actSize.width, actSize.height);
    }
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];
    self.stateLabel.hidden = YES;

    BOOL isOn = [entity.state isEqualToString:@"on"];
    self.toggleSwitch.on = isOn;
    self.toggleSwitch.enabled = entity.isAvailable;

    NSString *activity = entity.attributes[@"current_activity"];
    NSArray *activities = entity.attributes[@"activity_list"];
    if ([activity isKindOfClass:[NSString class]] && [activities isKindOfClass:[NSArray class]] && activities.count > 0) {
        [self.activityButton setTitle:[NSString stringWithFormat:@"%@ \u25BE", activity] forState:UIControlStateNormal];
        self.activityButton.hidden = NO;
        self.activityButton.enabled = entity.isAvailable;
    } else {
        self.activityButton.hidden = YES;
    }

    [self applyOnStateTint:isOn];
}

- (void)switchToggled:(UISwitch *)sender {
    [HAHaptics lightImpact];
    [self callService:sender.isOn ? @"turn_on" : @"turn_off" inDomain:@"remote"];
}

- (void)activityTapped {
    NSArray *activities = self.entity.attributes[@"activity_list"];
    if (![activities isKindOfClass:[NSArray class]] || activities.count == 0) return;

    NSString *current = self.entity.attributes[@"current_activity"];
    [self presentOptionsWithTitle:nil options:activities current:current sourceView:self.activityButton
                          handler:^(NSString *selected) {
        [HAHaptics lightImpact];
        [self callService:@"turn_on" inDomain:@"remote" withData:@{@"activity": selected}];
    }];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.toggleSwitch.on = NO;
    self.activityButton.hidden = YES;
}

@end
