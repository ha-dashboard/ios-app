#import "HAHeadingBadgesView.h"
#import "HAAction.h"
#import "HAEntity.h"
#import "HAEntityDisplayHelper.h"
#import "HAIconMapper.h"
#import "HATheme.h"

// ha-heading-badge / hui-heading-card styles
static const CGFloat kHeadingBadgeIconSize = 16.0; // --mdc-icon-size: 16px
static const CGFloat kHeadingBadgeIconGap = 3.0;   // .heading-badge gap: 3px
static const CGFloat kHeadingBadgeSpacing = 8.0;   // .badges-row gap: var(--ha-space-2)
static const CGFloat kHeadingBadgeFontSize = 14.0; // --ha-font-size-m, weight 400

@interface HAHeadingBadgesView ()
@property (nonatomic, strong) NSMutableArray<UIView *> *mutableBadgeViews;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *badgeWidths;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *badgeConfigs;
@property (nonatomic, strong) NSMutableArray *badgeEntities; // HAEntity or NSNull (missing entity)
@property (nonatomic, assign, readwrite) CGFloat contentWidth;
@end

@implementation HAHeadingBadgesView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = YES;
        _mutableBadgeViews = [NSMutableArray array];
        _badgeWidths = [NSMutableArray array];
        _badgeConfigs = [NSMutableArray array];
        _badgeEntities = [NSMutableArray array];
    }
    return self;
}

- (NSArray<UIView *> *)badgeViews {
    return [self.mutableBadgeViews copy];
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(self.contentWidth, UIViewNoIntrinsicMetric);
}

- (void)configureWithBadgeConfigs:(NSArray<NSDictionary *> *)configs
                         entities:(NSDictionary<NSString *, HAEntity *> *)entities {
    for (UIView *v in self.mutableBadgeViews) [v removeFromSuperview];
    [self.mutableBadgeViews removeAllObjects];
    [self.badgeWidths removeAllObjects];
    [self.badgeConfigs removeAllObjects];
    [self.badgeEntities removeAllObjects];

    UIFont *textFont = [UIFont systemFontOfSize:kHeadingBadgeFontSize];
    CGFloat total = 0;
    for (NSDictionary *config in configs) {
        if (![config isKindOfClass:[NSDictionary class]]) continue;
        NSString *entityId = [config[@"entity"] isKindOfClass:[NSString class]] ? config[@"entity"] : nil;
        HAEntity *entity = entityId ? entities[entityId] : nil;

        NSString *glyph = nil;
        UIColor *iconColor = [HATheme secondaryTextColor];
        NSString *text = nil;
        NSString *name = nil;
        if (!entity) {
            // hui-entity-heading-badge error state: red alert icon and "-"
            glyph = [HAIconMapper glyphForIconName:@"alert-circle"];
            iconColor = [HATheme destructiveColor];
            text = @"-";
            name = entityId;
        } else {
            NSString *configName = [config[@"name"] isKindOfClass:[NSString class]] ? config[@"name"] : nil;
            name = configName.length > 0 ? configName
                : [HAEntityDisplayHelper displayNameForEntity:entity entityId:entity.entityId section:nil];
            if ([config[@"show_icon"] boolValue]) {
                NSString *iconName = [config[@"icon"] isKindOfClass:[NSString class]] ? config[@"icon"] : nil;
                if (iconName.length > 0) glyph = [HAIconMapper glyphForIconName:iconName];
                if (glyph.length == 0) glyph = [HAEntityDisplayHelper iconGlyphForEntity:entity];
                UIColor *custom = [self iconColorForEntity:entity color:config[@"color"]];
                if (custom) iconColor = custom;
            }
            if ([config[@"show_state"] boolValue]) {
                // state-display with dash-unavailable: "—" for unavailable
                NSString *stateText = [entity.state isEqualToString:@"unavailable"]
                    ? @"—" : [HAEntityDisplayHelper stateWithUnitForEntity:entity decimals:1];
                text = [HAEntityDisplayHelper stateContentText:config[@"state_content"]
                                                     forEntity:entity
                                                     stateText:stateText
                                                          name:name] ?: stateText;
            }
        }
        if (glyph.length == 0 && text.length == 0) continue; // nothing to draw

        UIView *badge = [[UIView alloc] init];
        badge.backgroundColor = [UIColor clearColor];
        CGFloat width = 0;
        if (glyph.length > 0) {
            UILabel *iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, kHeadingBadgeIconSize, kHeadingBadgeIconSize)];
            iconLabel.font = [HAIconMapper mdiFontOfSize:kHeadingBadgeIconSize];
            iconLabel.textAlignment = NSTextAlignmentCenter;
            iconLabel.text = glyph;
            iconLabel.textColor = iconColor;
            iconLabel.tag = 1;
            [badge addSubview:iconLabel];
            width = kHeadingBadgeIconSize;
        }
        if (text.length > 0) {
            UILabel *textLabel = [[UILabel alloc] init];
            textLabel.font = textFont;
            textLabel.textColor = [HATheme secondaryTextColor];
            textLabel.text = text;
            textLabel.tag = 2;
            CGFloat textWidth = ceil([text sizeWithAttributes:@{NSFontAttributeName: textFont}].width);
            if (width > 0) width += kHeadingBadgeIconGap;
            textLabel.frame = CGRectMake(width, 0, textWidth, 20.0);
            [badge addSubview:textLabel];
            width += textWidth;
        }

        badge.isAccessibilityElement = YES;
        NSMutableArray<NSString *> *spoken = [NSMutableArray array];
        if (name.length > 0) [spoken addObject:name];
        if (text.length > 0 && entity) [spoken addObject:text];
        badge.accessibilityLabel = [spoken componentsJoinedByString:@", "];

        NSUInteger index = self.mutableBadgeViews.count;
        badge.tag = (NSInteger)index;
        if (entity) [self addGesturesToBadge:badge config:config];

        [self addSubview:badge];
        [self.mutableBadgeViews addObject:badge];
        [self.badgeWidths addObject:@(width)];
        [self.badgeConfigs addObject:config];
        [self.badgeEntities addObject:entity ?: (id)[NSNull null]];
        total += (index > 0 ? kHeadingBadgeSpacing : 0) + width;
    }
    self.contentWidth = total;
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
}

