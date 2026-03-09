#import "HAAutoLayout.h"
#import "HAStackView.h"
#import "HAAlarmEntityCell.h"
#import "HAEntity.h"
#import "HAEntityAttributes.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"

static const CGFloat kPadding = 10.0;
static const CGFloat kActionButtonWidth = 70.0;
static const CGFloat kActionButtonHeight = 28.0;
static const CGFloat kActionButtonSpacing = 4.0;
static const CGFloat kKeypadButtonSize = 44.0;
static const CGFloat kKeypadButtonSpacing = 8.0;
static const CGFloat kCodeFieldHeight = 36.0;

// Tags for keypad digit buttons (tag = digit value, 10 = clear, 11 = enter)
static const NSInteger kKeypadTagClear = 10;
static const NSInteger kKeypadTagEnter = 11;

@interface HAAlarmEntityCell () <UITextFieldDelegate>
@property (nonatomic, strong) UILabel *alarmStateLabel;
@property (nonatomic, strong) UIButton *armAwayButton;
@property (nonatomic, strong) UIButton *armHomeButton;
@property (nonatomic, strong) UIButton *armNightButton;
@property (nonatomic, strong) UIButton *armVacationButton;
@property (nonatomic, strong) UIButton *armBypassButton;
@property (nonatomic, strong) UIButton *disarmButton;
@property (nonatomic, strong) UITextField *codeTextField;
@property (nonatomic, strong) UIView *keypadContainer;
@property (nonatomic, strong) NSMutableArray<UIButton *> *keypadButtons;
@property (nonatomic, copy) NSString *pendingService;
@property (nonatomic, assign) BOOL keypadVisible;
@end

@implementation HAAlarmEntityCell

#pragma mark - Height Calculations

+ (CGFloat)preferredHeightWithoutKeypad {
    // nameLabel (padding + ~16) + alarmState (~20 + 4 gap) + action buttons (28) + padding top/bottom
    return 100.0;
}

+ (CGFloat)preferredHeightWithKeypad {
    // Base layout: name + state + action buttons row = ~70pt from top
    // Then: gap(8) + code field(36) + gap(8) + 4 rows of keypad buttons (4*44 + 3*8) + padding(10)
    CGFloat baseTop = 70.0; // name + state + buttons
    CGFloat codeSection = 8.0 + kCodeFieldHeight; // gap + text field
    CGFloat keypadRows = 4.0 * kKeypadButtonSize + 3.0 * kKeypadButtonSpacing; // 4 rows
    CGFloat bottomPad = kPadding;
    return baseTop + codeSection + 8.0 + keypadRows + bottomPad;
}

