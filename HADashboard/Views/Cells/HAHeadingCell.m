#import "HAHeadingCell.h"
#import "HADashboardConfig.h"
#import "HALovelaceParser.h"
#import "HAHeadingBadgesView.h"
#import "HATheme.h"
#import "HAIconMapper.h"

@interface HAHeadingCell ()
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) HAHeadingBadgesView *badgesView;
/// Active only while badges show, so a badge-less heading keeps its full title width
@property (nonatomic, strong) NSLayoutConstraint *titleBeforeBadges;
@property (nonatomic, strong) NSLayoutConstraint *titleMinWidth;
@end

@implementation HAHeadingCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Match HASectionHeaderView style for visual consistency
        self.iconLabel = [[UILabel alloc] init];
        self.iconLabel.font = [HAIconMapper mdiFontOfSize:16];
        self.iconLabel.textColor = [HATheme secondaryTextColor];
        self.iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.iconLabel];

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        self.titleLabel.textColor = [HATheme sectionHeaderColor];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.titleLabel];

        // Heading badges at the end of the line (hui-heading-card .badges)
        self.badgesView = [[HAHeadingBadgesView alloc] init];
        self.badgesView.translatesAutoresizingMaskIntoConstraints = NO;
        self.badgesView.hidden = YES;
        [self.badgesView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        // The title truncates first; badges give way only below its minimum width
        [self.badgesView setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 5 forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:self.badgesView];

        // 8pt internal padding from the item's leading edge. HASectionHeaderView uses
        // the same icon/title geometry (its contentInset), so a section's header and
        // any later standalone heading line up.
        [NSLayoutConstraint activateConstraints:@[
            [self.iconLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:8],
            [self.iconLabel.widthAnchor constraintEqualToConstant:24],
            [self.iconLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconLabel.trailingAnchor constant:4],
            [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.badgesView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
            [self.badgesView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.badgesView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        ]];
        self.titleBeforeBadges = [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.badgesView.leadingAnchor constant:-8];
        // hui-heading-card: the title keeps up to 150px before the badges shrink
        self.titleMinWidth = [self.titleLabel.widthAnchor constraintGreaterThanOrEqualToConstant:0];
        self.titleMinWidth.priority = UILayoutPriorityDefaultHigh + 10;
    }
    return self;
}

- (void)configureWithItem:(HADashboardConfigItem *)item {
    [self configureWithItem:item badgeConfigs:nil entities:nil];
}

- (void)configureWithItem:(HADashboardConfigItem *)item
             badgeConfigs:(NSArray<NSDictionary *> *)badgeConfigs
                 entities:(NSDictionary<NSString *, HAEntity *> *)entities {
    // HA heading card "heading_style: subtitle": smaller, secondary-coloured
    // text (hui-heading-card .content.subtitle). The default "title" style
    // keeps the section-header look.
    BOOL subtitle = [item.customProperties[@"heading_style"] isEqual:@"subtitle"];
    self.titleLabel.font = subtitle ? [UIFont systemFontOfSize:14 weight:UIFontWeightMedium]
                                    : [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = subtitle ? [HATheme secondaryTextColor] : [HATheme sectionHeaderColor];

    // An actionable heading tap_action shows HA's chevron (ha-icon-next) after the title
    NSString *chevron = item.customProperties[HAHeadingTapActionKey]
        ? [HAIconMapper glyphForIconName:@"chevron-right"] : nil;
    if (chevron.length > 0 && item.displayName.length > 0) {
        NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:item.displayName
            attributes:@{NSFontAttributeName: self.titleLabel.font, NSForegroundColorAttributeName: self.titleLabel.textColor}];
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\u00a0" stringByAppendingString:chevron]
            attributes:@{NSFontAttributeName: [HAIconMapper mdiFontOfSize:18], NSForegroundColorAttributeName: self.titleLabel.textColor}]];
        self.titleLabel.attributedText = title;
    } else {
        self.titleLabel.text = item.displayName;
    }

    // Try to get icon from customProperties or default
    NSString *icon = item.customProperties[@"icon"];
    if ([icon isKindOfClass:[NSString class]]) {
        // Strip "mdi:" prefix
        NSString *iconName = icon;
        if ([iconName hasPrefix:@"mdi:"]) iconName = [iconName substringFromIndex:4];
        self.iconLabel.text = [HAIconMapper glyphForIconName:iconName];
    } else {
        self.iconLabel.text = nil;
    }

    [self.badgesView configureWithBadgeConfigs:badgeConfigs entities:entities];
    BOOL showBadges = self.badgesView.contentWidth > 0;
    self.badgesView.hidden = !showBadges;
    self.titleBeforeBadges.active = showBadges;
    self.titleMinWidth.constant = showBadges ? MIN(ceil(self.titleLabel.intrinsicContentSize.width), 150.0) : 0;
    self.titleMinWidth.active = showBadges;
}

- (void)setBadgeActionBlock:(void (^)(HAEntity *, NSDictionary *, NSString *))badgeActionBlock {
    self.badgesView.badgeActionBlock = badgeActionBlock;
}

- (void (^)(HAEntity *, NSDictionary *, NSString *))badgeActionBlock {
    return self.badgesView.badgeActionBlock;
}

- (BOOL)badgesContainPoint:(CGPoint)point {
    if (self.badgesView.hidden) return NO;
    CGPoint local = [self convertPoint:point toView:self.badgesView];
    for (UIView *badge in self.badgesView.badgeViews) {
        if (CGRectContainsPoint(badge.frame, local)) return YES;
    }
    return NO;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.attributedText = nil;
    self.titleLabel.text = nil;
    self.iconLabel.text = nil;
    self.iconLabel.textColor = [HATheme secondaryTextColor];
    self.titleLabel.textColor = [HATheme sectionHeaderColor];
    [self.badgesView configureWithBadgeConfigs:nil entities:nil];
    self.badgesView.hidden = YES;
    self.badgesView.badgeActionBlock = nil;
    self.titleBeforeBadges.active = NO;
    self.titleMinWidth.active = NO;
}

@end
