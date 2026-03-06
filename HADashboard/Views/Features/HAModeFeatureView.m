#import "HAModeFeatureView.h"
#import "HAEntity.h"
#import "HAEntity+Climate.h"
#import "HAEntityAttributes.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "HAEntityDisplayHelper.h"
#import "HAIconMapper.h"
#import "UIView+HAUtilities.h"

@interface HAModeFeatureView ()
@property (nonatomic, strong) UIScrollView *scrollView;       // For icons style
@property (nonatomic, strong) UIStackView *modeStack;         // For icons style
@property (nonatomic, strong) UIButton *dropdownButton;       // For dropdown style
@property (nonatomic, strong) NSArray<NSString *> *modes;     // Available mode values
@property (nonatomic, copy) NSString *currentMode;            // Currently active mode
@property (nonatomic, assign) BOOL isDropdownStyle;
@end

@implementation HAModeFeatureView

+ (CGFloat)preferredHeight {
    return 36.0;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSLayoutConstraint *heightConstraint = [self.heightAnchor constraintEqualToConstant:[HAModeFeatureView preferredHeight]];
        heightConstraint.priority = UILayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[heightConstraint]];
    }
    return self;
}

- (void)configureWithEntity:(HAEntity *)entity featureConfig:(NSDictionary *)config {
    [super configureWithEntity:entity featureConfig:config];

    // Remove previous UI
    [self.scrollView removeFromSuperview];
    self.scrollView = nil;
    self.modeStack = nil;
    [self.dropdownButton removeFromSuperview];
    self.dropdownButton = nil;

    NSString *type = config[@"type"];
    NSString *style = config[@"style"];
    self.isDropdownStyle = [style isEqualToString:@"dropdown"];

    // Resolve modes and current mode from entity
    [self resolveModes:config entity:entity type:type];

    if (self.modes.count == 0) {
        self.hidden = YES;
        return;
    }
    self.hidden = NO;

    BOOL available = entity.isAvailable;
    self.alpha = available ? 1.0 : 0.4;

    if (self.isDropdownStyle) {
        [self setupDropdownForAvailable:available];
    } else {
        [self setupIconButtonsForAvailable:available entity:entity];
    }
}

#pragma mark - Mode Resolution

- (void)resolveModes:(NSDictionary *)config entity:(HAEntity *)entity type:(NSString *)type {
    if ([type isEqualToString:@"climate-hvac-modes"]) {
        // Config can restrict which modes to show
        NSArray *configModes = config[@"hvac_modes"];
        if ([configModes isKindOfClass:[NSArray class]] && configModes.count > 0) {
            self.modes = configModes;
        } else {
            self.modes = [entity hvacModes];
        }
        self.currentMode = entity.state; // climate entity state IS the hvac mode
    } else if ([type isEqualToString:@"climate-preset-modes"]) {
        NSArray *configModes = config[@"preset_modes"];
        if ([configModes isKindOfClass:[NSArray class]] && configModes.count > 0) {
            self.modes = configModes;
        } else {
            self.modes = entity.attributes[HAAttrPresetModes];
        }
        self.currentMode = entity.attributes[HAAttrPresetMode];
    } else if ([type isEqualToString:@"climate-fan-modes"]) {
        NSArray *configModes = config[@"fan_modes"];
        if ([configModes isKindOfClass:[NSArray class]] && configModes.count > 0) {
            self.modes = configModes;
        } else {
            self.modes = [entity climateFanModes];
        }
        self.currentMode = entity.attributes[HAAttrFanMode];
    } else if ([type isEqualToString:@"alarm-modes"]) {
        // Alarm modes are fixed set
        self.modes = @[@"armed_home", @"armed_away", @"armed_night", @"armed_vacation", @"disarmed"];
        self.currentMode = entity.state;
    }

    if (![self.modes isKindOfClass:[NSArray class]]) self.modes = @[];
}

#pragma mark - Icons Style (Pill Buttons)