#pragma mark - Setup

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;
    self.keypadButtons = [NSMutableArray array];

    // Alarm state badge (pill-shaped label with tinted background)
    self.alarmStateLabel = [[UILabel alloc] init];
    self.alarmStateLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.alarmStateLabel.textColor = [UIColor whiteColor];
    self.alarmStateLabel.textAlignment = NSTextAlignmentCenter;
    self.alarmStateLabel.layer.cornerRadius = 12;
    self.alarmStateLabel.layer.masksToBounds = YES;
    self.alarmStateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.alarmStateLabel];

    // Action buttons: Disarm / Home / Away
    self.armAwayButton = [self createActionButtonWithTitle:@"Away"
                                                    color:[HATheme destructiveColor]
                                                   action:@selector(armAwayTapped)];
    self.armHomeButton = [self createActionButtonWithTitle:@"Home"
                                                    color:[HATheme warningColor]
                                                   action:@selector(armHomeTapped)];
    self.armNightButton = [self createActionButtonWithTitle:@"Night"
                                                      color:[HATheme destructiveColor]
                                                     action:@selector(armNightTapped)];
    self.armVacationButton = [self createActionButtonWithTitle:@"Vacation"
                                                        color:[HATheme destructiveColor]
                                                       action:@selector(armVacationTapped)];
    self.armBypassButton = [self createActionButtonWithTitle:@"Bypass"
                                                      color:[HATheme warningColor]
                                                     action:@selector(armBypassTapped)];
    self.disarmButton = [self createActionButtonWithTitle:@"Disarm"
                                                   color:[HATheme successColor]
                                                  action:@selector(disarmTapped)];

    // Code text field (secure entry, monospaced, centered)
    self.codeTextField = [[UITextField alloc] init];
    self.codeTextField.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightMedium];
    self.codeTextField.textColor = [HATheme primaryTextColor];
    self.codeTextField.textAlignment = NSTextAlignmentCenter;
    self.codeTextField.secureTextEntry = YES;
    self.codeTextField.placeholder = @"Code";
    self.codeTextField.backgroundColor = [HATheme controlBackgroundColor];
    self.codeTextField.layer.cornerRadius = 8.0;
    self.codeTextField.layer.borderWidth = 1.0;
    self.codeTextField.layer.borderColor = [HATheme controlBorderColor].CGColor;
    self.codeTextField.translatesAutoresizingMaskIntoConstraints = NO;
    self.codeTextField.delegate = self;
    // Prevent system keyboard from appearing; we use the keypad
    self.codeTextField.inputView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.contentView addSubview:self.codeTextField];

    // Keypad container
    self.keypadContainer = [[UIView alloc] init];
    self.keypadContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.keypadContainer];

    [self buildKeypad];
    [self setupConstraints];

    // Initially hidden until configureWithEntity determines visibility
    self.codeTextField.hidden = YES;
    self.keypadContainer.hidden = YES;
}

- (UIButton *)createActionButtonWithTitle:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    // Pill-shaped with tinted background instead of solid color blocks
    button.backgroundColor = [color colorWithAlphaComponent:0.15];
    [button setTitleColor:color forState:UIControlStateNormal];
    button.layer.cornerRadius = kActionButtonHeight / 2.0; // pill shape
    button.layer.masksToBounds = YES;
    button.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:button];
    return button;
}

- (void)buildKeypad {
    // 4x3 grid: [1][2][3] / [4][5][6] / [7][8][9] / [Clear][0][Enter]
    NSArray *rows = @[
        @[@"1", @"2", @"3"],
        @[@"4", @"5", @"6"],
        @[@"7", @"8", @"9"],
        @[@"\u2715", @"0", @"\u2713"],  // multiply-x for clear, checkmark for enter
    ];

    CGFloat totalWidth = 3.0 * kKeypadButtonSize + 2.0 * kKeypadButtonSpacing;
    CGFloat totalHeight = 4.0 * kKeypadButtonSize + 3.0 * kKeypadButtonSpacing;

    // Size the container
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.keypadContainer.widthAnchor constraintEqualToConstant:totalWidth],
            [self.keypadContainer.heightAnchor constraintEqualToConstant:totalHeight],
        ]];
    }

    for (NSInteger row = 0; row < 4; row++) {
        for (NSInteger col = 0; col < 3; col++) {
            NSString *label = rows[row][col];
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
            [btn setTitle:label forState:UIControlStateNormal];
            btn.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightMedium];
            btn.translatesAutoresizingMaskIntoConstraints = NO;
            btn.layer.cornerRadius = kKeypadButtonSize / 2.0;
            btn.clipsToBounds = YES;

            // Determine tag and styling
            if (row == 3 && col == 0) {
                // Clear button
                btn.tag = kKeypadTagClear;
                btn.backgroundColor = [HATheme controlBackgroundColor];
                [btn setTitleColor:[HATheme destructiveColor] forState:UIControlStateNormal];
                btn.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
            } else if (row == 3 && col == 2) {
                // Enter button
                btn.tag = kKeypadTagEnter;
                btn.backgroundColor = [HATheme accentColor];
                [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                btn.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
            } else {
                // Digit button
                btn.tag = [label integerValue];
                btn.backgroundColor = [HATheme controlBackgroundColor];
                [btn setTitleColor:[HATheme primaryTextColor] forState:UIControlStateNormal];
            }

            [btn addTarget:self action:@selector(keypadButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.keypadContainer addSubview:btn];
            [self.keypadButtons addObject:btn];

            CGFloat x = col * (kKeypadButtonSize + kKeypadButtonSpacing);
            CGFloat y = row * (kKeypadButtonSize + kKeypadButtonSpacing);

            if (HAAutoLayoutAvailable()) {
                [NSLayoutConstraint activateConstraints:@[
                    [btn.leadingAnchor constraintEqualToAnchor:self.keypadContainer.leadingAnchor constant:x],
                    [btn.topAnchor constraintEqualToAnchor:self.keypadContainer.topAnchor constant:y],
                    [btn.widthAnchor constraintEqualToConstant:kKeypadButtonSize],
                    [btn.heightAnchor constraintEqualToConstant:kKeypadButtonSize],
                ]];
            }
        }
    }
}

