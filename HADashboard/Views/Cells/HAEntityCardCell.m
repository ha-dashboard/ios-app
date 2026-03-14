#import "HAAutoLayout.h"
#import "HAEntityCardCell.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HAEntityDisplayHelper.h"
#import "UIFont+HACompat.h"

@interface HAEntityCardCell ()
@property (nonatomic, strong) UILabel *entityIconLabel;
@property (nonatomic, strong) UILabel *entityNameLabel;
@property (nonatomic, strong) UILabel *entityStateLabel;
@end

@implementation HAEntityCardCell

+ (CGFloat)preferredHeight {
    return 100.0;
}

- (void)setupSubviews {
    [super setupSubviews];
    self.nameLabel.hidden = YES;
    self.stateLabel.hidden = YES;

    // Large centered icon
    self.entityIconLabel = [[UILabel alloc] init];
    self.entityIconLabel.font = [HAIconMapper mdiFontOfSize:40];
    self.entityIconLabel.textAlignment = NSTextAlignmentCenter;
    self.entityIconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.entityIconLabel];

    // Entity name (below icon)
    self.entityNameLabel = [[UILabel alloc] init];
    self.entityNameLabel.font = [UIFont ha_systemFontOfSize:14 weight:HAFontWeightMedium];
    self.entityNameLabel.textColor = [HATheme primaryTextColor];
    self.entityNameLabel.textAlignment = NSTextAlignmentCenter;
    self.entityNameLabel.numberOfLines = 1;
    self.entityNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.entityNameLabel];

    // Large state/attribute value
    self.entityStateLabel = [[UILabel alloc] init];
    self.entityStateLabel.font = [UIFont ha_monospacedDigitSystemFontOfSize:28 weight:HAFontWeightLight];
    self.entityStateLabel.textColor = [HATheme primaryTextColor];
    self.entityStateLabel.textAlignment = NSTextAlignmentCenter;
    self.entityStateLabel.numberOfLines = 1;
    self.entityStateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.entityStateLabel];

    HAActivateConstraints(@[
        HACon([self.entityIconLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12]),
        HACon([self.entityIconLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor]),

        HACon([self.entityStateLabel.topAnchor constraintEqualToAnchor:self.entityIconLabel.bottomAnchor constant:4]),
        HACon([self.entityStateLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor]),
        HACon([self.entityStateLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:8]),
        HACon([self.entityStateLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-8]),

        HACon([self.entityNameLabel.topAnchor constraintEqualToAnchor:self.entityStateLabel.bottomAnchor constant:2]),
        HACon([self.entityNameLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor]),
        HACon([self.entityNameLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:8]),
        HACon([self.entityNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-8]),
    ]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!HAAutoLayoutAvailable()) {
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat padding = 8.0;
        CGFloat maxW = w - padding * 2;

        CGSize iconSize = [self.entityIconLabel sizeThatFits:CGSizeMake(maxW, CGFLOAT_MAX)];
        self.entityIconLabel.frame = CGRectMake((w - iconSize.width) / 2.0, 12, iconSize.width, iconSize.height);

        CGSize stateSize = [self.entityStateLabel sizeThatFits:CGSizeMake(maxW, CGFLOAT_MAX)];
        self.entityStateLabel.frame = CGRectMake((w - stateSize.width) / 2.0, CGRectGetMaxY(self.entityIconLabel.frame) + 4,
                                                  stateSize.width, stateSize.height);

        CGSize nameSize = [self.entityNameLabel sizeThatFits:CGSizeMake(maxW, CGFLOAT_MAX)];
        self.entityNameLabel.frame = CGRectMake((w - nameSize.width) / 2.0, CGRectGetMaxY(self.entityStateLabel.frame) + 2,
                                                 nameSize.width, nameSize.height);
    }
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
    self.entityIconLabel.text = glyph ?: @"?";

    // state_color: default false, true for lights (matching HA frontend)
    BOOL stateColor = NO;
    if (props[@"state_color"]) {
        stateColor = [props[@"state_color"] boolValue];
    } else {
        stateColor = [[entity domain] isEqualToString:@"light"];
    }
    if (stateColor) {
        self.entityIconLabel.textColor = [HAEntityDisplayHelper iconColorForEntity:entity];
    } else {
        self.entityIconLabel.textColor = [HATheme secondaryTextColor];
    }

    // Name
    self.entityNameLabel.text = [HAEntityDisplayHelper displayNameForEntity:entity configItem:configItem nameOverride:nil];

    // State or attribute value
    NSString *attribute = props[@"attribute"];
    NSString *stateText;
    if ([attribute isKindOfClass:[NSString class]] && attribute.length > 0) {
        id attrVal = entity.attributes[attribute];
        stateText = (attrVal && attrVal != [NSNull null]) ? [NSString stringWithFormat:@"%@", attrVal] : @"—";
    } else {
        stateText = [HAEntityDisplayHelper formattedStateForEntity:entity decimals:1];
        stateText = [HAEntityDisplayHelper humanReadableState:stateText];
    }

    // Unit
    NSString *unit = props[@"unit"];
    if (![unit isKindOfClass:[NSString class]]) unit = entity.unitOfMeasurement;
    if (unit.length > 0 && ![[entity domain] isEqualToString:@"binary_sensor"]) {
        stateText = [NSString stringWithFormat:@"%@ %@", stateText, unit];
    }
    self.entityStateLabel.text = stateText;

    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.alpha = entity.isAvailable ? 1.0 : 0.5;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.entityIconLabel.text = nil;
    self.entityNameLabel.text = nil;
    self.entityStateLabel.text = nil;
    self.alpha = 1.0;
}

- (void)resetThemeColors {
    [super resetThemeColors];
    self.entityIconLabel.textColor = [HATheme secondaryTextColor];
    self.entityStateLabel.textColor = [HATheme primaryTextColor];
    self.entityNameLabel.textColor = [HATheme primaryTextColor];
}

@end
