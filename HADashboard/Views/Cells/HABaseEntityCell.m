#import "HABaseEntityCell.h"
#import "HAStrings.h"
#import "HAEntity.h"
#import "HAEntityDisplayHelper.h"
#import "HAStateLocalizer.h"
#import "HADashboardConfig.h"
#import "HATheme.h"
#import "HAIconMapper.h"
#import "HAConnectionManager.h"
#import "HAHaptics.h"
#import "UIView+HAUtilities.h"
#import "HAStrings.h"

static const CGFloat kHeadingHeight = 28.0;
static const CGFloat kHeadingGap = 2.0;

@interface HABaseEntityCell ()
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

        // Heading label: added to the CELL (self), not contentView.
        // When visible, layoutSubviews pushes contentView down below it.
        self.headingLabel = [[UILabel alloc] init];
        self.headingLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
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
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.nameLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.nameLabel attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.nameLabel attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTop multiplier:1 constant:padding]];

    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.stateLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.stateLabel attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.stateLabel attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationEqual toItem:self.nameLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:4]];

    // Fallback-card-type badge: pinned to the bottom of the card, independent
    // of whatever a subclass lays out above it. Lower constraint priorities
    // than the rest of this layout so a subclass's own bottom-anchored
    // controls (sliders, buttons) always win and the badge simply doesn't
    // appear to overlap — it's hidden by default (see configureWithEntity:).
    self.fallbackBadgeLabel = [[UILabel alloc] init];
    self.fallbackBadgeLabel.font = [UIFont systemFontOfSize:10];
    self.fallbackBadgeLabel.textColor = [HATheme tertiaryTextColor];
    self.fallbackBadgeLabel.numberOfLines = 1;
    self.fallbackBadgeLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.fallbackBadgeLabel.hidden = YES;
    self.fallbackBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.fallbackBadgeLabel];

    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.fallbackBadgeLabel attribute:NSLayoutAttributeLeading
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:padding]];
    [self.contentView addConstraint:[NSLayoutConstraint constraintWithItem:self.fallbackBadgeLabel attribute:NSLayoutAttributeTrailing
        relatedBy:NSLayoutRelationLessThanOrEqual toItem:self.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-padding]];
    NSLayoutConstraint *badgeBottom = [NSLayoutConstraint constraintWithItem:self.fallbackBadgeLabel attribute:NSLayoutAttributeBottom
        relatedBy:NSLayoutRelationEqual toItem:self.contentView attribute:NSLayoutAttributeBottom multiplier:1 constant:-6];
    badgeBottom.priority = UILayoutPriorityDefaultHigh; // 750: yields to a subclass's own required bottom constraints
    NSLayoutConstraint *badgeBelowState = [NSLayoutConstraint constraintWithItem:self.fallbackBadgeLabel attribute:NSLayoutAttributeTop
        relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:self.stateLabel attribute:NSLayoutAttributeBottom multiplier:1 constant:4];
    [self.contentView addConstraint:badgeBottom];
    [self.contentView addConstraint:badgeBelowState];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    if (self.showsHeading) {
        CGFloat headingH = kHeadingHeight + kHeadingGap;
        // Heading sits at top of cell bounds, no card background
        self.headingLabel.frame = CGRectMake(4, 0, self.bounds.size.width - 8, kHeadingHeight);
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
}

