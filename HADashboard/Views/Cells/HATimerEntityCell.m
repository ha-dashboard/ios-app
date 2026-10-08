#import "HATimerEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "UIView+HAUtilities.h"

static const CGFloat kHATimerButtonBaseFontSize = 12.0;
static const CGFloat kHATimerButtonMinimumScaleFactor = 0.6;
static const CGFloat kHATimerButtonTitleHorizontalInset = 8.0; // matches the button's own content insets

@interface HATimerEntityCell ()
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *pauseButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *finishButton;
@property (nonatomic, strong) UIButton *changeButton;
/// Cache so -layoutSubviews only recomputes the shared button font when
/// something that could change it actually changed (button width from a
/// resize, or a button's title from re-localization) — not on every layout
/// pass, which can happen often (scrolling, other cells' content changing).
@property (nonatomic, assign) CGFloat ha_lastButtonFontComputationWidth;
@property (nonatomic, copy) NSString *ha_lastButtonFontComputationTitles;
@end

@implementation HATimerEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Time display
    self.timeLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:20 weight:UIFontWeightMedium] color:[HATheme primaryTextColor] lines:1];

    CGFloat buttonHeight = 28.0;
    CGFloat buttonSpacing = 4.0;

    // Start/Pause/Cancel/Finish are laid out in an equal-width row (UIStackView,
    // available since iOS 9.0) spanning the full card width, instead of fixed
    // 56pt-wide buttons trailing-chained off the right edge. At the narrowest
    // supported column span (or with longer localized button titles — these
    // are being localized on feature/i18n), four fixed-width buttons overflow
    // the card and get pushed off the left edge, clipping "Start" to "art".
    // Equal-width distribution always fits, and adjustsFontSizeToFitWidth
    // shrinks the title rather than clipping it if a translation is long.
    self.startButton = [self ha_timerButtonWithTitle:@"Start" backgroundColor:[HATheme successColor] action:@selector(startTapped)];
    self.pauseButton = [self ha_timerButtonWithTitle:@"Pause" backgroundColor:[HATheme warningColor] action:@selector(pauseTapped)];
    self.cancelButton = [self ha_timerButtonWithTitle:@"Cancel" backgroundColor:[HATheme destructiveColor] action:@selector(cancelTapped)];
    self.finishButton = [self ha_timerButtonWithTitle:@"Finish" backgroundColor:[HATheme accentColor] action:@selector(finishTapped)];

    UIStackView *buttonRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.finishButton, self.startButton, self.pauseButton, self.cancelButton
    ]];
    buttonRow.axis = UILayoutConstraintAxisHorizontal;
    buttonRow.distribution = UIStackViewDistributionFillEqually;
    buttonRow.alignment = UIStackViewAlignmentFill;
    buttonRow.spacing = buttonSpacing;
    buttonRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:buttonRow];

    // Time label: below name
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.timeLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.timeLabel attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.nameLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:4]];

    // Change button (set new duration)
    self.changeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.changeButton setTitle:@"Change" forState:UIControlStateNormal];
    self.changeButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    self.changeButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.changeButton.titleLabel.minimumScaleFactor = 0.6;
    [self.changeButton setTitleColor:[HATheme accentColor] forState:UIControlStateNormal];
    self.changeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.changeButton addTarget:self action:@selector(changeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.changeButton];

    [NSLayoutConstraint activateConstraints:@[
        [buttonRow.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [buttonRow.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
        [buttonRow.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding],
        [buttonRow.heightAnchor constraintEqualToConstant:buttonHeight],
        // Change button: right-aligned, same Y as the time label
        [self.changeButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
        [self.changeButton.centerYAnchor constraintEqualToAnchor:self.timeLabel.centerYAnchor],
    ]];
}

/// Builds one of the bottom-row action buttons (Start/Pause/Cancel/Finish),
/// configured to shrink its title rather than clip it if the (eventually
/// localized) label doesn't fit the equal-width column it's given.
- (UIButton *)ha_timerButtonWithTitle:(NSString *)title backgroundColor:(UIColor *)backgroundColor action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:kHATimerButtonBaseFontSize];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = kHATimerButtonMinimumScaleFactor;
    button.titleLabel.lineBreakMode = NSLineBreakByClipping;
    button.titleLabel.numberOfLines = 1;
    button.backgroundColor = backgroundColor;
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.layer.cornerRadius = 4.0;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    NSString *state = entity.state;
    BOOL isActive = [state isEqualToString:@"active"];
    BOOL isPaused = [state isEqualToString:@"paused"];
    BOOL isIdle = [state isEqualToString:@"idle"];

    // Show remaining time if active/paused, otherwise duration
    NSString *remaining = [entity timerRemaining];
    NSString *duration = [entity timerDuration];
    if (isActive || isPaused) {
        self.timeLabel.text = remaining ?: duration ?: @"--:--:--";
    } else {
        self.timeLabel.text = duration ?: @"--:--:--";
    }

    if (isActive) {
        self.timeLabel.textColor = [HATheme accentColor];
    } else if (isPaused) {
        self.timeLabel.textColor = [HATheme warningColor];
    } else {
        self.timeLabel.textColor = [HATheme primaryTextColor];
    }

    BOOL available = entity.isAvailable;
    self.startButton.enabled = available && (isIdle || isPaused);
    self.pauseButton.enabled = available && isActive;
    self.cancelButton.enabled = available && (isActive || isPaused);
    self.finishButton.enabled = available && (isActive || isPaused);
    self.changeButton.enabled = available;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self ha_updateSharedButtonFontIfNeeded];
}

