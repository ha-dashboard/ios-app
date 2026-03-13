#import "HAAutoLayout.h"
#import "HACounterEntityCell.h"
#import "HAEntity.h"
#import "HAConnectionManager.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAHaptics.h"
#import "UIFont+HACompat.h"

@interface HACounterEntityCell ()
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UIButton *incrementButton;
@property (nonatomic, strong) UIButton *decrementButton;
@property (nonatomic, strong) UIButton *resetButton;
@end

@implementation HACounterEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Value label (large, prominent)
    self.valueLabel = [self labelWithFont:[UIFont ha_monospacedDigitSystemFontOfSize:28 weight:HAFontWeightBold]
                                    color:[HATheme primaryTextColor] lines:1];
    self.valueLabel.textAlignment = NSTextAlignmentRight;

    CGFloat buttonSize = 32.0;
    CGFloat buttonSpacing = 6.0;

    // Decrement button
    self.decrementButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.decrementButton setTitle:@"\u2212" forState:UIControlStateNormal]; // minus sign
    self.decrementButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.decrementButton.backgroundColor = [HATheme destructiveColor];
    [self.decrementButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.decrementButton.layer.cornerRadius = buttonSize / 2.0;
    self.decrementButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.decrementButton addTarget:self action:@selector(decrementTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.decrementButton];

    // Increment button
    self.incrementButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.incrementButton setTitle:@"+" forState:UIControlStateNormal];
    self.incrementButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.incrementButton.backgroundColor = [HATheme successColor];
    [self.incrementButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.incrementButton.layer.cornerRadius = buttonSize / 2.0;
    self.incrementButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.incrementButton addTarget:self action:@selector(incrementTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.incrementButton];

    // Reset button
    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetButton setTitle:@"Reset" forState:UIControlStateNormal];
    self.resetButton.titleLabel.font = [UIFont systemFontOfSize:11];
    self.resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.resetButton];

    // Value label: top-right
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.valueLabel attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.valueLabel attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]),
    ]);

    // Buttons: bottom row
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.incrementButton attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.incrementButton attribute:NSLayoutAttributeBottom
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.incrementButton attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonSize]),
        HACon([NSLayoutConstraint constraintWithItem:self.incrementButton attribute:NSLayoutAttributeHeight
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonSize]),
        HACon([NSLayoutConstraint constraintWithItem:self.decrementButton attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.incrementButton attribute:NSLayoutAttributeLeading multiplier:1 constant:-buttonSpacing]),
        HACon([NSLayoutConstraint constraintWithItem:self.decrementButton attribute:NSLayoutAttributeBottom
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.decrementButton attribute:NSLayoutAttributeWidth
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonSize]),
        HACon([NSLayoutConstraint constraintWithItem:self.decrementButton attribute:NSLayoutAttributeHeight
            relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonSize]),
    ]);

    // Reset button: bottom-left
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.resetButton attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.resetButton attribute:NSLayoutAttributeBottom
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-padding]),
    ]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat padding = 10.0;
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat buttonSize = 32.0;
        CGFloat buttonSpacing = 6.0;

        CGSize valSize = [self.valueLabel sizeThatFits:CGSizeMake(w - padding * 2, CGFLOAT_MAX)];
        self.valueLabel.frame = CGRectMake(w - padding - valSize.width, padding, valSize.width, valSize.height);

        self.incrementButton.frame = CGRectMake(w - padding - buttonSize, h - padding - buttonSize, buttonSize, buttonSize);
        self.decrementButton.frame = CGRectMake(CGRectGetMinX(self.incrementButton.frame) - buttonSpacing - buttonSize,
                                                 h - padding - buttonSize, buttonSize, buttonSize);

        CGSize resetSize = [self.resetButton sizeThatFits:CGSizeMake(100, CGFLOAT_MAX)];
        self.resetButton.frame = CGRectMake(padding, h - padding - resetSize.height, resetSize.width, resetSize.height);
    }
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    self.valueLabel.text = [NSString stringWithFormat:@"%ld", (long)[entity counterValue]];

    BOOL available = entity.isAvailable;
    NSInteger value = [entity counterValue];
    // Clamp buttons at min/max if defined
    NSNumber *minAttr = entity.attributes[@"minimum"];
    NSNumber *maxAttr = entity.attributes[@"maximum"];
    BOOL atMin = ([minAttr isKindOfClass:[NSNumber class]] && value <= [minAttr integerValue]);
    BOOL atMax = ([maxAttr isKindOfClass:[NSNumber class]] && value >= [maxAttr integerValue]);
    self.incrementButton.enabled = available && !atMax;
    self.decrementButton.enabled = available && !atMin;
    self.resetButton.enabled = available;
}

#pragma mark - Actions

- (void)incrementTapped {
    [HAHaptics lightImpact];
    [self callService:@"increment" inDomain:HAEntityDomainCounter];
}

- (void)decrementTapped {
    [HAHaptics lightImpact];
    [self callService:@"decrement" inDomain:HAEntityDomainCounter];
}

- (void)resetTapped {
    [HAHaptics mediumImpact];
    [self callService:@"reset" inDomain:HAEntityDomainCounter];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.valueLabel.text = nil;
    self.valueLabel.textColor = [HATheme primaryTextColor];
    self.decrementButton.backgroundColor = [HATheme destructiveColor];
    self.incrementButton.backgroundColor = [HATheme successColor];
}

@end
