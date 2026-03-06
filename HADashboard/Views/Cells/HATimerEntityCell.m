#import "HATimerEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "UIView+HAUtilities.h"

@interface HATimerEntityCell ()
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *pauseButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *finishButton;
@property (nonatomic, strong) UIButton *changeButton;
@end

@implementation HATimerEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Time display
    self.timeLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:20 weight:UIFontWeightMedium] color:[HATheme primaryTextColor] lines:1];

    CGFloat buttonWidth = 56.0;
    CGFloat buttonHeight = 28.0;
    CGFloat buttonSpacing = 4.0;

    // Start button
    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startButton setTitle:@"Start" forState:UIControlStateNormal];
    self.startButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    self.startButton.backgroundColor = [HATheme successColor];
    [self.startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startButton.layer.cornerRadius = 4.0;
    self.startButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.startButton addTarget:self action:@selector(startTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.startButton];

    // Pause button
    self.pauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pauseButton setTitle:@"Pause" forState:UIControlStateNormal];
    self.pauseButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    self.pauseButton.backgroundColor = [HATheme warningColor];
    [self.pauseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.pauseButton.layer.cornerRadius = 4.0;
    self.pauseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pauseButton addTarget:self action:@selector(pauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.pauseButton];

    // Cancel button
    self.cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    self.cancelButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    self.cancelButton.backgroundColor = [HATheme destructiveColor];
    [self.cancelButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.cancelButton.layer.cornerRadius = 4.0;
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.cancelButton];

    // Time label: below name
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.timeLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.timeLabel attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.nameLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:4]];

    // Buttons: bottom-right row
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.cancelButton attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.cancelButton attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.cancelButton attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonWidth]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.cancelButton attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonHeight]];

    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.pauseButton attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.cancelButton attribute:NSLayoutAttributeLeading multiplier:1 constant:-buttonSpacing]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.pauseButton attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.pauseButton attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonWidth]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.pauseButton attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonHeight]];

    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.startButton attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.pauseButton attribute:NSLayoutAttributeLeading multiplier:1 constant:-buttonSpacing]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.startButton attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.startButton attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonWidth]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.startButton attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonHeight]];

    // Finish button (force-complete the timer)
    self.finishButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.finishButton setTitle:@"Finish" forState:UIControlStateNormal];
    self.finishButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    self.finishButton.backgroundColor = [HATheme accentColor];
    [self.finishButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.finishButton.layer.cornerRadius = 4.0;
    self.finishButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.finishButton addTarget:self action:@selector(finishTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.finishButton];

    // Change button (set new duration)
    self.changeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.changeButton setTitle:@"Change" forState:UIControlStateNormal];
    self.changeButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [self.changeButton setTitleColor:[HATheme accentColor] forState:UIControlStateNormal];
    self.changeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.changeButton addTarget:self action:@selector(changeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.changeButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.finishButton.trailingAnchor constraintEqualToAnchor:self.startButton.leadingAnchor constant:-buttonSpacing],
        [self.finishButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-padding],
        [self.finishButton.widthAnchor constraintEqualToConstant:buttonWidth],
        [self.finishButton.heightAnchor constraintEqualToConstant:buttonHeight],
        // Change button: left of time label, same Y
        [self.changeButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
        [self.changeButton.centerYAnchor constraintEqualToAnchor:self.timeLabel.centerYAnchor],
    ]];
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
}

@end
