#import "HAAutoLayout.h"
#import "NSString+HACompat.h"
#import "HAVacuumEntityCell.h"
#import "NSString+HACompat.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HAHaptics.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"
#import "UIView+HAUtilities.h"
#import "UIFont+HACompat.h"

static const CGFloat kIconCircleSize = 60.0;
static const CGFloat kIconFontSize   = 32.0;
static const CGFloat kButtonSize     = 36.0;
static const CGFloat kButtonIconSize = 18.0;
static const CGFloat kButtonSpacing  = 12.0;

@interface HAVacuumEntityCell ()
@property (nonatomic, strong) UIView  *iconCircle;
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *statusLabel2;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *returnHomeButton;
@property (nonatomic, strong) UIButton *powerButton;
@property (nonatomic, strong) UIButton *locateButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *spotButton;
@property (nonatomic, strong) UIButton *fanSpeedButton;
@property (nonatomic, copy)   NSArray<NSString *> *configuredCommands;
@end

@implementation HAVacuumEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    // Hide base cell labels — vacuum card has its own centered layout
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // -- Icon circle (centered, top area) --
    self.iconCircle = [[UIView alloc] init];
    self.iconCircle.layer.cornerRadius = kIconCircleSize / 2.0;
    self.iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.iconCircle];

    self.iconLabel = [[UILabel alloc] init];
    self.iconLabel.textAlignment = NSTextAlignmentCenter;
    self.iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.iconCircle addSubview:self.iconLabel];

    // -- Status label --
    self.statusLabel2 = [self labelWithFont:[UIFont ha_systemFontOfSize:13 weight:HAFontWeightMedium] color:[HATheme secondaryTextColor] lines:1];
    self.statusLabel2.textAlignment = NSTextAlignmentCenter;

    // -- Command buttons --
    self.playPauseButton  = [self makeCommandButton];
    self.returnHomeButton = [self makeCommandButton];
    self.powerButton      = [self makeCommandButton];

    self.locateButton     = [self makeCommandButton];
    self.stopButton       = [self makeCommandButton];
    self.spotButton       = [self makeCommandButton];
    self.fanSpeedButton   = [self makeCommandButton];

    [self.playPauseButton  addTarget:self action:@selector(playPauseTapped)  forControlEvents:UIControlEventTouchUpInside];
    [self.returnHomeButton addTarget:self action:@selector(returnHomeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.powerButton      addTarget:self action:@selector(powerTapped)      forControlEvents:UIControlEventTouchUpInside];
    [self.locateButton     addTarget:self action:@selector(locateTapped)     forControlEvents:UIControlEventTouchUpInside];
    [self.stopButton       addTarget:self action:@selector(stopTapped)       forControlEvents:UIControlEventTouchUpInside];
    [self.spotButton       addTarget:self action:@selector(spotTapped)       forControlEvents:UIControlEventTouchUpInside];
    [self.fanSpeedButton   addTarget:self action:@selector(fanSpeedTapped)   forControlEvents:UIControlEventTouchUpInside];

    // --- Layout constraints ---
    // Icon circle and status label use auto layout. Buttons are positioned in layoutSubviews
    // to handle dynamic visibility (only configured commands shown).

    // Icon circle: centered horizontally, near top
    HAActivateConstraints(@[
        HACon([self.iconCircle.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor]),
        HACon([self.iconCircle.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:padding + 4]),
        HACon([self.iconCircle.widthAnchor constraintEqualToConstant:kIconCircleSize]),
        HACon([self.iconCircle.heightAnchor constraintEqualToConstant:kIconCircleSize]),
    ]);

    // Icon label: centered inside circle
    HACenterIn(self.iconLabel, self.iconCircle, YES, YES);

    // Status label: below icon circle, centered
    HAActivateConstraints(@[
        HACon([self.statusLabel2.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor]),
        HACon([self.statusLabel2.topAnchor constraintEqualToAnchor:self.iconCircle.bottomAnchor constant:4]),
        HACon([self.statusLabel2.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:padding]),
        HACon([self.statusLabel2.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-padding]),
    ]);

    // Buttons don't use auto layout — positioned in layoutSubviews for dynamic visibility
    self.playPauseButton.translatesAutoresizingMaskIntoConstraints = YES;
    self.returnHomeButton.translatesAutoresizingMaskIntoConstraints = YES;
    self.powerButton.translatesAutoresizingMaskIntoConstraints = YES;
    self.locateButton.translatesAutoresizingMaskIntoConstraints = YES;
    self.stopButton.translatesAutoresizingMaskIntoConstraints = YES;
    self.spotButton.translatesAutoresizingMaskIntoConstraints = YES;
    self.fanSpeedButton.translatesAutoresizingMaskIntoConstraints = YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat padding = 10.0;
    CGFloat contentW = self.contentView.bounds.size.width;
    CGFloat contentH = self.contentView.bounds.size.height;

    if (!HAAutoLayoutAvailable()) {
        // Icon circle: centered horizontally, near top
        self.iconCircle.frame = CGRectMake((contentW - kIconCircleSize) / 2.0, padding + 4, kIconCircleSize, kIconCircleSize);
        self.iconLabel.frame = CGRectMake(0, 0, kIconCircleSize, kIconCircleSize);

        // Status label: below icon, centered
        CGSize statusSize = [self.statusLabel2 sizeThatFits:CGSizeMake(contentW - padding * 2, CGFLOAT_MAX)];
        self.statusLabel2.frame = CGRectMake((contentW - statusSize.width) / 2.0, CGRectGetMaxY(self.iconCircle.frame) + 4, statusSize.width, statusSize.height);
    }

    // Collect visible buttons
    NSMutableArray<UIButton *> *visibleButtons = [NSMutableArray array];
    if (!self.playPauseButton.hidden) [visibleButtons addObject:self.playPauseButton];
    if (!self.stopButton.hidden) [visibleButtons addObject:self.stopButton];
    if (!self.returnHomeButton.hidden) [visibleButtons addObject:self.returnHomeButton];
    if (!self.locateButton.hidden) [visibleButtons addObject:self.locateButton];
    if (!self.spotButton.hidden) [visibleButtons addObject:self.spotButton];
    if (!self.fanSpeedButton.hidden) [visibleButtons addObject:self.fanSpeedButton];
    if (!self.powerButton.hidden) [visibleButtons addObject:self.powerButton];

    NSUInteger count = visibleButtons.count;
    if (count == 0) return;

    CGFloat totalButtonsWidth = count * kButtonSize + (count - 1) * kButtonSpacing;
    CGFloat startX = (contentW - totalButtonsWidth) / 2.0;
    CGFloat btnY = contentH - padding - kButtonSize;

    for (NSUInteger i = 0; i < count; i++) {
        UIButton *btn = visibleButtons[i];
        btn.frame = CGRectMake(startX + i * (kButtonSize + kButtonSpacing), btnY, kButtonSize, kButtonSize);
    }
}

