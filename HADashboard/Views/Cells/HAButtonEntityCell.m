#import "HAButtonEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"

static const NSTimeInterval kPressFeedbackDuration = 1.5;

@interface HAButtonEntityCell ()
@property (nonatomic, strong) UIButton *pressButton;
@property (nonatomic, strong) UILabel *feedbackLabel;
@property (nonatomic, assign) BOOL pressing;
@end

@implementation HAButtonEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Press button
    self.pressButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pressButton setTitle:@"Press" forState:UIControlStateNormal];
    self.pressButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.pressButton.backgroundColor = [HATheme accentColor];
    [self.pressButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.pressButton.layer.cornerRadius = 6.0;
    self.pressButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pressButton addTarget:self action:@selector(pressTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.pressButton];

    // Feedback label
    self.feedbackLabel = [self labelWithFont:[UIFont boldSystemFontOfSize:13] color:[HATheme successColor] lines:1];
    self.feedbackLabel.text = @"Pressed";
    self.feedbackLabel.textAlignment = NSTextAlignmentCenter;
    self.feedbackLabel.alpha = 0.0;

    // Press button: right side, vertically centered
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.pressButton attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.pressButton attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeCenterY multiplier:1 constant:8]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.pressButton attribute:NSLayoutAttributeWidth
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:80]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.pressButton attribute:NSLayoutAttributeHeight
        relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:32]];

    // Feedback label: same position as button
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.feedbackLabel attribute:NSLayoutAttributeCenterX
        relatedBy:NSLayoutRelationEqual toItem:self.pressButton attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.feedbackLabel attribute:NSLayoutAttributeCenterY
        relatedBy:NSLayoutRelationEqual toItem:self.pressButton attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.pressButton.enabled = entity.isAvailable;

    if (!self.pressing) {
        self.pressButton.alpha = 1.0;
        self.feedbackLabel.alpha = 0.0;
    }
}

#pragma mark - Actions

- (void)pressTapped {
    if (!self.entity || self.pressing) return;

    self.pressing = YES;

    [HAHaptics mediumImpact];

    [self callService:@"press" inDomain:[self.entity domain]];

    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.2 animations:^{
        self.pressButton.alpha = 0.0;
        self.feedbackLabel.alpha = 1.0;
        self.contentView.backgroundColor = [HATheme onTintColor];
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPressFeedbackDuration * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                [UIView animateWithDuration:0.3 animations:^{
                    strongSelf.pressButton.alpha = 1.0;
                    strongSelf.feedbackLabel.alpha = 0.0;
                    strongSelf.contentView.backgroundColor = [HATheme cellBackgroundColor];
                } completion:^(BOOL finished2) {
                    strongSelf.pressing = NO;
                }];
            });
    }];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.pressing = NO;
    self.pressButton.alpha = 1.0;
    self.feedbackLabel.alpha = 0.0;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.pressButton.backgroundColor = [HATheme accentColor];
    self.feedbackLabel.textColor = [HATheme successColor];
}

@end