- (void)setupIconButtonsForAvailable:(BOOL)available entity:(HAEntity *)entity {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self addSubview:self.scrollView];

    self.modeStack = [[UIStackView alloc] init];
    self.modeStack.axis = UILayoutConstraintAxisHorizontal;
    self.modeStack.spacing = 6;
    self.modeStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.modeStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [self.scrollView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.scrollView.heightAnchor constraintEqualToConstant:30],
        [self.modeStack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.modeStack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.modeStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.modeStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.modeStack.heightAnchor constraintEqualToAnchor:self.scrollView.heightAnchor],
    ]];

    UIColor *activeColor = [HAEntityDisplayHelper iconColorForEntity:entity];

    for (NSUInteger i = 0; i < self.modes.count; i++) {
        NSString *mode = self.modes[i];
        BOOL isActive = [mode isEqualToString:self.currentMode];

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.tag = (NSInteger)i;

        // Try to get an icon for this mode, fall back to text
        NSString *iconGlyph = [self iconGlyphForMode:mode type:self.featureType];
        if (iconGlyph) {
            [btn setTitle:iconGlyph forState:UIControlStateNormal];
            btn.titleLabel.font = [HAIconMapper mdiFontOfSize:16];
        } else {
            NSString *displayName = [self displayNameForMode:mode];
            [btn setTitle:displayName forState:UIControlStateNormal];
            btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        }

        if (isActive) {
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            btn.backgroundColor = activeColor;
        } else {
            [btn setTitleColor:[HATheme primaryTextColor] forState:UIControlStateNormal];
            btn.backgroundColor = [HATheme cellBackgroundColor];
        }

        btn.layer.cornerRadius = 15;
        btn.layer.masksToBounds = YES;
        btn.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
        btn.enabled = available;
        [btn addTarget:self action:@selector(modeTapped:) forControlEvents:UIControlEventTouchUpInside];

        [self.modeStack addArrangedSubview:btn];
    }
}

#pragma mark - Dropdown Style

- (void)setupDropdownForAvailable:(BOOL)available {
    self.dropdownButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.dropdownButton.translatesAutoresizingMaskIntoConstraints = NO;
    NSString *displayName = self.currentMode ? [self displayNameForMode:self.currentMode] : @"Select";
    [self.dropdownButton setTitle:[NSString stringWithFormat:@"%@ \u25BE", displayName] forState:UIControlStateNormal]; // ▾
    self.dropdownButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.dropdownButton setTitleColor:[HATheme primaryTextColor] forState:UIControlStateNormal];
    self.dropdownButton.backgroundColor = [HATheme cellBackgroundColor];
    self.dropdownButton.layer.cornerRadius = 8;
    self.dropdownButton.layer.masksToBounds = YES;
    self.dropdownButton.contentEdgeInsets = UIEdgeInsetsMake(6, 16, 6, 16);
    self.dropdownButton.enabled = available;
    [self.dropdownButton addTarget:self action:@selector(dropdownTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.dropdownButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.dropdownButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.dropdownButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.dropdownButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:12],
        [self.dropdownButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-12],
    ]];
}

#pragma mark - Actions

- (void)modeTapped:(UIButton *)sender {
    [HAHaptics lightImpact];
    NSUInteger idx = (NSUInteger)sender.tag;
    if (idx >= self.modes.count) return;
    NSString *selectedMode = self.modes[idx];
    [self callServiceForMode:selectedMode];
}

- (void)dropdownTapped:(UIButton *)sender {
    UIViewController *vc = [self ha_parentViewController];
    if (!vc) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self; // Fix #2: prevent retain cycle
    for (NSString *mode in self.modes) {
        NSString *displayName = [self displayNameForMode:mode];
        BOOL isActive = [mode isEqualToString:self.currentMode];
        // Fix #6: use checkmark emoji instead of private setValue:@"checked"
        NSString *title = isActive ? [NSString stringWithFormat:@"\u2713 %@", displayName] : displayName;
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *a) {
            [HAHaptics lightImpact];
            [weakSelf callServiceForMode:mode];
        }];
        [sheet addAction:action];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    // iPad popover anchor
    sheet.popoverPresentationController.sourceView = sender;
    sheet.popoverPresentationController.sourceRect = sender.bounds;

    [vc presentViewController:sheet animated:YES completion:nil];
}

