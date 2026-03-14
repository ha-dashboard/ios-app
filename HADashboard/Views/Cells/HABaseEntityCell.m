#import "HAAutoLayout.h"
#import "NSString+HACompat.h"
#import "HABaseEntityCell.h"
#import "NSString+HACompat.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HAConnectionManager.h"
#import "HAHaptics.h"
#import "UIView+HAUtilities.h"
#import "UIViewController+HAAlert.h"
#import "UIFont+HACompat.h"

static const CGFloat kHeadingHeight = 28.0;
static const CGFloat kHeadingGap = 2.0;

@interface HABaseEntityCell () {
    UILabel *_headingIconLabel;
}
@property (nonatomic, assign) BOOL showsHeading;
@end

@implementation HABaseEntityCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.layer.cornerRadius = 14.0;
        self.contentView.layer.masksToBounds = YES;
        self.contentView.layer.borderWidth = 0.0;
        [self applyGradientBackground];

        // Heading icon: separate UILabel for MDI glyph on iOS 5
        // (iOS 5 can't render mixed fonts in a single attributed string)
        _headingIconLabel = [[UILabel alloc] init];
        _headingIconLabel.font = [HAIconMapper mdiFontOfSize:16];
        _headingIconLabel.textColor = [HATheme secondaryTextColor];
        _headingIconLabel.textAlignment = NSTextAlignmentCenter;
        _headingIconLabel.hidden = YES;
        [self addSubview:_headingIconLabel];

        // Heading label: added to the CELL (self), not contentView.
        // When visible, layoutSubviews pushes contentView down below it.
        self.headingLabel = [[UILabel alloc] init];
        self.headingLabel.font = [UIFont ha_systemFontOfSize:17 weight:HAFontWeightSemibold];
        self.headingLabel.textColor = [HATheme sectionHeaderColor];
        self.headingLabel.numberOfLines = 1;
        self.headingLabel.hidden = YES;
        [self addSubview:self.headingLabel];

        [self setupSubviews];
    }
    return self;
}

- (void)setupSubviews {
    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.font = [UIFont systemFontOfSize:13];
    self.nameLabel.textColor = [HATheme secondaryTextColor];
    self.nameLabel.numberOfLines = 1;
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.nameLabel];

    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.font = [UIFont boldSystemFontOfSize:16];
    self.stateLabel.textColor = [HATheme primaryTextColor];
    self.stateLabel.numberOfLines = 1;
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.stateLabel];

    CGFloat padding = 10.0;
    HAActivateConstraints(@[
        HACon([NSLayoutConstraint constraintWithItem:self.nameLabel attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.nameLabel attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.nameLabel attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.stateLabel attribute:NSLayoutAttributeLeading
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.stateLabel attribute:NSLayoutAttributeTrailing
            relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]),
        HACon([NSLayoutConstraint constraintWithItem:self.stateLabel attribute:NSLayoutAttributeTop
            relatedBy:NSLayoutRelationEqual toItem:self.nameLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:4]),
    ]);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (self.showsHeading) {
        CGFloat headingH = kHeadingHeight + kHeadingGap;
        // Position heading icon + title
        if (!_headingIconLabel.hidden) {
            _headingIconLabel.frame = CGRectMake(4, 0, 24, kHeadingHeight);
            self.headingLabel.frame = CGRectMake(30, 0, self.bounds.size.width - 38, kHeadingHeight);
        } else {
            self.headingLabel.frame = CGRectMake(4, 0, self.bounds.size.width - 8, kHeadingHeight);
        }
        // Push contentView below the heading
        self.contentView.frame = CGRectMake(0, headingH,
            self.bounds.size.width, self.bounds.size.height - headingH);
    } else {
        self.contentView.frame = self.bounds;
    }

    // Sync backgroundView (blur) with contentView frame so it doesn't cover headings.
    // UICollectionViewCell auto-sizes backgroundView to cell bounds; override here.
    if (self.backgroundView) {
        self.backgroundView.frame = self.contentView.frame;
    }

    if (!HAAutoLayoutAvailable()) {
        CGFloat padding = 10.0;
        CGFloat w = self.contentView.bounds.size.width;
        CGFloat labelW = w - padding * 2;
        CGSize nameSize = [self.nameLabel sizeThatFits:CGSizeMake(labelW, CGFLOAT_MAX)];
        self.nameLabel.frame = CGRectMake(padding, padding, labelW, nameSize.height);
        CGSize stateSize = [self.stateLabel sizeThatFits:CGSizeMake(labelW, CGFLOAT_MAX)];
        self.stateLabel.frame = CGRectMake(padding, CGRectGetMaxY(self.nameLabel.frame) + 4, labelW, stateSize.height);
    }
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    self.entity = entity;

    // Configure heading (from grid heading — e.g. "House Climate", "Ribbit")
    NSString *headingIcon = configItem.customProperties[@"headingIcon"];
    BOOL hasHeading = (configItem.displayName.length > 0 && headingIcon != nil);

    if (hasHeading) {
        NSString *iconName = headingIcon;
        if ([iconName hasPrefix:@"mdi:"]) iconName = [iconName substringFromIndex:4];
        NSString *glyph = [HAIconMapper glyphForIconName:iconName];
        if (glyph) {
            [HAIconMapper setIconGlyph:glyph iconSize:16 iconColor:[HATheme secondaryTextColor]
                onIconLabel:_headingIconLabel
                text:configItem.displayName
                textFont:[UIFont ha_systemFontOfSize:17 weight:HAFontWeightSemibold]
                textColor:[HATheme sectionHeaderColor]
                onTextLabel:self.headingLabel];
        } else {
            _headingIconLabel.hidden = YES;
            self.headingLabel.text = configItem.displayName;
        }
        self.headingLabel.hidden = NO;
        self.showsHeading = YES;
    } else {
        self.headingLabel.hidden = YES;
        self.showsHeading = NO;
    }
    [self setNeedsLayout];

    if (!entity) {
        self.nameLabel.text = configItem.entityId;
        self.stateLabel.text = @"—";
        self.contentView.alpha = 0.5;
        return;
    }

    self.contentView.alpha = entity.isAvailable ? 1.0 : 0.5;
    // When heading is present, displayName holds the heading text (shown as banner).
    // The entity name should come from the card-level nameOverride or friendly_name.
    NSString *cardNameOverride = configItem.customProperties[@"nameOverride"];
    if (cardNameOverride.length > 0) {
        self.nameLabel.text = cardNameOverride;
    } else if (hasHeading) {
        self.nameLabel.text = [entity friendlyName];
    } else {
        self.nameLabel.text = configItem.displayName ?: [entity friendlyName];
    }
    self.stateLabel.text = [self displayState];
}

