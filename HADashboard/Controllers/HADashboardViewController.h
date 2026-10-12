#import <UIKit/UIKit.h>

@class HADashboardConfigItem, HADashboardConfigSection, HAEntity;

@interface HADashboardViewController : UIViewController

/// Layout height for a dashboard item, as used by the collection view layouts.
/// `section` is the item's config section (composite cards fall back to it);
/// `entity` is the item's resolved entity, or nil.
+ (CGFloat)heightForItem:(HADashboardConfigItem *)item
                  entity:(HAEntity *)entity
                 section:(HADashboardConfigSection *)section
               itemWidth:(CGFloat)itemWidth;

@end
