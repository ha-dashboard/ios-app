#import "HAAutoLayout.h"
#import "HAStackView.h"
#import "HAButtonRowFeatureView.h"
#import "HAEntity.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "HAEntityDisplayHelper.h"
#import "HAIconMapper.h"

@interface HAButtonRowFeatureView ()
@property (nonatomic, strong) HAStackView *buttonStack;
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
@property (nonatomic, strong) UISwitch *toggleSwitch;  // For "toggle" feature type
@property (nonatomic, strong) UILabel *tempValueLabel;  // For "target-temperature" display
@end

@implementation HAButtonRowFeatureView

+ (CGFloat)preferredHeight {
    return 36.0;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.buttonStack = [[HAStackView alloc] init];
    self.buttonStack.axis = 0;
    self.buttonStack.distribution = 1;
    self.buttonStack.spacing = 8;
    self.buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.buttonStack];

    if (HAAutoLayoutAvailable()) {
        NSLayoutConstraint *heightConstraint = [self.heightAnchor constraintEqualToConstant:[HAButtonRowFeatureView preferredHeight]];
        heightConstraint.priority = UILayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[
            [self.buttonStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [self.buttonStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [self.buttonStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.buttonStack.heightAnchor constraintEqualToConstant:32],
            heightConstraint,
        ]];
    }
}

