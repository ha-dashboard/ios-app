#import "HAAutoLayout.h"
#import "HAUpdateEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "UIFont+HACompat.h"

@interface HAUpdateEntityCell ()
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIButton *updateButton;
@property (nonatomic, strong) UIButton *skipButton;
@end

@implementation HAUpdateEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Version info label
    self.versionLabel = [self labelWithFont:[UIFont systemFontOfSize:12] color:[HATheme secondaryTextColor] lines:2];

    // Update button
    self.updateButton = HASystemButton();
    [self.updateButton setTitle:@"Update" forState:UIControlStateNormal];
    self.updateButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.updateButton.backgroundColor = [HATheme accentColor];
    [self.updateButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.updateButton.layer.cornerRadius = 6.0;
    self.updateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.updateButton addTarget:self action:@selector(updateTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.updateButton];

    // Version label: below name
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.versionLabel attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.versionLabel attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.updateButton attribute:NSLayoutAttributeLeading multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.versionLabel attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.nameLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:4]),
    ]);

    // Update button: right side, vertically centered
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.updateButton attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.updateButton attribute:NSLayoutAttributeCenterY
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeCenterY multiplier:1 constant:8]),
        HACon([NSLayoutConstraint constraintWithItem:self.updateButton attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:72]),
        HACon([NSLayoutConstraint constraintWithItem:self.updateButton attribute:NSLayoutAttributeHeight
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:30]),
    ]);

    // Release summary label (below version)
    self.summaryLabel = [[UILabel alloc] init];
    self.summaryLabel.font = [UIFont systemFontOfSize:11];
    self.summaryLabel.textColor = [HATheme secondaryTextColor];
    self.summaryLabel.numberOfLines = 2;
    self.summaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.summaryLabel.hidden = YES;
    [self.contentView addSubview:self.summaryLabel];

    HAActivateConstraints(@[
        HACon([self.summaryLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding]),
        HACon([self.summaryLabel.trailingAnchor constraintEqualToAnchor:self.updateButton.leadingAnchor constant:-padding]),
        HACon([self.summaryLabel.topAnchor constraintEqualToAnchor:self.versionLabel.bottomAnchor constant:2]),
    ]);

    // Skip button (below update button)
    self.skipButton = HASystemButton();
    [self.skipButton setTitle:@"Skip" forState:UIControlStateNormal];
    self.skipButton.titleLabel.font = [UIFont ha_systemFontOfSize:11 weight:HAFontWeightMedium];
    self.skipButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.skipButton.hidden = YES;
    [self.skipButton addTarget:self action:@selector(skipTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.skipButton];

    HAActivateConstraints(@[
        HACon([self.skipButton.centerXAnchor constraintEqualToAnchor:self.updateButton.centerXAnchor]),
        HACon([self.skipButton.topAnchor constraintEqualToAnchor:self.updateButton.bottomAnchor constant:2]),
    ]);
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    NSString *installed = [entity updateInstalledVersion] ?: @"?";
    NSString *latest = [entity updateLatestVersion] ?: @"?";
    BOOL hasUpdate = [entity updateAvailable];

    // Check if update is in progress
    id inProgress = entity.attributes[@"in_progress"];
    BOOL isUpdating = [inProgress isKindOfClass:[NSNumber class]] && [inProgress boolValue];

    if (hasUpdate) {
        self.versionLabel.text = [NSString stringWithFormat:@"%@ \u2192 %@", installed, latest];
        self.versionLabel.textColor = [HATheme accentColor];
        self.updateButton.hidden = NO;
        self.skipButton.hidden = NO;
        self.contentView.backgroundColor = [HATheme activeTintColor];

        if (isUpdating) {
            [self.updateButton setTitle:@"Installing\u2026" forState:UIControlStateNormal];
            self.updateButton.enabled = NO;
            self.skipButton.enabled = NO;
        } else {
            [self.updateButton setTitle:@"Update" forState:UIControlStateNormal];
            self.updateButton.enabled = entity.isAvailable;
            self.skipButton.enabled = entity.isAvailable;
        }

        // Release summary
        NSString *summary = HAAttrString(entity.attributes, HAAttrReleaseSummary);
        if (summary.length > 0) {
            self.summaryLabel.text = summary;
            self.summaryLabel.hidden = NO;
        } else {
            self.summaryLabel.hidden = YES;
        }
    } else {
        self.versionLabel.text = [NSString stringWithFormat:@"v%@ (up to date)", installed];
        self.versionLabel.textColor = [HATheme secondaryTextColor];
        self.updateButton.hidden = YES;
        self.skipButton.hidden = YES;
        self.summaryLabel.hidden = YES;
        self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    }
}

#pragma mark - Actions

- (void)updateTapped {
    [self callService:@"install" inDomain:HAEntityDomainUpdate];
}

- (void)skipTapped {
    [self callService:@"skip" inDomain:HAEntityDomainUpdate];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat padding = 10.0;
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat btnW = 72;
        CGFloat btnH = 30;
        // Update button right, vertically centered offset by 8
        self.updateButton.frame = CGRectMake(w - padding - btnW, h / 2 + 8 - btnH / 2, btnW, btnH);
        // Version label below nameLabel
        CGFloat nameMaxY = CGRectGetMaxY(self.nameLabel.frame);
        CGFloat verW = CGRectGetMinX(self.updateButton.frame) - padding * 2;
        CGSize verSize = [self.versionLabel sizeThatFits:CGSizeMake(verW, CGFLOAT_MAX)];
        self.versionLabel.frame = CGRectMake(padding, nameMaxY + 4, verW, verSize.height);
        // Summary below version
        if (!self.summaryLabel.hidden) {
            CGSize sumSize = [self.summaryLabel sizeThatFits:CGSizeMake(verW, CGFLOAT_MAX)];
            self.summaryLabel.frame = CGRectMake(padding, CGRectGetMaxY(self.versionLabel.frame) + 2,
                                                 verW, sumSize.height);
        }
        // Skip button below update button
        if (!self.skipButton.hidden) {
            CGSize skipSize = [self.skipButton sizeThatFits:CGSizeMake(btnW, CGFLOAT_MAX)];
            self.skipButton.frame = CGRectMake(CGRectGetMidX(self.updateButton.frame) - skipSize.width / 2,
                                               CGRectGetMaxY(self.updateButton.frame) + 2,
                                               skipSize.width, skipSize.height);
        }
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.versionLabel.text = nil;
    self.updateButton.hidden = NO;
    self.updateButton.enabled = YES;
    self.skipButton.hidden = YES;
    self.summaryLabel.hidden = YES;
    self.summaryLabel.text = nil;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.versionLabel.textColor = [HATheme secondaryTextColor];
    self.updateButton.backgroundColor = [HATheme accentColor];
}

@end
