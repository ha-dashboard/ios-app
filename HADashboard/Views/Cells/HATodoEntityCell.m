#import "HATodoEntityCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"

@interface HATodoEntityCell ()
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *itemCountDescLabel;
@end

@implementation HATodoEntityCell

- (void)setupSubviews {
    [super setupSubviews];
    self.stateLabel.hidden = YES;

    CGFloat padding = 10.0;

    // Icon
    self.iconLabel = [self labelWithFont:[HAIconMapper mdiFontOfSize:28] color:[HATheme primaryTextColor] lines:1];
    self.iconLabel.textAlignment = NSTextAlignmentCenter;

    // Item count (large number)
    self.countLabel = [self labelWithFont:[UIFont monospacedDigitSystemFontOfSize:24 weight:UIFontWeightBold] color:[HATheme primaryTextColor] lines:1];
    self.countLabel.textAlignment = NSTextAlignmentRight;

    // Description label
    self.itemCountDescLabel = [self labelWithFont:[UIFont systemFontOfSize:11] color:[HATheme secondaryTextColor] lines:1];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [self.iconLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.iconLabel.widthAnchor constraintEqualToConstant:32],
        [self.countLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-padding],
        [self.countLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2],
        [self.itemCountDescLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:padding],
        [self.itemCountDescLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:4],
    ]];
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];

    // Icon from entity or default
    NSString *iconName = [entity icon];
    if ([iconName hasPrefix:@"mdi:"]) iconName = [iconName substringFromIndex:4];
    NSString *glyph = iconName ? [HAIconMapper glyphForIconName:iconName] : nil;
    if (!glyph) glyph = [HAIconMapper glyphForIconName:@"clipboard-list"] ?: @"\U0001F4CB";
    self.iconLabel.text = glyph;

    // Item count from state
    NSString *state = entity.state;
    NSInteger count = [state integerValue];
    self.countLabel.text = [NSString stringWithFormat:@"%ld", (long)count];

    // Description
    if (count == 1) {
        self.itemCountDescLabel.text = @"1 item";
    } else {
        self.itemCountDescLabel.text = [NSString stringWithFormat:@"%ld items", (long)count];
    }

    self.contentView.backgroundColor = (count > 0) ? [HATheme onTintColor] : [HATheme cellBackgroundColor];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconLabel.text = nil;
    self.countLabel.text = nil;
    self.itemCountDescLabel.text = nil;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.countLabel.textColor = [HATheme primaryTextColor];
    self.itemCountDescLabel.textColor = [HATheme secondaryTextColor];
}

@end
