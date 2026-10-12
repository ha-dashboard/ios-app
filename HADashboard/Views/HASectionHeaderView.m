#import "HASectionHeaderView.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HALovelaceParser.h"
#import "HAHeadingBadgesView.h"

@interface HASectionHeaderView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingWithIcon;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingNoIcon;
@property (nonatomic, strong) NSLayoutConstraint *iconLeading;
@property (nonatomic, strong) NSLayoutConstraint *titleTrailing;
@property (nonatomic, strong) HAHeadingBadgesView *badgesView;
@property (nonatomic, strong) NSLayoutConstraint *badgesTrailing;
@property (nonatomic, strong) NSLayoutConstraint *titleBeforeBadges;
@property (nonatomic, strong) NSLayoutConstraint *titleMinWidth;
@property (nonatomic, strong) UITapGestureRecognizer *headingTap;
@property (nonatomic, copy) NSDictionary *tapAction;
@end

@implementation HASectionHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupSubviews];
    }
    return self;
}

- (void)setupSubviews {
    // Icon label (MDI font glyph)
    self.iconLabel = [[UILabel alloc] init];
    self.iconLabel.font = [HAIconMapper mdiFontOfSize:16];
    self.iconLabel.textColor = [HATheme secondaryTextColor];
    self.iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.iconLabel];

    // Title label
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [HATheme sectionHeaderColor];
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.titleLabel];

    // Layout: icon (fixed 24pt width, glyph leading-aligned) | 4pt gap | title —
    // the same geometry as a standalone heading row (HAHeadingCell), so the
    // section's first heading and any later heading line up.
    // Two title leading constraints: with-icon (after icon) and no-icon (flush left).
    _contentInset = 8.0;
    self.iconLeading = [self.iconLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:_contentInset];
    self.titleTrailing = [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-_contentInset];
    [NSLayoutConstraint activateConstraints:@[
        self.iconLeading,
        [self.iconLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.iconLabel.widthAnchor constraintEqualToConstant:24],

        self.titleTrailing,
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
    self.titleLeadingWithIcon = [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconLabel.trailingAnchor constant:4];
    self.titleLeadingNoIcon = [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:_contentInset];
    self.titleLeadingNoIcon.active = YES;

    // Heading badges at the end of the line (hui-heading-card .badges). While
    // they show, the title ends before them instead of at the trailing inset.
    self.badgesView = [[HAHeadingBadgesView alloc] init];
    self.badgesView.translatesAutoresizingMaskIntoConstraints = NO;
    self.badgesView.hidden = YES;
    [self.badgesView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.badgesView setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 5 forAxis:UILayoutConstraintAxisHorizontal];
    [self addSubview:self.badgesView];
    self.badgesTrailing = [self.badgesView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-_contentInset];
    [NSLayoutConstraint activateConstraints:@[
        self.badgesTrailing,
        [self.badgesView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.badgesView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    self.titleBeforeBadges = [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.badgesView.leadingAnchor constant:-8];
    self.titleMinWidth = [self.titleLabel.widthAnchor constraintGreaterThanOrEqualToConstant:0];
    self.titleMinWidth.priority = UILayoutPriorityDefaultHigh + 10;

    self.headingTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(headingTapped:)];
    self.headingTap.delegate = self;
    self.headingTap.enabled = NO;
    [self addGestureRecognizer:self.headingTap];
}

- (void)setContentInset:(CGFloat)contentInset {
    _contentInset = contentInset;
    self.iconLeading.constant = contentInset;
    self.titleLeadingNoIcon.constant = contentInset;
    self.titleTrailing.constant = -contentInset;
    self.badgesTrailing.constant = -contentInset;
}

- (void)configureWithSection:(HADashboardConfigSection *)section {
    [self configureWithSection:section badgeConfigs:nil entities:nil];
}

- (void)configureWithSection:(HADashboardConfigSection *)section
                badgeConfigs:(NSArray<NSDictionary *> *)badgeConfigs
                    entities:(NSDictionary<NSString *, HAEntity *> *)entities {
    // An actionable heading tap_action shows HA's chevron (ha-icon-next) after the title
    NSDictionary *tapAction = section.customProperties[HAHeadingTapActionKey];
    self.tapAction = [tapAction isKindOfClass:[NSDictionary class]] ? tapAction : nil;
    self.headingTap.enabled = (self.tapAction != nil);
    NSString *chevron = self.tapAction ? [HAIconMapper glyphForIconName:@"chevron-right"] : nil;
    if (chevron.length > 0 && section.title.length > 0) {
        UIColor *color = [HATheme sectionHeaderColor];
        NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:section.title
            attributes:@{NSFontAttributeName: self.titleLabel.font, NSForegroundColorAttributeName: color}];
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\u00a0" stringByAppendingString:chevron]
            attributes:@{NSFontAttributeName: [HAIconMapper mdiFontOfSize:18], NSForegroundColorAttributeName: color}]];
        self.titleLabel.attributedText = title;
    } else {
        self.titleLabel.text = section.title;
    }

    [self.badgesView configureWithBadgeConfigs:badgeConfigs entities:entities];
    BOOL showBadges = self.badgesView.contentWidth > 0;
    self.badgesView.hidden = !showBadges;
    self.titleTrailing.active = !showBadges;
    self.titleBeforeBadges.active = showBadges;
    self.titleMinWidth.constant = showBadges ? MIN(ceil(self.titleLabel.intrinsicContentSize.width), 150.0) : 0;
    self.titleMinWidth.active = showBadges;

    // Try icon from section config, then from card type as domain hint
    NSString *glyph = [HAIconMapper glyphForIconName:section.icon];
    if (!glyph && section.cardType) {
        if ([section.cardType isEqualToString:@"thermostat"]) {
            glyph = [HAIconMapper glyphForDomain:@"climate"];
        } else if ([section.cardType isEqualToString:@"weather-forecast"]) {
            glyph = [HAIconMapper glyphForDomain:@"weather"];
        } else if ([section.cardType isEqualToString:@"media-control"]) {
            glyph = [HAIconMapper glyphForDomain:@"media_player"];
        }
    }

    if (glyph) {
        self.iconLabel.text = glyph;
        self.iconLabel.hidden = NO;
        self.titleLeadingNoIcon.active = NO;
        self.titleLeadingWithIcon.active = YES;
    } else {
        self.iconLabel.text = nil;
        self.iconLabel.hidden = YES;
        self.titleLeadingWithIcon.active = NO;
        self.titleLeadingNoIcon.active = YES;
    }
}