- (void)setupConstraints {
    UIView *cv = self.contentView;

    // Alarm state badge: below name, left-aligned pill
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.alarmStateLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:kPadding],
            [self.alarmStateLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:4],
            [self.alarmStateLabel.heightAnchor constraintEqualToConstant:24],
        ]];
    }

    // Action buttons: UIStackView row below alarm state
    HAStackView *buttonStack = [[HAStackView alloc] initWithArrangedSubviews:@[
        self.armAwayButton, self.armHomeButton, self.armNightButton,
        self.armVacationButton, self.armBypassButton, self.disarmButton
    ]];
    buttonStack.axis = 0;
    buttonStack.spacing = kActionButtonSpacing;
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:buttonStack];

    for (UIButton *btn in buttonStack.arrangedSubviews) {
        if (HAAutoLayoutAvailable()) {
            [btn.heightAnchor constraintEqualToConstant:kActionButtonHeight].active = YES;
        }
    }

    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [buttonStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:cv.leadingAnchor constant:kPadding],
            [buttonStack.trailingAnchor constraintLessThanOrEqualToAnchor:cv.trailingAnchor constant:-kPadding],
            [buttonStack.topAnchor constraintEqualToAnchor:self.alarmStateLabel.bottomAnchor constant:8],
            [buttonStack.centerXAnchor constraintEqualToAnchor:cv.centerXAnchor],
        ]];
    }

    // Night, Vacation, Bypass hidden by default — shown based on supported_features
    self.armNightButton.hidden = YES;
    self.armVacationButton.hidden = YES;
    self.armBypassButton.hidden = YES;

    // Code text field: centered below buttons
    CGFloat codeFieldWidth = 3.0 * kKeypadButtonSize + 2.0 * kKeypadButtonSpacing;
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.codeTextField.centerXAnchor constraintEqualToAnchor:cv.centerXAnchor],
            [self.codeTextField.topAnchor constraintEqualToAnchor:buttonStack.bottomAnchor constant:8],
            [self.codeTextField.widthAnchor constraintEqualToConstant:codeFieldWidth],
            [self.codeTextField.heightAnchor constraintEqualToConstant:kCodeFieldHeight],
        ]];
    }

    // Keypad container: centered below code field
    if (HAAutoLayoutAvailable()) {
        [NSLayoutConstraint activateConstraints:@[
            [self.keypadContainer.centerXAnchor constraintEqualToAnchor:cv.centerXAnchor],
            [self.keypadContainer.topAnchor constraintEqualToAnchor:self.codeTextField.bottomAnchor constant:8],
        ]];
    }
}