- (UIButton *)makeCommandButton {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.layer.cornerRadius = kButtonSize / 2.0;
    btn.clipsToBounds = YES;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:btn];
    return btn;
}

#pragma mark - Configuration

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    // Keep base labels hidden
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    // Read configured commands from card config (e.g. ["start_pause", "return_home", "on_off"])
    // Mushroom default: no buttons unless commands are explicitly configured.
    NSArray *commands = configItem.customProperties[@"commands"];
    if ([commands isKindOfClass:[NSArray class]] && commands.count > 0) {
        self.configuredCommands = commands;
    } else {
        self.configuredCommands = @[]; // mushroom default: no buttons
    }

    // Filter commands by entity supported_features bitmask (matching mushroom behavior).
    // Even if a command is configured, hide it if the vacuum doesn't support the feature.
    NSInteger features = [entity supportedFeatures];
    BOOL supportsStart    = (features & (1 << 13)) != 0; // START = 8192
    BOOL supportsPause    = (features & (1 << 2)) != 0;  // PAUSE = 4
    BOOL supportsStop     = (features & (1 << 3)) != 0;  // STOP = 8
    BOOL supportsReturn   = (features & (1 << 4)) != 0;  // RETURN_HOME = 16
    BOOL supportsTurnOn   = (features & (1 << 0)) != 0;  // TURN_ON = 1
    BOOL supportsTurnOff  = (features & (1 << 1)) != 0;  // TURN_OFF = 2
    BOOL supportsLocate   = (features & (1 << 9)) != 0;  // LOCATE = 512
    BOOL supportsSpot     = (features & (1 << 5)) != 0;  // CLEAN_SPOT = 32
    BOOL supportsFanSpeed = (features & (1 << 6)) != 0;  // FAN_SPEED = 64

    BOOL hasCommands = self.configuredCommands.count > 0;

    BOOL showPlayPause = (hasCommands ? [self.configuredCommands containsObject:@"start_pause"] : YES)
                         && (supportsStart || supportsPause);
    BOOL showReturnHome = (hasCommands ? [self.configuredCommands containsObject:@"return_home"] : YES)
                          && supportsReturn;
    BOOL showPower = (hasCommands ? [self.configuredCommands containsObject:@"on_off"] : NO)
                     && (supportsTurnOn || supportsTurnOff);
    BOOL showLocate = (hasCommands ? [self.configuredCommands containsObject:@"locate"] : NO)
                      && supportsLocate;
    BOOL showStop = (hasCommands ? [self.configuredCommands containsObject:@"stop"] : NO)
                    && supportsStop;
    BOOL showSpot = (hasCommands ? [self.configuredCommands containsObject:@"clean_spot"] : NO)
                    && supportsSpot;
    BOOL showFanSpeed = (hasCommands ? [self.configuredCommands containsObject:@"fan_speed"] : NO)
                        && supportsFanSpeed;

    self.playPauseButton.hidden = !showPlayPause;
    self.returnHomeButton.hidden = !showReturnHome;
    self.powerButton.hidden = !showPower;
    self.locateButton.hidden = !showLocate;
    self.stopButton.hidden = !showStop;
    self.spotButton.hidden = !showSpot;
    self.fanSpeedButton.hidden = !showFanSpeed;

    if (!entity) {
        self.statusLabel2.text = @"Unavailable";
        [self applyIconColorForState:nil];
        [self updateButtonIcons:nil];
        return;
    }

    // Status text: vacuum status with optional battery
    NSString *vacuumState = [entity vacuumStatus] ?: entity.state ?: @"unknown";
    NSNumber *battery = [entity vacuumBatteryLevel];
    NSMutableString *display = [NSMutableString stringWithString:[HAEntityDisplayHelper humanReadableState:vacuumState]];
    if (battery) {
        [display appendFormat:@" \u2022 %@%%", battery];
    }
    self.statusLabel2.text = display;

    // Icon color based on state
    [self applyIconColorForState:vacuumState];

    // Button states
    [self updateButtonIcons:vacuumState];

    BOOL available = entity.isAvailable;
    self.playPauseButton.enabled = available;
    self.returnHomeButton.enabled = available;
    self.powerButton.enabled = available;
    self.locateButton.enabled = available;
    self.stopButton.enabled = available;
    self.spotButton.enabled = available;
    self.fanSpeedButton.enabled = available;
    self.playPauseButton.alpha = available ? 1.0 : 0.4;
    self.returnHomeButton.alpha = available ? 1.0 : 0.4;
    self.powerButton.alpha = available ? 1.0 : 0.4;
    self.locateButton.alpha = available ? 1.0 : 0.4;
    self.stopButton.alpha = available ? 1.0 : 0.4;
    self.spotButton.alpha = available ? 1.0 : 0.4;
    self.fanSpeedButton.alpha = available ? 1.0 : 0.4;
}

