#import "HABaseEntityCell.h"

@class HAEntity, HADashboardConfigItem;

@interface HALightEntityCell : HABaseEntityCell

/// Preferred height for a light card showing this entity — accounts for
/// whichever of the name/toggle row, brightness slider, and color-temp
/// slider the cell will actually render. Does not include heading icon
/// extra height; callers add that themselves (see HADashboardViewController).
+ (CGFloat)preferredHeightForEntity:(HAEntity *)entity configItem:(HADashboardConfigItem *)configItem;

@end
