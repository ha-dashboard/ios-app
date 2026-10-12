#import <UIKit/UIKit.h>

@class HADashboardConfigSection;
@class HAEntity;

/// Renders multiple entities as compact badge chips in a horizontal flow.
/// Used for custom:badge-card rendering.
@interface HABadgeRowCell : UICollectionViewCell

- (void)configureWithSection:(HADashboardConfigSection *)section entities:(NSDictionary *)entityDict;

/// Calculate preferred height for a given entity count and available width
+ (CGFloat)preferredHeightForEntityCount:(NSInteger)count width:(CGFloat)width;
+ (CGFloat)preferredHeightForEntityCount:(NSInteger)count width:(CGFloat)width chipStyle:(BOOL)chipStyle;

/// Calculate preferred height by measuring actual badge widths from entity data
+ (CGFloat)preferredHeightForSection:(HADashboardConfigSection *)section
                            entities:(NSDictionary *)entityDict
                               width:(CGFloat)width;

/// Called when a badge is tapped. Used to open entity detail.
@property (nonatomic, copy) void(^entityTapBlock)(HAEntity *entity);

/// View-level badges: when the section carries customProperties[@"badgeConfigs"]
/// (normalized HA entity badge configs, one per entityIds entry — see
/// +[HALovelaceParser normalizedViewBadgeConfigs:]), each badge honours its
/// show_name/show_state/show_icon/icon/color/state_content, and a tap calls
/// this block (when set) with that badge's config instead of entityTapBlock.
@property (nonatomic, copy) void(^badgeTapBlock)(HAEntity *entity, NSDictionary *badgeConfig);

@end
