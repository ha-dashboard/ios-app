#import <UIKit/UIKit.h>

@class HAEntity;

/// A heading card's "badges" (HA heading badges, hui-entity-heading-badge),
/// drawn as a compact, right-aligned row at the end of a heading line: per
/// badge an optional 16pt state icon and the state text in 14pt secondary
/// text, 3pt apart, badges 8pt apart (ha-heading-badge / hui-heading-card
/// .badges-row) — no pill background. Used by the standalone heading row
/// (HAHeadingCell), the section header (HASectionHeaderView) and headings
/// embedded above a grid's first card (HABaseEntityCell).
///
/// Badges whose action is configured (anything but "none") respond to tap,
/// hold and double tap; a double-tap recognizer is only added when
/// double_tap_action is set, so single taps are never delayed otherwise.
@interface HAHeadingBadgesView : UIView

/// Show `configs` (normalized heading badge configs — see
/// +[HALovelaceParser normalizedHeadingBadgeConfigs:] — already filtered by
/// their visibility conditions) with state from `entities`. A badge whose
/// entity is missing shows HA's error badge (red alert icon and "-").
- (void)configureWithBadgeConfigs:(NSArray<NSDictionary *> *)configs
                         entities:(NSDictionary<NSString *, HAEntity *> *)entities;

/// Width the badges need side by side (0 when there are none). Also the
/// view's intrinsic content width; narrower bounds clip the leading badges.
@property (nonatomic, readonly) CGFloat contentWidth;

/// One view per badge, in config order (exposed for tests).
@property (nonatomic, readonly) NSArray<UIView *> *badgeViews;

/// Called with "tap_action", "hold_action" or "double_tap_action" and the
/// badge's config when a badge with that action configured is activated.
@property (nonatomic, copy) void (^badgeActionBlock)(HAEntity *entity, NSDictionary *badgeConfig, NSString *actionType);

@end