- (NSString *)displayState {
    if (!self.entity) return @"—";
    return self.entity.state;
}

+ (CGFloat)headingHeight {
    return kHeadingHeight + kHeadingGap;
}

/// Configures the cell background color and opacity.
/// Blur backgroundView is applied externally by HADashboardViewController willDisplayCell.
- (void)applyGradientBackground {
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.contentView.opaque = NO;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.entity = nil;
    self.nameLabel.text = nil;
    self.stateLabel.text = nil;
    self.headingLabel.attributedText = nil;
    self.headingLabel.text = nil;
    self.headingLabel.hidden = YES;
    self.showsHeading = NO;
    self.contentView.alpha = 1.0;
    [self resetThemeColors];
}

- (void)resetThemeColors {
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.contentView.opaque = NO;
    self.nameLabel.textColor = [HATheme secondaryTextColor];
    self.stateLabel.textColor = [HATheme primaryTextColor];
    self.headingLabel.textColor = [HATheme sectionHeaderColor];
}

- (void)applyOnStateTint:(BOOL)isOn {
    self.contentView.backgroundColor = isOn ? [HATheme onTintColor] : [HATheme cellBackgroundColor];
}

#pragma mark - Factory Helpers

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color lines:(NSInteger)lines {
    UILabel *label = [[UILabel alloc] init];
    label.font = font;
    label.textColor = color;
    label.numberOfLines = lines;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:label];
    return label;
}

- (void)callService:(NSString *)service inDomain:(NSString *)domain {
    [self callService:service inDomain:domain withData:nil];
}

- (void)callService:(NSString *)service inDomain:(NSString *)domain withData:(NSDictionary *)data {
    if (!self.entity) return;
    [[HAConnectionManager sharedManager] callService:service
                                            inDomain:domain
                                            withData:data
                                            entityId:self.entity.entityId];
}

- (UIButton *)actionButtonWithTitle:(NSString *)title target:(id)target action:(SEL)action {
    UIButton *btn = HASystemButton();
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    btn.backgroundColor = [HATheme accentColor];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.layer.cornerRadius = 6.0;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:btn];
    return btn;
}

#pragma mark - Slider Helpers

- (void)sliderTouchDown:(UISlider *)sender {
    self.sliderDragging = YES;
}

- (void)sliderTouchUp:(UISlider *)sender {
    self.sliderDragging = NO;
}

#pragma mark - Option Sheet

- (void)presentOptionsWithTitle:(NSString *)title
                        options:(NSArray<NSString *> *)options
                        current:(NSString *)current
                     sourceView:(UIView *)sourceView
                        handler:(void(^)(NSString *selected))handler {
    UIViewController *vc = [self ha_parentViewController];
    if (!vc) return;

    NSMutableArray *titles = [NSMutableArray arrayWithCapacity:options.count];
    for (NSString *option in options) {
        BOOL isActive = [option isEqualToString:current];
        [titles addObject:isActive ? [NSString stringWithFormat:@"\u2713 %@", [option capitalizedString]] : [option capitalizedString]];
    }

    [vc ha_showActionSheetWithTitle:title
                        cancelTitle:@"Cancel"
                       actionTitles:titles
                         sourceView:sourceView
                            handler:^(NSInteger index) {
        [HAHaptics lightImpact];
        if (handler) handler(options[(NSUInteger)index]);
    }];
}

@end