- (void)applyIconColorForState:(NSString *)vacuumState {
    UIColor *iconColor;
    UIColor *circleBg;

    NSString *state = [vacuumState lowercaseString];

    if ([state isEqualToString:@"cleaning"]) {
        iconColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.65 alpha:1.0]; // Teal
        circleBg  = [UIColor colorWithRed:0.0 green:0.75 blue:0.65 alpha:0.15];
    } else if ([state isEqualToString:@"returning"]) {
        iconColor = [HATheme accentColor]; // Blue
        circleBg  = [[HATheme accentColor] colorWithAlphaComponent:0.15];
    } else if ([state isEqualToString:@"error"]) {
        iconColor = [HATheme destructiveColor]; // Red
        circleBg  = [[HATheme destructiveColor] colorWithAlphaComponent:0.15];
    } else {
        // Docked, idle, off, paused, unknown
        iconColor = [HATheme secondaryTextColor]; // Gray
        circleBg  = [HATheme tertiaryTextColor]; // Subtle gray
        circleBg  = [circleBg colorWithAlphaComponent:0.3];
    }

    self.iconCircle.backgroundColor = circleBg;

    // Set the robot-vacuum MDI glyph
    NSString *glyph = [HAIconMapper glyphForIconName:@"robot-vacuum"] ?: @"\u2699"; // fallback gear
    NSAttributedString *iconAttr = [HAIconMapper attributedGlyph:glyph fontSize:kIconFontSize color:iconColor];
    self.iconLabel.attributedText = iconAttr;
}

