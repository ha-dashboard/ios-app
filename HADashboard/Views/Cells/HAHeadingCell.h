#import <UIKit/UIKit.h>

@class HADashboardConfigItem;
@class HAEntity;

@interface HAHeadingCell : UICollectionViewCell

- (void)configureWithItem:(HADashboardConfigItem *)item;

/// Configure the heading and its badges: `badgeConfigs` are the item's
/// heading badges (customProperties[HAHeadingBadgesKey]) that pass their
/// visibility conditions, drawn right-aligned on the heading line with state
/// from `entities`. nil/empty shows no badges. An actionable heading
/// tap_action (customProperties[HAHeadingTapActionKey]) adds HA's chevron.
- (void)configureWithItem:(HADashboardConfigItem *)item
             badgeConfigs:(NSArray<NSDictionary *> *)badgeConfigs
                 entities:(NSDictionary<NSString *, HAEntity *> *)entities;

/// Called when a heading badge's configured tap/hold/double-tap action fires.
@property (nonatomic, copy) void (^badgeActionBlock)(HAEntity *entity, NSDictionary *badgeConfig, NSString *actionType);

/// YES when `point` (in the cell's coordinates) falls on a heading badge, so
/// a tap there is not the heading's own tap.
- (BOOL)badgesContainPoint:(CGPoint)point;

@end