#pragma mark - Configuration

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    NSString *state = [entity alarmState];
    BOOL isArmed = [state hasPrefix:@"armed"];
    BOOL isDisarmed = [state isEqualToString:@"disarmed"];
    BOOL isTriggered = [state isEqualToString:@"triggered"];

    // State badge: shield icon + state text with colored background
    NSString *stateText = [self displayStringForState:state];
    self.alarmStateLabel.text = [NSString stringWithFormat:@"  %@  ", stateText]; // padding for pill
    if (isArmed) {
        self.alarmStateLabel.backgroundColor = [HATheme successColor];
    } else if (isTriggered) {
        self.alarmStateLabel.backgroundColor = [HATheme destructiveColor];
    } else if (isDisarmed) {
        self.alarmStateLabel.backgroundColor = [[HATheme secondaryTextColor] colorWithAlphaComponent:0.3];
        self.alarmStateLabel.textColor = [HATheme primaryTextColor];
    } else {
        self.alarmStateLabel.backgroundColor = [HATheme warningColor];
    }

    BOOL available = entity.isAvailable;
    NSInteger features = HAAttrInteger(entity.attributes, HAAttrSupportedFeatures, 31);

    // Contextual buttons: when armed, only show Disarm. When disarmed, show arm options.
    if (isArmed || isTriggered) {
        // Armed or triggered: only show Disarm
        self.armAwayButton.hidden = YES;
        self.armHomeButton.hidden = YES;
        self.armNightButton.hidden = YES;
        self.armVacationButton.hidden = YES;
        self.armBypassButton.hidden = YES;
        self.disarmButton.hidden = NO;
        self.disarmButton.enabled = available;
    } else {
        // Disarmed/pending: show arm options based on supported_features
        self.disarmButton.hidden = YES;
        self.armHomeButton.hidden = !(features & 1);       // ARM_HOME
        self.armAwayButton.hidden = !(features & 2);        // ARM_AWAY
        self.armNightButton.hidden = !(features & 4);       // ARM_NIGHT
        self.armBypassButton.hidden = !(features & 16);     // ARM_CUSTOM_BYPASS
        self.armVacationButton.hidden = !(features & 32);   // ARM_VACATION
        self.armAwayButton.enabled = available;
        self.armHomeButton.enabled = available;
        self.armNightButton.enabled = available;
        self.armVacationButton.enabled = available;
        self.armBypassButton.enabled = available;
    }

    // Show keypad when code_arm_required is YES and code_format is set,
    // or when disarming (always needs code if code_format is set)
    BOOL codeArmRequired = HAAttrBool(entity.attributes, @"code_arm_required", YES);
    BOOL hasCodeFormat = ([entity alarmCodeFormat] != nil);
    BOOL showCode = hasCodeFormat && (codeArmRequired || isArmed) && entity.isAvailable;
    NSString *codeFormat = [entity alarmCodeFormat];
    BOOL isTextCode = showCode && codeFormat && ![codeFormat isEqualToString:@"number"];
    self.keypadVisible = showCode;
    self.codeTextField.hidden = !showCode;
    // Text code format: show system keyboard, hide custom numeric keypad
    // Number code format: hide system keyboard, show custom numeric keypad
    if (isTextCode) {
        self.codeTextField.inputView = nil; // allow system keyboard
        self.codeTextField.keyboardType = UIKeyboardTypeDefault;
        self.codeTextField.secureTextEntry = YES;
        self.keypadContainer.hidden = YES;
    } else {
        self.codeTextField.inputView = [[UIView alloc] initWithFrame:CGRectZero]; // suppress keyboard
        self.keypadContainer.hidden = !showCode;
    }
    self.codeTextField.text = @"";
    self.pendingService = nil;
}

- (NSString *)displayStringForState:(NSString *)state {
    if ([state isEqualToString:@"armed_away"]) return @"Armed Away";
    if ([state isEqualToString:@"armed_home"]) return @"Armed Home";
    if ([state isEqualToString:@"armed_night"]) return @"Armed Night";
    if ([state isEqualToString:@"armed_vacation"]) return @"Armed Vacation";
    if ([state isEqualToString:@"disarmed"]) return @"Disarmed";
    if ([state isEqualToString:@"pending"]) return @"Pending";
    if ([state isEqualToString:@"arming"]) return @"Arming";
    if ([state isEqualToString:@"triggered"]) return @"TRIGGERED";
    return state ?: @"Unknown";
}

#pragma mark - Keypad Actions