- (void)configureWithEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem {
    self.entity = entity;

    // Fallback-card-type badge: only set by the parser when a custom:* card
    // it doesn't natively understand rendered generically instead of vanishing
    // (GitHub #19) — see HADashboardConfigItem.fallbackCardType. The parser
    // already leaves this nil when "Show Unsupported Cards" is off, so no
    // separate setting check is needed here.
    NSString *fallbackType = configItem.fallbackCardType;
    if (fallbackType.length > 0) {
        self.fallbackBadgeLabel.text = fallbackType;
        self.fallbackBadgeLabel.hidden = NO;
        self.fallbackBadgeLabel.accessibilityLabel = [NSString stringWithFormat:
            HALocalizedString(@"card.fallbackBadge.accessibilityFormat",
                @"VoiceOver label for the small badge on a generically-rendered card standing in for an unsupported custom card type. %1$@ is the raw Lovelace card type, e.g. custom:bubble-card."),
            fallbackType];
    } else {
        self.fallbackBadgeLabel.text = nil;
        self.fallbackBadgeLabel.hidden = YES;
        self.fallbackBadgeLabel.accessibilityLabel = nil;
    }

    // Configure heading (from grid heading — e.g. "House Climate", "Ribbit")
    NSString *headingIcon = configItem.customProperties[@"headingIcon"];
    BOOL hasHeading = (configItem.displayName.length > 0 && headingIcon != nil);

    if (hasHeading) {
        NSString *iconName = headingIcon;
        if ([iconName hasPrefix:@"mdi:"]) iconName = [iconName substringFromIndex:4];
        NSString *glyph = [HAIconMapper glyphForIconName:iconName];
        if (glyph) {
            NSMutableAttributedString *heading = [[NSMutableAttributedString alloc] initWithString:glyph
                attributes:@{NSFontAttributeName: [HAIconMapper mdiFontOfSize:16],
                             NSForegroundColorAttributeName: [HATheme secondaryTextColor]}];
            [heading appendAttributedString:[[NSAttributedString alloc] initWithString:
                [NSString stringWithFormat:@"  %@", configItem.displayName]
                attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold],
                             NSForegroundColorAttributeName: [HATheme sectionHeaderColor]}]];
            self.headingLabel.attributedText = heading;
        } else {
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
        self.stateLabel.text = HALocalizedString(@"cell.base.no_value", @"State label fallback in the base entity cell, shown when no display state is available.");
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
    // Default fallback used by any subclass that doesn't override this —
    // route through the shared helper (which in turn routes through
    // HAStateLocalizer) rather than returning the raw HA state verbatim.
    // See docs/plans/i18n-plan.md §2.5/§2.7.
    return [HAEntityDisplayHelper formattedStateForEntity:self.entity decimals:1];
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
    self.fallbackBadgeLabel.text = nil;
    self.fallbackBadgeLabel.hidden = YES;
    self.fallbackBadgeLabel.accessibilityLabel = nil;
    [self resetThemeColors];
}

- (void)resetThemeColors {
    self.contentView.backgroundColor = [HATheme cellBackgroundColor];
    self.contentView.opaque = NO;
    self.nameLabel.textColor = [HATheme secondaryTextColor];
    self.stateLabel.textColor = [HATheme primaryTextColor];
    self.headingLabel.textColor = [HATheme sectionHeaderColor];
    self.fallbackBadgeLabel.textColor = [HATheme tertiaryTextColor];
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
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
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
    [self presentOptionsWithTitle:title options:options current:current sourceView:sourceView
                            domain:nil attr:nil handler:handler];
}

- (void)presentOptionsWithTitle:(NSString *)title
                        options:(NSArray<NSString *> *)options
                        current:(NSString *)current
                     sourceView:(UIView *)sourceView
                         domain:(NSString *)domain
                           attr:(NSString *)attr
                        handler:(void(^)(NSString *selected))handler {
    UIViewController *vc = [self ha_parentViewController];
    if (!vc) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *option in options) {
        NSString *displayTitle = (domain.length > 0 && attr.length > 0)
            ? [[HAStateLocalizer sharedLocalizer] localizedAttributeValueForDomain:domain deviceClass:nil attr:attr value:option]
            : [option capitalizedString];
        UIAlertAction *action = [UIAlertAction actionWithTitle:displayTitle
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *a) {
            [HAHaptics lightImpact];
            if (handler) handler(option);
        }];
        if ([option isEqualToString:current]) {
            [action setValue:@YES forKey:@"checked"];
        }
        [sheet addAction:action];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:HALocalizedString(@"action.cancel", @"Cancel button in alerts and action sheets throughout Settings.") style:UIAlertActionStyleCancel handler:nil]];

    if (sourceView) {
        sheet.popoverPresentationController.sourceView = sourceView;
        sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    }
    [vc presentViewController:sheet animated:YES completion:nil];
}

@end
