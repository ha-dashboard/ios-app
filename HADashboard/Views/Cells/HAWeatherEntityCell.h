#import "HABaseEntityCell.h"

@class HADashboardConfigItem;

@interface HAWeatherEntityCell : HABaseEntityCell

/// Preferred height for the weather cell with default options (both
/// current conditions and a 5-row forecast shown).
+ (CGFloat)preferredHeight;

/// Preferred height honoring the weather-forecast card's show_current /
/// show_forecast / forecast_slots options on configItem.customProperties.
/// Pass nil for default (both sections shown, 5 forecast rows).
+ (CGFloat)preferredHeightForConfigItem:(HADashboardConfigItem *)configItem;

@end
