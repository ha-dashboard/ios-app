#import <Foundation/Foundation.h>

@class HADashboardConfigSection;

@interface HADashboardConfigItem : NSObject

@property (nonatomic, copy) NSString *entityId;
@property (nonatomic, copy) NSString *displayName;  // overrides friendly_name
@property (nonatomic, assign) NSInteger column;
@property (nonatomic, assign) NSInteger row;
@property (nonatomic, assign) NSInteger columnSpan;  // defaults to 1
@property (nonatomic, assign) NSInteger rowSpan;     // defaults to 1
@property (nonatomic, copy) NSString *cardType;      // Lovelace card type (e.g. "entities", "thermostat")
/// For entities card items in columnar layout: the sub-section with entity IDs and title
@property (nonatomic, strong) HADashboardConfigSection *entitiesSection;
/// Custom properties from Lovelace card (dimensions, card_mod, etc.)
@property (nonatomic, copy) NSDictionary *customProperties;
/// Conditional visibility: array of @{@"entity": entityId, @"state": requiredState}
/// Item is shown only when ALL conditions are met. nil = always show.
@property (nonatomic, copy) NSArray<NSDictionary *> *visibilityConditions;
/// Set when this item's generic rendering is standing in for an unmapped
/// custom:* Lovelace card that happened to carry an "entity"/"entities" key
/// (e.g. "custom:bubble-card"), so it didn't produce zero entities and
/// therefore wasn't routed to the HAUnsupportedCardType placeholder. The raw
/// Lovelace "type" string, or nil for a normal (non-fallback) item. The cell
/// shows this as a small, subtle badge so the fallback isn't mistaken for a
/// fully-supported card. See +[HALovelaceParser isNativelySupportedCustomCardType:].
@property (nonatomic, copy) NSString *fallbackCardType;

- (instancetype)initWithDictionary:(NSDictionary *)dict;

@end


/// A section of items, typically corresponding to a Lovelace card or HA section column
@interface HADashboardConfigSection : NSObject

@property (nonatomic, copy) NSString *title;       // nil for untitled sections
@property (nonatomic, copy) NSString *cardType;    // Lovelace card type
@property (nonatomic, copy) NSString *icon;        // MDI icon name (e.g. "mdi:thermometer")
@property (nonatomic, copy) NSArray<HADashboardConfigItem *> *items;
@property (nonatomic, copy) NSArray<NSString *> *entityIds; // All entity IDs for composite cards
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *nameOverrides; // entity_id -> display name
@property (nonatomic, copy) NSDictionary *customProperties; // Extra rendering hints (e.g. chipStyle)
/// Sections view: the HA section's column_span (how many view columns it
/// covers, before clamping to the columns available on screen). 0 = 1.
@property (nonatomic, assign) NSInteger columnSpan;

@end


@interface HADashboardConfig : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<HADashboardConfigItem *> *items;
@property (nonatomic, copy) NSArray<HADashboardConfigSection *> *sections;
@property (nonatomic, assign) NSInteger columns;      // grid columns, defaults to 3

/// View-level badge row (the Lovelace view's "badges"), or nil when the view has
/// none (or is a panel view, which HA renders without badges). cardType is
/// "badges"; entityIds/nameOverrides list the badges in order, and
/// customProperties[@"badgeConfigs"] holds the matching normalized badge
/// configs (see +[HALovelaceParser normalizedViewBadgeConfigs:]). Kept apart
/// from `sections` because it is laid out full width above every section/column.
@property (nonatomic, strong) HADashboardConfigSection *viewBadges;

/// Strategy-based dashboard: type string (e.g. "original-states", "home") or nil
@property (nonatomic, copy) NSString *strategyType;
/// Strategy-based dashboard: full strategy config dictionary or nil
@property (nonatomic, copy) NSDictionary *strategyConfig;

+ (instancetype)configFromJSONData:(NSData *)data error:(NSError **)error;
+ (instancetype)configFromFileAtPath:(NSString *)path error:(NSError **)error;

/// Returns a default config showing all entities in a simple grid
+ (instancetype)defaultConfigWithEntityIds:(NSArray<NSString *> *)entityIds columns:(NSInteger)columns;

/// All entity IDs referenced in this config (across all sections)
- (NSArray<NSString *> *)allEntityIds;

@end