/// hui-entity-heading-badge _computeStateColor: "state" → the entity's state
/// colour, "none"/absent → inherit (nil here), any other colour only while
/// the entity is active.
- (UIColor *)iconColorForEntity:(HAEntity *)entity color:(id)color {
    if (![color isKindOfClass:[NSString class]] || [color length] == 0 || [color isEqualToString:@"none"]) return nil;
    if ([color isEqualToString:@"state"]) return [HAEntityDisplayHelper iconColorForEntity:entity];
    return [HAEntityDisplayHelper isEntityStateActive:entity] ? [HATheme colorFromString:color] : nil;
}

- (void)addGesturesToBadge:(UIView *)badge config:(NSDictionary *)config {
    BOOL hasTap = [HAAction configHasAction:config[@"tap_action"]];
    BOOL hasHold = [HAAction configHasAction:config[@"hold_action"]];
    BOOL hasDouble = [HAAction configHasAction:config[@"double_tap_action"]];
    if (!hasTap && !hasHold && !hasDouble) return; // HA type "badge": not a button
    badge.userInteractionEnabled = YES;
    badge.accessibilityTraits = UIAccessibilityTraitButton;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(badgeTapped:)];
    [badge addGestureRecognizer:tap];
    if (hasDouble) {
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(badgeDoubleTapped:)];
        doubleTap.numberOfTapsRequired = 2;
        [badge addGestureRecognizer:doubleTap];
        [tap requireGestureRecognizerToFail:doubleTap];
    }
    if (hasHold) {
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(badgeHeld:)];
        hold.minimumPressDuration = 0.5;
        [badge addGestureRecognizer:hold];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Right-aligned: the last badge ends at the trailing edge; when the view is
    // narrower than contentWidth the leading badges are clipped.
    CGFloat height = self.bounds.size.height;
    CGFloat x = self.bounds.size.width - self.contentWidth;
    for (NSUInteger i = 0; i < self.mutableBadgeViews.count; i++) {
        UIView *badge = self.mutableBadgeViews[i];
        CGFloat width = [self.badgeWidths[i] floatValue];
        // Full-height badge (a comfortable touch target); content centred vertically
        badge.frame = CGRectMake(x, 0, width, height);
        CGFloat midY = round(height / 2.0);
        for (UIView *sub in badge.subviews) {
            CGRect f = sub.frame;
            f.origin.y = midY - round(f.size.height / 2.0);
            sub.frame = f;
        }
        x += width + kHeadingBadgeSpacing;
    }
}

#pragma mark - Actions

- (void)fireAction:(NSString *)actionType fromView:(UIView *)view {
    NSInteger idx = view.tag;
    if (idx < 0 || idx >= (NSInteger)self.badgeConfigs.count || !self.badgeActionBlock) return;
    id entity = self.badgeEntities[(NSUInteger)idx];
    if (![entity isKindOfClass:[HAEntity class]]) return;
    NSDictionary *config = self.badgeConfigs[(NSUInteger)idx];
    if (![HAAction configHasAction:config[actionType]]) return; // "none" (HA default for heading badges)
    self.badgeActionBlock(entity, config, actionType);
}

- (void)badgeTapped:(UITapGestureRecognizer *)gesture {
    [self fireAction:@"tap_action" fromView:gesture.view];
}

- (void)badgeDoubleTapped:(UITapGestureRecognizer *)gesture {
    [self fireAction:@"double_tap_action" fromView:gesture.view];
}

- (void)badgeHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self fireAction:@"hold_action" fromView:gesture.view];
}

@end