- (void)callServiceForMode:(NSString *)mode {
    NSString *entityId = self.entity.entityId;
    if (!entityId || !self.serviceCallBlock) return;

    NSString *type = self.featureType;
    NSString *service = nil;
    NSString *domain = nil;
    NSDictionary *data = nil;

    if ([type isEqualToString:@"climate-hvac-modes"]) {
        domain = @"climate";
        service = @"set_hvac_mode";
        data = @{@"entity_id": entityId, @"hvac_mode": mode};
    } else if ([type isEqualToString:@"climate-preset-modes"]) {
        domain = @"climate";
        service = @"set_preset_mode";
        data = @{@"entity_id": entityId, @"preset_mode": mode};
    } else if ([type isEqualToString:@"climate-fan-modes"]) {
        domain = @"climate";
        service = @"set_fan_mode";
        data = @{@"entity_id": entityId, @"fan_mode": mode};
    } else if ([type isEqualToString:@"alarm-modes"]) {
        domain = @"alarm_control_panel";
        if ([mode isEqualToString:@"disarmed"]) {
            service = @"alarm_disarm";
        } else if ([mode isEqualToString:@"armed_home"]) {
            service = @"alarm_arm_home";
        } else if ([mode isEqualToString:@"armed_away"]) {
            service = @"alarm_arm_away";
        } else if ([mode isEqualToString:@"armed_night"]) {
            service = @"alarm_arm_night";
        } else if ([mode isEqualToString:@"armed_vacation"]) {
            service = @"alarm_arm_vacation";
        }
        data = @{@"entity_id": entityId};
    }

    if (service && domain && data) {
        self.serviceCallBlock(service, domain, data);
    }
}

#pragma mark - Display Helpers

- (NSString *)displayNameForMode:(NSString *)mode {
    // "heat_cool" → "Heat/Cool", "armed_home" → "Armed Home"
    NSString *formatted = [mode stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    return [formatted capitalizedString];
}

- (NSString *)iconGlyphForMode:(NSString *)mode type:(NSString *)featureType {
    // HVAC mode icons (match HA web frontend)
    if ([featureType isEqualToString:@"climate-hvac-modes"]) {
        if ([mode isEqualToString:@"heat"])       return [HAIconMapper glyphForIconName:@"fire"];
        if ([mode isEqualToString:@"cool"])       return [HAIconMapper glyphForIconName:@"snowflake"];
        if ([mode isEqualToString:@"heat_cool"])  return [HAIconMapper glyphForIconName:@"sun-snowflake-variant"];
        if ([mode isEqualToString:@"auto"])       return [HAIconMapper glyphForIconName:@"thermostat-auto"];
        if ([mode isEqualToString:@"dry"])        return [HAIconMapper glyphForIconName:@"water-percent"];
        if ([mode isEqualToString:@"fan_only"])   return [HAIconMapper glyphForIconName:@"fan"];
        if ([mode isEqualToString:@"off"])        return [HAIconMapper glyphForIconName:@"power"];
    }
    // Alarm mode icons
    if ([featureType isEqualToString:@"alarm-modes"]) {
        if ([mode isEqualToString:@"armed_home"])     return [HAIconMapper glyphForIconName:@"shield-home"];
        if ([mode isEqualToString:@"armed_away"])     return [HAIconMapper glyphForIconName:@"shield-lock"];
        if ([mode isEqualToString:@"armed_night"])    return [HAIconMapper glyphForIconName:@"shield-moon"];
        if ([mode isEqualToString:@"armed_vacation"]) return [HAIconMapper glyphForIconName:@"shield-airplane"];
        if ([mode isEqualToString:@"disarmed"])       return [HAIconMapper glyphForIconName:@"shield-off"];
    }
    // Fan mode and preset mode — no standard icons, use text labels
    return nil;
}

@end
