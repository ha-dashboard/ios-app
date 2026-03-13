#import "HAAutoLayout.h"
#import "HAHeadingCell.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "UIFont+HACompat.h"

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
        self.titleLabel.font = [UIFont ha_systemFontOfSize:17 weight:HAFontWeightSemibold];
        self.titleLabel.textColor = [HATheme sectionHeaderColor];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.titleLabel];

        HAActivateConstraints(@[
            HACon([self.iconLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16]),
            HACon([self.iconLabel.widthAnchor constraintEqualToConstant:24]),
            HACon([self.iconLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor]),
            HACon([self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconLabel.trailingAnchor constant:4]),
            HACon([self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16]),
            HACon([self.titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor]),
        ]);
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat h = self.contentView.bounds.size.height;
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat midY = h / 2.0;
        CGFloat iconW = 24.0;
        self.iconLabel.frame = CGRectMake(16, midY - 10, iconW, 20);
        CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(w - 16 - iconW - 4 - 16, CGFLOAT_MAX)];
        self.titleLabel.frame = CGRectMake(16 + iconW + 4, midY - titleSize.height / 2.0,
                                           titleSize.width, titleSize.height);
    }
}

- (void)configureWithItem:(HADashboardConfigItem *)item {
    self.titleLabel.text = item.displayName;

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