- (void)updateButtonIcons:(NSString *)vacuumState {
    NSString *state = [vacuumState lowercaseString];
    BOOL isCleaning = [state isEqualToString:@"cleaning"];
    BOOL isOn = ![state isEqualToString:@"off"] && state != nil;

    // Play/Pause button: show pause icon when cleaning, play icon otherwise
    NSString *playPauseIcon = isCleaning ? @"pause" : @"play";
    [self setButton:self.playPauseButton iconName:playPauseIcon];

    // Return home button
    [self setButton:self.returnHomeButton iconName:@"home"];

    // Power button: show power-off styling when on, power-on when off
    [self setButton:self.powerButton iconName:@"power"];

    // New buttons
    [self setButton:self.locateButton iconName:@"map-marker-radius"];
    [self setButton:self.stopButton iconName:@"stop"];
    [self setButton:self.spotButton iconName:@"target"];
    // Fan speed: show current speed text
    NSString *fanSpeed = HAAttrString(self.entity.attributes, HAAttrFanSpeed);
    if (fanSpeed) {
        [self.fanSpeedButton setAttributedTitle:nil forState:UIControlStateNormal];
        [self.fanSpeedButton setTitle:fanSpeed forState:UIControlStateNormal];
        self.fanSpeedButton.titleLabel.font = [UIFont ha_systemFontOfSize:10 weight:HAFontWeightMedium];
        [self.fanSpeedButton setTitleColor:[HATheme primaryTextColor] forState:UIControlStateNormal];
    } else {
        [self setButton:self.fanSpeedButton iconName:@"fan"];
    }

    // Button background colors
    UIColor *btnBg = [HATheme tertiaryTextColor];
    btnBg = [btnBg colorWithAlphaComponent:0.25];

    for (UIButton *btn in @[self.playPauseButton, self.returnHomeButton, self.locateButton,
                             self.stopButton, self.spotButton, self.fanSpeedButton]) {
        btn.backgroundColor = btnBg;
    }
    self.powerButton.backgroundColor = isOn ? btnBg : [[HATheme secondaryTextColor] colorWithAlphaComponent:0.15];
}

- (void)setButton:(UIButton *)button iconName:(NSString *)iconName {
    [HAIconMapper setIconName:iconName onButton:button size:kButtonIconSize color:[HATheme primaryTextColor]];
}

#pragma mark - Actions

- (void)playPauseTapped {
    [HAHaptics mediumImpact];

    NSString *domain = [self.entity domain];
    BOOL isLawnMower = [domain isEqualToString:@"lawn_mower"];

    NSString *state = [[self.entity vacuumStatus] ?: self.entity.state lowercaseString];
    NSString *service;
    if ([state isEqualToString:@"cleaning"] || [state isEqualToString:@"mowing"]) {
        service = isLawnMower ? @"pause" : @"pause";
    } else {
        service = isLawnMower ? @"start_mowing" : @"start";
    }

    [self callService:service inDomain:domain];
}

- (void)returnHomeTapped {
    [HAHaptics mediumImpact];
    NSString *domain = [self.entity domain];
    NSString *service = [domain isEqualToString:@"lawn_mower"] ? @"dock" : @"return_to_base";
    [self callService:service inDomain:domain];
}

- (void)powerTapped {
    [HAHaptics mediumImpact];

    NSString *state = [[self.entity vacuumStatus] ?: self.entity.state lowercaseString];
    NSString *service;
    if ([state isEqualToString:@"off"]) {
        service = @"turn_on";
    } else {
        service = @"turn_off";
    }

    [self callService:service inDomain:HAEntityDomainVacuum];
}

- (void)locateTapped {
    [HAHaptics mediumImpact];
    [self callService:@"locate" inDomain:HAEntityDomainVacuum];
}

- (void)stopTapped {
    [HAHaptics mediumImpact];
    [self callService:@"stop" inDomain:HAEntityDomainVacuum];
}

- (void)spotTapped {
    [HAHaptics mediumImpact];
    [self callService:@"clean_spot" inDomain:HAEntityDomainVacuum];
}

- (void)fanSpeedTapped {
    if (!self.entity) return;
    NSArray *speeds = HAAttrArray(self.entity.attributes, HAAttrFanSpeedList);
    if (speeds.count == 0) return;
    NSString *current = HAAttrString(self.entity.attributes, HAAttrFanSpeed);

    [self presentOptionsWithTitle:@"Fan Speed" options:speeds current:current sourceView:self.fanSpeedButton
                          handler:^(NSString *selected) {
        [self callService:@"set_fan_speed" inDomain:HAEntityDomainVacuum withData:@{@"fan_speed": selected}];
    }];
}

#pragma mark - Reuse

- (void)prepareForReuse {
    [super prepareForReuse];
    self.statusLabel2.text = nil;
    self.iconLabel.attributedText = nil;
    self.iconCircle.backgroundColor = nil;
    self.configuredCommands = nil;
    self.playPauseButton.hidden = NO;
    self.returnHomeButton.hidden = NO;
    self.powerButton.hidden = NO;
    self.locateButton.hidden = YES;
    self.stopButton.hidden = YES;
    self.spotButton.hidden = YES;
    self.fanSpeedButton.hidden = YES;
    self.statusLabel2.textColor = [HATheme secondaryTextColor];
}

@end
