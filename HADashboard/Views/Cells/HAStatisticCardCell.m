#import "HAAutoLayout.h"
#import "HAStatisticCardCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"
#import "UIFont+HACompat.h"

@interface HAStatisticCardCell ()
@property (nonatomic, strong) UILabel *statIconLabel;
@property (nonatomic, strong) UILabel *statValueLabel;
@property (nonatomic, strong) UILabel *statTypeLabel;
@property (nonatomic, strong) UILabel *statNameLabel;
@end

@implementation HAStatisticCardCell

+ (CGFloat)preferredHeight {
    return 100.0;
}

- (void)setupSubviews {
    [super setupSubviews];
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    // Icon (top-left)
    self.statIconLabel = [[UILabel alloc] init];
    self.statIconLabel.font = [HAIconMapper mdiFontOfSize:24];
    self.statIconLabel.textColor = [HATheme secondaryTextColor];
    self.statIconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.statIconLabel];

    // Large value (centered)
    self.statValueLabel = [[UILabel alloc] init];
    self.statValueLabel.font = [UIFont ha_monospacedDigitSystemFontOfSize:32 weight:HAFontWeightLight];
    self.statValueLabel.textColor = [HATheme primaryTextColor];
    self.statValueLabel.textAlignment = NSTextAlignmentCenter;
    self.statValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.statValueLabel];

    // Stat type label (e.g. "Mean", "Max")
    self.statTypeLabel = [[UILabel alloc] init];
    self.statTypeLabel.font = [UIFont ha_systemFontOfSize:11 weight:HAFontWeightMedium];
    self.statTypeLabel.textColor = [HATheme secondaryTextColor];
    self.statTypeLabel.textAlignment = NSTextAlignmentCenter;
    self.statTypeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.statTypeLabel];

    // Entity name (below stat type)
    self.statNameLabel = [[UILabel alloc] init];
    self.statNameLabel.font = [UIFont ha_systemFontOfSize:12 weight:HAFontWeightRegular];
    self.statNameLabel.textColor = [HATheme secondaryTextColor];
    self.statNameLabel.textAlignment = NSTextAlignmentCenter;
    self.statNameLabel.numberOfLines = 1;
    self.statNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.statNameLabel];

    HAActivateConstraints(@[
        HACon([self.statIconLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12]),
        HACon([self.statIconLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12]),

        HACon([self.statValueLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor]),
        HACon([self.statValueLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16]),

        HACon([self.statTypeLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor]),
        HACon([self.statTypeLabel.topAnchor constraintEqualToAnchor:self.statValueLabel.bottomAnchor constant:2]),

        HACon([self.statNameLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor]),
        HACon([self.statNameLabel.topAnchor constraintEqualToAnchor:self.statTypeLabel.bottomAnchor constant:2]),
        HACon([self.statNameLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:8]),
        HACon([self.statNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-8]),
    ]);
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    [super configureWithEntity:entity configItem:configItem];
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    if (!entity) return;

    NSDictionary *props = configItem.customProperties;

    // Icon
    NSString *iconName = props[@"icon"];
    NSString *glyph = nil;
    if ([iconName isKindOfClass:[NSString class]]) {
        if ([iconName hasPrefix:@"mdi:"]) iconName = [iconName substringFromIndex:4];
        glyph = [HAIconMapper glyphForIconName:iconName];
    }
    if (!glyph) glyph = [HAEntityDisplayHelper iconGlyphForEntity:entity];
    self.statIconLabel.text = glyph ?: @"?";

    // Name
    self.statNameLabel.text = [HAEntityDisplayHelper displayNameForEntity:entity configItem:configItem nameOverride:nil];

    // Stat type
    NSString *statType = props[@"stat_type"] ?: @"state";
    NSString *typeDisplay = [statType capitalizedString];
    self.statTypeLabel.text = typeDisplay;

    // Value: for "state" type, show current state. For others, show current state
    // as fallback since we don't have the statistics API yet.
    NSString *stateText = [HAEntityDisplayHelper formattedStateForEntity:entity decimals:1];
    NSString *unit = props[@"unit"];
    if (![unit isKindOfClass:[NSString class]]) unit = entity.unitOfMeasurement;
    if (unit.length > 0) {
        stateText = [NSString stringWithFormat:@"%@ %@", stateText, unit];
    }
    self.statValueLabel.text = stateText;

    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.alpha = entity.isAvailable ? 1.0 : 0.5;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        // Icon top-left
        self.statIconLabel.frame = CGRectMake(12, 12, 28, 28);
        // Value centered
        CGSize valSize = [self.statValueLabel sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)];
        self.statValueLabel.frame = CGRectMake((w - valSize.width) / 2, 16, valSize.width, valSize.height);
        // Stat type below value
        CGSize typeSize = [self.statTypeLabel sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)];
        CGFloat typeY = CGRectGetMaxY(self.statValueLabel.frame) + 2;
        self.statTypeLabel.frame = CGRectMake((w - typeSize.width) / 2, typeY, typeSize.width, typeSize.height);
        // Name below type
        CGFloat nameW = w - 16;
        CGSize nameSize = [self.statNameLabel sizeThatFits:CGSizeMake(nameW, CGFLOAT_MAX)];
        CGFloat nameY = CGRectGetMaxY(self.statTypeLabel.frame) + 2;
        self.statNameLabel.frame = CGRectMake((w - nameSize.width) / 2, nameY, nameSize.width, nameSize.height);
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.statIconLabel.text = nil;
    self.statValueLabel.text = nil;
    self.statTypeLabel.text = nil;
    self.statNameLabel.text = nil;
    self.alpha = 1.0;
}

@end
