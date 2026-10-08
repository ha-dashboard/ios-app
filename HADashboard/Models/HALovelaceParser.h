#import <Foundation/Foundation.h>

@class HADashboardConfig;

/// NSUserDefaults key for the Settings → Developer "Show Unsupported Cards" toggle.
/// The key being absent (never touched by the user) is treated as YES — see
/// +[HALovelaceParser showUnsupportedCardsEnabled].
extern NSString *const HAShowUnsupportedCardsDefaultsKey;

/// Sentinel Lovelace card "type" stamped on synthesized placeholder items for an
/// unsupported/unrecognized card, so HAEntityCellFactory can route them to
/// HAUnsupportedCardCell. Never appears in a real Lovelace config.
extern NSString *const HAUnsupportedCardType;

/// customProperties key on an unsupported-card placeholder item: the original,
/// unmodified Lovelace "type" string (e.g. "custom:bubble-card").
extern NSString *const HAUnsupportedCardTypeKey;

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
/// Equivalent to calling the floor-aware variant below with an empty floorNamesByAreaId.
+ (HADashboardConfig *)dashboardConfigFromView:(HALovelaceView *)view
                                       columns:(NSInteger)columns
                                 entityAreaMap:(NSDictionary<NSString *, NSString *> *)entityAreaMap
                                     areaNames:(NSDictionary<NSString *, NSString *> *)areaNames
                               entityDeviceMap:(NSDictionary<NSString *, NSString *> *)entityDeviceMap
                                   deviceNames:(NSDictionary<NSString *, NSString *> *)deviceNames;

/// Convert a single Lovelace view with full registry data for resolving dynamic
/// card/row names: tile cards, entities-card rows, and any other path that reads
/// a "name" expressed as {"type": "area"|"device"|"floor"|"text"} or an array of
/// such items (see HAEntityNameResolver). Pass empty dicts when registry data is
/// unavailable. Equivalent to calling the entity-registry-aware variant below
/// with an empty entityRegistryNames.
+ (HADashboardConfig *)dashboardConfigFromView:(HALovelaceView *)view
                                       columns:(NSInteger)columns
                                 entityAreaMap:(NSDictionary<NSString *, NSString *> *)entityAreaMap
                                     areaNames:(NSDictionary<NSString *, NSString *> *)areaNames
                               entityDeviceMap:(NSDictionary<NSString *, NSString *> *)entityDeviceMap
                                   deviceNames:(NSDictionary<NSString *, NSString *> *)deviceNames
                            floorNamesByAreaId:(NSDictionary<NSString *, NSString *> *)floorNamesByAreaId;

/// Convert a single Lovelace view with the full registry data
/// HAEntityNameResolver can use, including entityRegistryNames (entity_id ->
/// the entity's own registry name, before device-prefix stripping) — needed
/// to resolve an explicit {"type": "entity"} item inside a multi-item name
/// array, e.g. "name": [{"type": "area"}, {"type": "entity"}]. Pass empty
/// dicts when registry data is unavailable.
+ (HADashboardConfig *)dashboardConfigFromView:(HALovelaceView *)view
                                       columns:(NSInteger)columns
                                 entityAreaMap:(NSDictionary<NSString *, NSString *> *)entityAreaMap
                                     areaNames:(NSDictionary<NSString *, NSString *> *)areaNames
                               entityDeviceMap:(NSDictionary<NSString *, NSString *> *)entityDeviceMap
                                   deviceNames:(NSDictionary<NSString *, NSString *> *)deviceNames
                            floorNamesByAreaId:(NSDictionary<NSString *, NSString *> *)floorNamesByAreaId
                           entityRegistryNames:(NSDictionary<NSString *, NSString *> *)entityRegistryNames;

/// Extract all entity IDs from a Lovelace card dictionary (recursively handles stacks)
+ (NSArray<NSDictionary *> *)extractEntitiesFromCard:(NSDictionary *)card;

/// Whether unsupported/unrecognized cards should produce a visible placeholder
/// item (YES, default) or be skipped silently like before this feature existed
/// (NO). Backed by HAShowUnsupportedCardsDefaultsKey; defaults to YES when the
/// user has never changed the Settings → Developer toggle.
+ (BOOL)showUnsupportedCardsEnabled;

@end