- (void)setBadgeActionBlock:(void (^)(HAEntity *, NSDictionary *, NSString *))badgeActionBlock {
    self.badgesView.badgeActionBlock = badgeActionBlock;
}

- (void (^)(HAEntity *, NSDictionary *, NSString *))badgeActionBlock {
    return self.badgesView.badgeActionBlock;
}

- (void)headingTapped:(UITapGestureRecognizer *)gesture {
    if (self.tapAction && self.headingTapBlock) self.headingTapBlock(self.tapAction);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // A badge's own tap is not the heading's (HA: badges sit outside .content)
    return !(touch.view && [touch.view isDescendantOfView:self.badgesView]);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.attributedText = nil;
    self.titleLabel.text = nil;
    [self.badgesView configureWithBadgeConfigs:nil entities:nil];
    self.badgesView.hidden = YES;
    self.badgesView.badgeActionBlock = nil;
    self.titleBeforeBadges.active = NO;
    self.titleMinWidth.active = NO;
    self.titleTrailing.active = YES;
    self.headingTapBlock = nil;
    self.tapAction = nil;
    self.headingTap.enabled = NO;
    self.iconLabel.text = nil;
    self.iconLabel.hidden = YES;
    self.titleLabel.textColor = [HATheme sectionHeaderColor];
    self.iconLabel.textColor = [HATheme secondaryTextColor];
}

@end