- (void)keypadButtonTapped:(UIButton *)sender {
    [HAHaptics lightImpact];

    if (sender.tag == kKeypadTagClear) {
        self.codeTextField.text = @"";
    } else if (sender.tag == kKeypadTagEnter) {
        [self submitCodeForService:self.pendingService ?: @"alarm_disarm"];
    } else {
        // Digit button
        NSString *digit = [NSString stringWithFormat:@"%ld", (long)sender.tag];
        self.codeTextField.text = [self.codeTextField.text stringByAppendingString:digit];
    }
}

- (void)submitCodeForService:(NSString *)service {
    if (!self.entity) return;

    NSString *code = self.codeTextField.text;
    NSDictionary *data = nil;
    if (code.length > 0) {
        data = @{@"code": code};
    }

    [[HAConnectionManager sharedManager] callService:service
                                            inDomain:HAEntityDomainAlarmControlPanel
                                            withData:data
                                            entityId:self.entity.entityId];

    // Clear the code field after submission
    self.codeTextField.text = @"";
    self.pendingService = nil;
}

#pragma mark - Action Button Handlers

- (void)armAwayTapped {
    if (!self.entity) return;
    [HAHaptics mediumImpact];

    if (self.keypadVisible) {
        // Set pending service — code is submitted when user presses Enter on keypad
        self.pendingService = @"alarm_arm_away";
    } else {
        [self callAlarmService:@"alarm_arm_away"];
    }
}

- (void)armHomeTapped {
    if (!self.entity) return;
    [HAHaptics mediumImpact];

    if (self.keypadVisible) {
        self.pendingService = @"alarm_arm_home";
    } else {
        [self callAlarmService:@"alarm_arm_home"];
    }
}

- (void)armNightTapped {
    if (!self.entity) return;
    [HAHaptics mediumImpact];

    if (self.keypadVisible) {
        self.pendingService = @"alarm_arm_night";
    } else {
        [self callAlarmService:@"alarm_arm_night"];
    }
}

- (void)armVacationTapped {
    if (!self.entity) return;
    [HAHaptics mediumImpact];

    if (self.keypadVisible) {
        self.pendingService = @"alarm_arm_vacation";
    } else {
        [self callAlarmService:@"alarm_arm_vacation"];
    }
}

- (void)armBypassTapped {
    if (!self.entity) return;
    [HAHaptics mediumImpact];

    if (self.keypadVisible) {
        self.pendingService = @"alarm_arm_custom_bypass";
    } else {
        [self callAlarmService:@"alarm_arm_custom_bypass"];
    }
}

- (void)disarmTapped {
    if (!self.entity) return;
    [HAHaptics heavyImpact];

    if (self.keypadVisible) {
        self.pendingService = @"alarm_disarm";
    } else {
        [self callAlarmService:@"alarm_disarm"];
    }
}

