#import <UIKit/UIKit.h>
#import "HAStackView.h"

@class HADashboardConfigSection;
@class HADashboardConfigItem;
@class HAEntity;
@class HAEntityRowView;

@interface HAEntitiesCardCell : UICollectionViewCell

- (void)configureWithSection:(HADashboardConfigSection *)section
                    entities:(NSDictionary *)entityDict
                  configItem:(HADashboardConfigItem *)configItem;

+ (CGFloat)preferredHeightForEntityCount:(NSInteger)count hasTitle:(BOOL)hasTitle hasHeaderToggle:(BOOL)hasHeaderToggle;
+ (CGFloat)preferredHeightForEntityCount:(NSInteger)count hasTitle:(BOOL)hasTitle hasHeaderToggle:(BOOL)hasHeaderToggle hasSceneChips:(BOOL)hasSceneChips;

/// Height calculation that auto-detects scene/script entities and accounts for chip row.
+ (CGFloat)preferredHeightForSection:(HADashboardConfigSection *)section
                            entities:(NSDictionary *)entityDict;

/// Called when an entity row is tapped (non-control area). Used to open entity detail.
@property (nonatomic, copy) void(^entityTapBlock)(HAEntity *entity);

/// Entity row views (for hit-testing from dashboard VC).
@property (nonatomic, strong, readonly) NSMutableArray<HAEntityRowView *> *rowViews;
@property (nonatomic, strong, readonly) HAStackView *stackView;

@end
