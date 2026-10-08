#import "HASceneEntityCell.h"
#import "HAStrings.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"

static const NSTimeInterval kActivationFeedbackDuration = 1.5;

@interface HASceneEntityCell ()
@property (nonatomic, strong) UIButton *activateButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UILabel *feedbackLabel;
@property (nonatomic, assign) BOOL activating;
@end

@implementation HASceneEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Activate button
    self.activateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.activateButton setTitle:HALocalizedString(@"cell.scene.activate", @"Button in the scene cell, activates the scene. Max ~10 chars -- fixed-width pill.") forState:UIControlStateNormal];
    self.activateButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.activateButton.backgroundColor = [HATheme accentColor];
    [self.activateButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.activateButton.layer.cornerRadius = 6.0;
    self.activateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.activateButton addTarget:self action:@selector(activateTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.activateButton];

    // Feedback label (shown briefly after activation)
    self.feedbackLabel = [self labelWithFont:[UIFont boldSystemFontOfSize:13] color:[HATheme successColor] lines:1];
    self.feedbackLabel.text = HALocalizedString(@"cell.scene.activated", @"Feedback label in the scene cell, briefly shown after activation. Max ~10 chars.");
    self.feedbackLabel.textAlignment = NSTextAlignmentCenter;
    self.feedbackLabel.alpha = 0.0;

    // Activate button: centered bottom
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.activateButton attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.activateButton attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeCenterY multiplier:1 constant:8]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.activateButton attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:80]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.activateButton attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:32]];

    // Feedback label: same position as button
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.feedbackLabel attribute:NSLayoutAttributeCenterX
        relatedBy:NSLayoutRelationEqual toItem:self.activateButton attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.feedbackLabel attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:self.activateButton attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];

    // Stop button (for running scripts)
    self.stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.stopButton setTitle:HALocalizedString(@"cell.scene.stop", @"Button in the scene cell, stops a running script. Max ~8 chars -- fixed-width pill.") forState:UIControlStateNormal];
    self.stopButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.stopButton.backgroundColor = [HATheme destructiveColor];
    [self.stopButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.stopButton.layer.cornerRadius = 6.0;
    self.stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.stopButton.hidden = YES;
    [self.stopButton addTarget:self action:@selector(stopTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.stopButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.stopButton.trailingAnchor constraintEqualToAnchor:self.activateButton.leadingAnchor constant:-4],
        [self.stopButton.centerYAnchor constraintEqualToAnchor:self.activateButton.centerYAnchor],
        [self.stopButton.widthAnchor constraintEqualToConstant:60],
        [self.stopButton.heightAnchor constraintEqualToConstant:32],
    ]];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.activateButton.enabled = entity.isAvailable;

    NSString *domain = [entity domain];
    if ([domain isEqualToString:HAEntityDomainScript]) {
        [self.activateButton setTitle:HALocalizedString(@"cell.scene.run", @"Button in the scene cell, runs a script entity. Max ~10 chars -- fixed-width pill.") forState:UIControlStateNormal];
        // Show Stop button when script is running
        BOOL isRunning = entity.isOn;
        self.stopButton.hidden = !isRunning;
    } else if ([domain isEqualToString:@"automation"]) {
        [self.activateButton setTitle:HALocalizedString(@"cell.scene.trigger", @"Button in the scene cell, triggers an automation entity. Max ~10 chars -- fixed-width pill.") forState:UIControlStateNormal];
        self.stopButton.hidden = YES;
    } else {
        [self.activateButton setTitle:HALocalizedString(@"cell.scene.activate", @"Button in the scene cell, activates the scene. Max ~10 chars -- fixed-width pill.") forState:UIControlStateNormal];
        self.stopButton.hidden = YES;
    }
    self.activateButton.backgroundColor = [HATheme accentColor];

    // Reset feedback state if not currently animating
    if (!self.activating) {
        self.activateButton.alpha = 1.0;
        self.feedbackLabel.alpha = 0.0;
    }
}

#pragma mark - Actions

- (void)activateTapped {
    if (!self.entity || self.activating) return;

    self.activating = YES;

    [HAHaptics notifySuccess];

    // Call the service — automation uses trigger, others use turn_on
    NSString *domain = [self.entity domain];
    NSString *service = [domain isEqualToString:@"automation"] ? @"trigger" : @"turn_on";
    [self callService:service inDomain:domain];

    // Visual feedback: flash the button, show "Activated"
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.2 animations:^{
        self.activateButton.alpha = 0.0;
        self.feedbackLabel.alpha = 1.0;
        self.contentView.backgroundColor = [HATheme onTintColor];
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kActivationFeedbackDuration * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                [UIView animateWithDuration:0.3 animations:^{
                    strongSelf.activateButton.alpha = 1.0;
                    strongSelf.feedbackLabel.alpha = 0.0;
                    strongSelf.contentView.backgroundColor = [HATheme cellBackgroundColor];
                } completion:^(BOOL finished2) {
                    strongSelf.activating = NO;
                }];
            });
    }];
}

- (void)stopTapped {
    if (!self.entity) return;
    [HAHaptics mediumImpact];
    [self callService:@"turn_off" inDomain:[self.entity domain]];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.activating = NO;
    self.activateButton.alpha = 1.0;
    self.feedbackLabel.alpha = 0.0;
    self.stopButton.hidden = YES;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.activateButton.backgroundColor = [HATheme accentColor];
    self.feedbackLabel.textColor = [HATheme successColor];
    self.stopButton.backgroundColor = [HATheme destructiveColor];
}

@end