#pragma mark - Shared Button Row Font

/// Start/Pause/Cancel/Finish are equal-width (UIStackView FillEqually), but
/// each button's own adjustsFontSizeToFitWidth shrinks its title
/// independently — so a short title like "Pause" stays at the base size
/// while a long one shrinks, and the row reads as mismatched font sizes.
/// Instead, every button shares ONE font: the largest size that still fits
/// the longest title in its (equal) button width, with
/// kHATimerButtonMinimumScaleFactor as the floor adjustsFontSizeToFitWidth
/// would also respect if our computed size were somehow still too large.
- (void)ha_updateSharedButtonFontIfNeeded {
    CGFloat width = CGRectGetWidth(self.startButton.bounds);
    if (width <= 0) return;

    NSString *titlesSignature = [@[
        self.finishButton.currentTitle ?: @"", self.startButton.currentTitle ?: @"",
        self.pauseButton.currentTitle ?: @"", self.cancelButton.currentTitle ?: @"",
    ] componentsJoinedByString:@"␟"]; // unit-separator-ish join; titles can't contain it

    if (fabs(width - self.ha_lastButtonFontComputationWidth) < 0.5 &&
        [titlesSignature isEqualToString:self.ha_lastButtonFontComputationTitles]) {
        return; // Nothing that would change the shared font has changed.
    }
    self.ha_lastButtonFontComputationWidth = width;
    self.ha_lastButtonFontComputationTitles = titlesSignature;

    NSArray<UIButton *> *buttons = @[self.finishButton, self.startButton, self.pauseButton, self.cancelButton];
    UIFont *baseFont = [UIFont boldSystemFontOfSize:kHATimerButtonBaseFontSize];
    CGFloat availableWidth = width - kHATimerButtonTitleHorizontalInset;
    if (availableWidth <= 0) return;

    CGFloat smallestScale = 1.0;
    for (UIButton *button in buttons) {
        NSString *title = button.currentTitle ?: @"";
        if (title.length == 0) continue;
        CGFloat textWidth = [title sizeWithAttributes:@{NSFontAttributeName: baseFont}].width;
        if (textWidth <= 0) continue;
        smallestScale = MIN(smallestScale, availableWidth / textWidth);
    }
    smallestScale = MAX(MIN(smallestScale, 1.0), kHATimerButtonMinimumScaleFactor);

    UIFont *sharedFont = [UIFont boldSystemFontOfSize:kHATimerButtonBaseFontSize * smallestScale];
    for (UIButton *button in buttons) {
        button.titleLabel.font = sharedFont;
    }
}

#pragma mark - Actions

- (void)startTapped {
    [self callService:@"start" inDomain:HAEntityDomainTimer];
}

- (void)pauseTapped {
    [self callService:@"pause" inDomain:HAEntityDomainTimer];
}

- (void)cancelTapped {
    [self callService:@"cancel" inDomain:HAEntityDomainTimer];
}

- (void)finishTapped {
    [self callService:@"finish" inDomain:HAEntityDomainTimer];
}

- (void)changeTapped {
    UIViewController *vc = [self ha_parentViewController];
    if (!vc) return;

    UIDatePicker *picker = [[UIDatePicker alloc] init];
    picker.datePickerMode = UIDatePickerModeCountDownTimer;
    picker.countDownDuration = 300; // default 5 minutes

    // Parse current duration as default
    NSString *duration = [self.entity timerDuration];
    if (duration.length > 0) {
        NSArray *parts = [duration componentsSeparatedByString:@":"];
        if (parts.count == 3) {
            NSTimeInterval secs = [parts[0] doubleValue] * 3600 + [parts[1] doubleValue] * 60 + [parts[2] doubleValue];
            if (secs > 0) picker.countDownDuration = secs;
        }
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Set Duration"
                                                                  message:@"\n\n\n\n\n\n\n"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert.view addSubview:picker];
    picker.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [picker.centerXAnchor constraintEqualToAnchor:alert.view.centerXAnchor],
        [picker.topAnchor constraintEqualToAnchor:alert.view.topAnchor constant:50],
    ]];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Set" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSTimeInterval secs = picker.countDownDuration;
        NSInteger h = (NSInteger)(secs / 3600);
        NSInteger m = (NSInteger)((NSInteger)secs % 3600) / 60;
        NSInteger s = (NSInteger)secs % 60;
        NSString *dur = [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)s];
        [weakSelf callService:@"change" inDomain:HAEntityDomainTimer withData:@{@"duration": dur}];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [vc presentViewController:alert animated:YES completion:nil];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.timeLabel.text = nil;
    self.timeLabel.textColor = [HATheme primaryTextColor];
    self.startButton.backgroundColor = [HATheme successColor];
    self.pauseButton.backgroundColor = [HATheme warningColor];
    self.cancelButton.backgroundColor = [HATheme destructiveColor];
    self.finishButton.backgroundColor = [HATheme accentColor];
    // Force a recomputation on next layout rather than trusting the cache —
    // cheap (a couple of string/float compares) and avoids a reused cell
    // ever showing a stale shared font from a previous width/locale.
    self.ha_lastButtonFontComputationWidth = 0;
    self.ha_lastButtonFontComputationTitles = nil;
}

@end