- (void)callAlarmService:(NSString *)service {
    [[HAConnectionManager sharedManager] callService:service
                                            inDomain:HAEntityDomainAlarmControlPanel
                                            withData:nil
                                            entityId:self.entity.entityId];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    // Allow editing when using system keyboard (text code format);
    // deny when using custom numeric keypad (inputView is set)
    return (textField.inputView == nil);
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    // Submit code on Return key (text code mode)
    [self submitCodeForService:self.pendingService ?: @"alarm_disarm"];
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat padding = kPadding;

        // alarmStateLabel: below nameLabel, left-aligned
        CGSize alarmSize = [self.alarmStateLabel sizeThatFits:CGSizeMake(w - padding * 2, CGFLOAT_MAX)];
        self.alarmStateLabel.frame = CGRectMake(padding, CGRectGetMaxY(self.nameLabel.frame) + 4, alarmSize.width + 4, 24);

        // Action buttons: row below alarm state, centered
        NSMutableArray *visibleBtns = [NSMutableArray array];
        for (UIButton *btn in @[self.armAwayButton, self.armHomeButton, self.armNightButton,
                                 self.armVacationButton, self.armBypassButton, self.disarmButton]) {
            if (!btn.hidden) [visibleBtns addObject:btn];
        }
        CGFloat btnY = CGRectGetMaxY(self.alarmStateLabel.frame) + 8;
        CGFloat totalBtnW = visibleBtns.count * kActionButtonWidth + MAX(0, (CGFloat)visibleBtns.count - 1) * kActionButtonSpacing;
        CGFloat btnX = (w - totalBtnW) / 2.0;
        for (UIButton *btn in visibleBtns) {
            btn.frame = CGRectMake(btnX, btnY, kActionButtonWidth, kActionButtonHeight);
            btnX += kActionButtonWidth + kActionButtonSpacing;
        }

        // Code text field: centered below buttons
        CGFloat codeFieldWidth = 3.0 * kKeypadButtonSize + 2.0 * kKeypadButtonSpacing;
        CGFloat codeY = btnY + kActionButtonHeight + 8;
        self.codeTextField.frame = CGRectMake((w - codeFieldWidth) / 2.0, codeY, codeFieldWidth, kCodeFieldHeight);

        // Keypad container: centered below code field
        CGFloat keypadW = 3.0 * kKeypadButtonSize + 2.0 * kKeypadButtonSpacing;
        CGFloat keypadH = 4.0 * kKeypadButtonSize + 3.0 * kKeypadButtonSpacing;
        CGFloat keypadY = CGRectGetMaxY(self.codeTextField.frame) + 8;
        self.keypadContainer.frame = CGRectMake((w - keypadW) / 2.0, keypadY, keypadW, keypadH);

        // Keypad buttons inside container
        NSInteger btnIdx = 0;
        for (NSInteger row = 0; row < 4; row++) {
            for (NSInteger col = 0; col < 3; col++) {
                if (btnIdx < (NSInteger)self.keypadButtons.count) {
                    CGFloat x = col * (kKeypadButtonSize + kKeypadButtonSpacing);
                    CGFloat y = row * (kKeypadButtonSize + kKeypadButtonSpacing);
                    self.keypadButtons[btnIdx].frame = CGRectMake(x, y, kKeypadButtonSize, kKeypadButtonSize);
                }
                btnIdx++;
            }
        }
    }
}

#pragma mark - Reuse

- (void)prepareForReuse {
    [super prepareForReuse];
    self.alarmStateLabel.text = nil;
    self.alarmStateLabel.textColor = [HATheme primaryTextColor];
    self.armAwayButton.backgroundColor = [HATheme destructiveColor];
    self.armHomeButton.backgroundColor = [HATheme warningColor];
    self.armNightButton.backgroundColor = [HATheme destructiveColor];
    self.armVacationButton.backgroundColor = [HATheme destructiveColor];
    self.armBypassButton.backgroundColor = [HATheme warningColor];
    self.disarmButton.backgroundColor = [HATheme successColor];
    self.armNightButton.hidden = YES;
    self.armVacationButton.hidden = YES;
    self.armBypassButton.hidden = YES;
    self.codeTextField.text = @"";
    self.codeTextField.layer.borderColor = [HATheme controlBorderColor].CGColor;
    self.codeTextField.backgroundColor = [HATheme controlBackgroundColor];
    self.pendingService = nil;
    self.keypadVisible = NO;
    self.codeTextField.hidden = YES;
    self.keypadContainer.hidden = YES;

    // Refresh keypad button colors for theme changes
    for (UIButton *btn in self.keypadButtons) {
        if (btn.tag == kKeypadTagClear) {
            btn.backgroundColor = [HATheme controlBackgroundColor];
            [btn setTitleColor:[HATheme destructiveColor] forState:UIControlStateNormal];
        } else if (btn.tag == kKeypadTagEnter) {
            btn.backgroundColor = [HATheme accentColor];
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            btn.backgroundColor = [HATheme controlBackgroundColor];
            [btn setTitleColor:[HATheme primaryTextColor] forState:UIControlStateNormal];
        }
    }
    self.codeTextField.textColor = [HATheme primaryTextColor];
}

@end
