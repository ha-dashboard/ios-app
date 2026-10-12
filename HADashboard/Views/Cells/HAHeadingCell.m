#import "HAHeadingCell.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"

@interface HAHeadingCell ()
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *titleLabel;
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
        ]];
    }
    return self;
}

- (void)configureWithItem:(HADashboardConfigItem *)item {
    self.titleLabel.text = item.displayName;

    // HA heading card "heading_style: subtitle": smaller, secondary-coloured
    // text (hui-heading-card .content.subtitle). The default "title" style
    // keeps the section-header look.
    BOOL subtitle = [item.customProperties[@"heading_style"] isEqual:@"subtitle"];
    self.titleLabel.font = subtitle ? [UIFont systemFontOfSize:14 weight:UIFontWeightMedium]
                                    : [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = subtitle ? [HATheme secondaryTextColor] : [HATheme sectionHeaderColor];

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
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = nil;
    self.iconLabel.text = nil;
    self.iconLabel.textColor = [HATheme secondaryTextColor];
    self.titleLabel.textColor = [HATheme sectionHeaderColor];
}

@end
