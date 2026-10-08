#import <Foundation/Foundation.h>

@class HADashboardConfig;

/// Represents a single Lovelace view (tab) in a HA dashboard
@interface HALovelaceView : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, strong) NSArray<NSDictionary *> *rawCards;
/// HA 2024+ sections: array of @{@"title": NSString, @"cards": NSArray}
/// nil for classic (non-sections) views.
@property (nonatomic, strong) NSArray<NSDictionary *> *rawSections;
/// Maximum columns for sections layout (from HA view config "max_columns"). 0 = use default (4).
@property (nonatomic, assign) NSInteger maxColumns;
/// View layout type: "masonry" (default classic), "panel", "sidebar", or "sections".
@property (nonatomic, copy) NSString *viewType;
@end


/// Parsed result of a full Lovelace dashboard configuration
@interface HALovelaceDashboard : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<HALovelaceView *> *views;

- (instancetype)initWithDictionary:(NSDictionary *)dict;

/// Get a view by index
- (HALovelaceView *)viewAtIndex:(NSUInteger)index;
@end


/// Parses Lovelace config JSON into our native HADashboardConfig format
@interface HALovelaceParser : NSObject

/// Parse the full Lovelace config response from HA WebSocket API
+ (HALovelaceDashboard *)parseDashboardFromDictionary:(NSDictionary *)dict;

/// Convert a single Lovelace view into our native HADashboardConfig
/// @param view The Lovelace view to convert
/// @param columns Number of grid columns
+ (HADashboardConfig *)dashboardConfigFromView:(HALovelaceView *)view columns:(NSInteger)columns;

/// Convert a single Lovelace view with registry data for resolving dynamic card names
/// (e.g. tile cards with "name": {"type": "area"} or "name": {"type": "device"}).
/// Pass empty dicts when registry data is unavailable.
+ (HADashboardConfig *)dashboardConfigFromView:(HALovelaceView *)view
                                       columns:(NSInteger)columns
                                 entityAreaMap:(NSDictionary<NSString *, NSString *> *)entityAreaMap
                                     areaNames:(NSDictionary<NSString *, NSString *> *)areaNames
                               entityDeviceMap:(NSDictionary<NSString *, NSString *> *)entityDeviceMap
                                   deviceNames:(NSDictionary<NSString *, NSString *> *)deviceNames;

/// Extract all entity IDs from a Lovelace card dictionary (recursively handles stacks)
+ (NSArray<NSDictionary *> *)extractEntitiesFromCard:(NSDictionary *)card;

@end