- (void)configureWithEntity:(HAEntity *)entity featureConfig:(NSDictionary *)config {
    [super configureWithEntity:entity featureConfig:config];

    // Clear existing buttons
    for (UIView *v in self.buttonStack.arrangedSubviews) {
        [self.buttonStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    self.toggleSwitch = nil;
    self.tempValueLabel = nil;

    NSString *type = config[@"type"];
    BOOL available = entity.isAvailable;

    if ([type isEqualToString:@"cover-open-close"]) {
        [self setupCoverButtonsForEntity:entity available:available];
    } else if ([type isEqualToString:@"lock-commands"]) {
        [self setupLockButtonsForEntity:entity available:available];
    } else if ([type isEqualToString:@"toggle"]) {
        [self setupToggleForEntity:entity available:available];
    } else if ([type isEqualToString:@"vacuum-commands"]) {
        [self setupVacuumButtonsForConfig:config entity:entity available:available];
    } else if ([type isEqualToString:@"counter-actions"]) {
        [self setupCounterButtonsForConfig:config entity:entity available:available];
    } else if ([type isEqualToString:@"target-temperature"]) {
        [self setupTargetTemperatureForEntity:entity available:available];
    }

    self.alpha = available ? 1.0 : 0.4;
}

#pragma mark - Cover Open/Close/Stop

- (void)setupCoverButtonsForEntity:(HAEntity *)entity available:(BOOL)available {
    NSString *state = entity.state;
    BOOL isOpen = [state isEqualToString:@"open"] || [state isEqualToString:@"opening"];
    BOOL isClosed = [state isEqualToString:@"closed"] || [state isEqualToString:@"closing"];

    UIButton *openBtn = [self makeButtonWithTitle:@"\u25B2" tag:0]; // ▲
    UIButton *stopBtn = [self makeButtonWithTitle:@"\u25A0" tag:1]; // ■
    UIButton *closeBtn = [self makeButtonWithTitle:@"\u25BC" tag:2]; // ▼

    // Highlight active state
    UIColor *activeColor = [HAEntityDisplayHelper iconColorForEntity:entity];
    if (isOpen) [openBtn setTitleColor:activeColor forState:UIControlStateNormal];
    if (isClosed) [closeBtn setTitleColor:activeColor forState:UIControlStateNormal];

    openBtn.enabled = available && !isOpen;
    stopBtn.enabled = available;
    closeBtn.enabled = available && !isClosed;

    [self.buttonStack addArrangedSubview:openBtn];
    [self.buttonStack addArrangedSubview:stopBtn];
    [self.buttonStack addArrangedSubview:closeBtn];

    self.buttons = @[openBtn, stopBtn, closeBtn];
}

#pragma mark - Lock Commands

- (void)setupLockButtonsForEntity:(HAEntity *)entity available:(BOOL)available {
    BOOL isLocked = [entity.state isEqualToString:@"locked"];

    UIButton *lockBtn = [self makeButtonWithTitle:@"Lock" tag:10];
    UIButton *unlockBtn = [self makeButtonWithTitle:@"Unlock" tag:11];

    UIColor *activeColor = [HAEntityDisplayHelper iconColorForEntity:entity];
    if (isLocked) {
        [lockBtn setTitleColor:activeColor forState:UIControlStateNormal];
    } else {
        [unlockBtn setTitleColor:activeColor forState:UIControlStateNormal];
    }

    lockBtn.enabled = available;
    unlockBtn.enabled = available;

    [self.buttonStack addArrangedSubview:lockBtn];
    [self.buttonStack addArrangedSubview:unlockBtn];

    self.buttons = @[lockBtn, unlockBtn];
}

#pragma mark - Toggle (UISwitch)

- (void)setupToggleForEntity:(HAEntity *)entity available:(BOOL)available {
    self.toggleSwitch = [[UISwitch alloc] init];
    self.toggleSwitch.on = [entity isOn];
    self.toggleSwitch.enabled = available;
    self.toggleSwitch.onTintColor = [HAEntityDisplayHelper iconColorForEntity:entity];
    [self.toggleSwitch addTarget:self action:@selector(toggleSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    // Center the switch in the stack
    UIView *leftSpacer = [[UIView alloc] init];
    UIView *rightSpacer = [[UIView alloc] init];
    [self.buttonStack addArrangedSubview:leftSpacer];
    [self.buttonStack addArrangedSubview:self.toggleSwitch];
    [self.buttonStack addArrangedSubview:rightSpacer];
    self.buttonStack.distribution = 4;
}

#pragma mark - Vacuum Commands

- (void)setupVacuumButtonsForConfig:(NSDictionary *)config entity:(HAEntity *)entity available:(BOOL)available {
    NSArray *commands = config[@"commands"];
    if (![commands isKindOfClass:[NSArray class]] || commands.count == 0) {
        commands = @[@"start_pause", @"stop", @"return_home"];
    }

    NSMutableArray *btns = [NSMutableArray arrayWithCapacity:commands.count];
    for (NSUInteger i = 0; i < commands.count; i++) {
        NSString *cmd = commands[i];
        NSString *title = [[cmd stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString];
        UIButton *btn = [self makeButtonWithTitle:title tag:20 + (NSInteger)i];
        btn.enabled = available;
        [self.buttonStack addArrangedSubview:btn];
        [btns addObject:btn];
    }
    self.buttons = [btns copy];
}

#pragma mark - Counter Actions

- (void)setupCounterButtonsForConfig:(NSDictionary *)config entity:(HAEntity *)entity available:(BOOL)available {
    NSArray *actions = config[@"actions"];
    if (![actions isKindOfClass:[NSArray class]] || actions.count == 0) {
        actions = @[@"increment", @"decrement", @"reset"];
    }

    NSMutableArray *btns = [NSMutableArray arrayWithCapacity:actions.count];
    for (NSUInteger i = 0; i < actions.count; i++) {
        NSString *action = actions[i];
        NSString *title;
        if ([action isEqualToString:@"increment"]) title = @"+";
        else if ([action isEqualToString:@"decrement"]) title = @"\u2212"; // −
        else title = [[action capitalizedString] substringToIndex:MIN(action.length, (NSUInteger)5)];

        UIButton *btn = [self makeButtonWithTitle:title tag:30 + (NSInteger)i];
        btn.enabled = available;
        [self.buttonStack addArrangedSubview:btn];
        [btns addObject:btn];
    }
    self.buttons = [btns copy];
}

#pragma mark - Target Temperature

- (void)setupTargetTemperatureForEntity:(HAEntity *)entity available:(BOOL)available {
    // Use fill distribution so the value label stretches and buttons stay compact
    self.buttonStack.distribution = 0;

    UIButton *minusBtn = [self makeButtonWithTitle:@"\u2212" tag:40]; // −
    minusBtn.enabled = available;
    if (HAAutoLayoutAvailable()) {
        [minusBtn.widthAnchor constraintEqualToConstant:44].active = YES;
    }
    [minusBtn setContentHuggingPriority:UILayoutPriorityRequired forAxis:0];

    self.tempValueLabel = [[UILabel alloc] init];
    self.tempValueLabel.textAlignment = NSTextAlignmentCenter;
    self.tempValueLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.tempValueLabel.textColor = [HATheme primaryTextColor];
    NSNumber *target = [entity targetTemperature];
    NSString *unit = [entity weatherTemperatureUnit] ?: @"\u00B0C";
    self.tempValueLabel.text = target
        ? [NSString stringWithFormat:@"%@%@", target, unit]
        : @"--";
    if (HAAutoLayoutAvailable()) {
        [self.tempValueLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:0];
    }

    UIButton *plusBtn = [self makeButtonWithTitle:@"+" tag:41];
    plusBtn.enabled = available;
    if (HAAutoLayoutAvailable()) {
        [plusBtn.widthAnchor constraintEqualToConstant:44].active = YES;
    }
    [plusBtn setContentHuggingPriority:UILayoutPriorityRequired forAxis:0];

    [self.buttonStack addArrangedSubview:minusBtn];
    [self.buttonStack addArrangedSubview:self.tempValueLabel];
    [self.buttonStack addArrangedSubview:plusBtn];

    self.buttons = @[minusBtn, plusBtn];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat h = [HAButtonRowFeatureView preferredHeight];
        CGFloat selfW = self.bounds.size.width;
        self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, selfW, h);
        self.buttonStack.frame = CGRectMake(12, (h - 32) / 2, selfW - 24, 32);
    }
}

#pragma mark - Button Factory

- (UIButton *)makeButtonWithTitle:(NSString *)title tag:(NSInteger)tag {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [btn setTitleColor:[HATheme primaryTextColor] forState:UIControlStateNormal];
    [btn setTitleColor:[HATheme secondaryTextColor] forState:UIControlStateDisabled];
    btn.backgroundColor = [HATheme cellBackgroundColor];
    btn.layer.cornerRadius = 8;
    btn.layer.masksToBounds = YES;
    btn.tag = tag;
    [btn addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

#pragma mark - Actions

- (void)buttonTapped:(UIButton *)sender {
    [HAHaptics lightImpact];
    NSString *entityId = self.entity.entityId;
    if (!entityId || !self.serviceCallBlock) return;

    NSString *type = self.featureType;
    NSString *service = nil;
    NSString *domain = nil;
    NSDictionary *data = @{@"entity_id": entityId};

    if ([type isEqualToString:@"cover-open-close"]) {
        domain = @"cover";
        if (sender.tag == 0) service = @"open_cover";
        else if (sender.tag == 1) service = @"stop_cover";
        else if (sender.tag == 2) service = @"close_cover";
    } else if ([type isEqualToString:@"lock-commands"]) {
        domain = @"lock";
        service = (sender.tag == 10) ? @"lock" : @"unlock";
    } else if ([type isEqualToString:@"vacuum-commands"]) {
        domain = @"vacuum";
        NSArray *commands = self.featureConfig[@"commands"];
        if (![commands isKindOfClass:[NSArray class]]) commands = @[@"start_pause", @"stop", @"return_home"];
        NSUInteger idx = (NSUInteger)(sender.tag - 20);
        if (idx < commands.count) {
            NSString *cmd = commands[idx];
            // Map command names to HA services
            if ([cmd isEqualToString:@"start_pause"]) service = @"start";
            else if ([cmd isEqualToString:@"return_home"]) service = @"return_to_base";
            else if ([cmd isEqualToString:@"clean_spot"]) service = @"clean_spot";
            else if ([cmd isEqualToString:@"locate"]) service = @"locate";
            else service = cmd;
        }
    } else if ([type isEqualToString:@"counter-actions"]) {
        domain = @"counter";
        NSArray *actions = self.featureConfig[@"actions"];
        if (![actions isKindOfClass:[NSArray class]]) actions = @[@"increment", @"decrement", @"reset"];
        NSUInteger idx = (NSUInteger)(sender.tag - 30);
        if (idx < actions.count) {
            service = actions[idx];
        }
    } else if ([type isEqualToString:@"target-temperature"]) {
        domain = @"climate";
        service = @"set_temperature";
        NSNumber *current = [self.entity targetTemperature];
        CGFloat step = 0.5;
        NSNumber *attrStep = self.entity.attributes[@"target_temp_step"];
        if (attrStep) step = [attrStep floatValue];
        CGFloat newTemp = current ? [current floatValue] : 20.0;
        if (sender.tag == 40) newTemp -= step;
        else if (sender.tag == 41) newTemp += step;
        data = @{@"entity_id": entityId, @"temperature": @(newTemp)};
    }

    if (service && domain) {
        self.serviceCallBlock(service, domain, data);
    }
}

- (void)toggleSwitchChanged:(UISwitch *)sender {
    [HAHaptics lightImpact];
    NSString *entityId = self.entity.entityId;
    if (!entityId || !self.serviceCallBlock) return;
    self.serviceCallBlock(@"toggle", @"homeassistant", @{@"entity_id": entityId});
}

@end
