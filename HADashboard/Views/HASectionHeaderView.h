#import <UIKit/UIKit.h>

@class HADashboardConfigSection;
@class HAEntity;

/// Custom section header for the dashboard collection view.
/// Displays an optional MDI icon (as Unicode symbol) and a section title.
@interface HASectionHeaderView : UICollectionReusableView

- (void)configureWithSection:(HADashboardConfigSection *)section;

/// Configure the header and the badges of the heading card it came from:
/// `badgeConfigs` are the section's heading badges
/// (customProperties[HAHeadingBadgesKey]) that pass their visibility
/// conditions, drawn right-aligned with state from `entities`. An actionable
/// heading tap_action (customProperties[HAHeadingTapActionKey]) adds HA's
/// chevron and makes the title tappable (headingTapBlock).
- (void)configureWithSection:(HADashboardConfigSection *)section
                badgeConfigs:(NSArray<NSDictionary *> *)badgeConfigs
                    entities:(NSDictionary<NSString *, HAEntity *> *)entities;

/// Called when a heading badge's configured tap/hold/double-tap action fires.
@property (nonatomic, copy) void (^badgeActionBlock)(HAEntity *entity, NSDictionary *badgeConfig, NSString *actionType);

/// Called with the heading's tap_action when the header (outside its badges)
/// is tapped; only while that action is configured.
@property (nonatomic, copy) void (^headingTapBlock)(NSDictionary *tapAction);

/// Distance from the header's leading edge to its icon (or to the title when
/// there is no icon), and from its trailing edge to the title. Defaults to 8,
/// the inset of a standalone heading row (HAHeadingCell) inside its item frame,
/// which is right when the header frame starts where the section's items
/// start (HAColumnarLayout). A header spanning the full collection-view width
/// while items are inset (flow layout) adds that inset so both line up.
@property (nonatomic, assign) CGFloat contentInset;

@end
