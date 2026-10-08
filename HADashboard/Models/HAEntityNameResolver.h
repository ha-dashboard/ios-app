#import <Foundation/Foundation.h>

/// Registry lookups needed to resolve an HA "entity name config" value
/// (card/row "name" expressed as an object or array of objects, e.g.
/// {"type": "area"}) into a display string. All dictionaries are optional —
/// pass empty dictionaries (not nil) when registry data isn't available yet.
@interface HAEntityNameRegistryContext : NSObject

/// entity_id -> area_id
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *entityAreaMap;
/// area_id -> area display name
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *areaNames;
/// entity_id -> device_id
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *entityDeviceMap;
/// device_id -> device display name (already resolved name_by_user / name)
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *deviceNames;
/// area_id -> floor display name
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *floorNamesByAreaId;

+ (instancetype)contextWithEntityAreaMap:(NSDictionary<NSString *, NSString *> *)entityAreaMap
                                areaNames:(NSDictionary<NSString *, NSString *> *)areaNames
                          entityDeviceMap:(NSDictionary<NSString *, NSString *> *)entityDeviceMap
                              deviceNames:(NSDictionary<NSString *, NSString *> *)deviceNames
                       floorNamesByAreaId:(NSDictionary<NSString *, NSString *> *)floorNamesByAreaId;

/// A context with no registry data — every lookup degrades to nil.
+ (instancetype)emptyContext;

@end


/// Resolves a Home Assistant Lovelace "name" config value for a card or row
/// into a display string, following the entity-name-config semantics of the
/// HA frontend (see home-assistant/frontend src/common/entity/entity_name_config.ts
/// and compute_entity_name_display.ts): the value can be a plain string, a
/// single @{"type": ...} object, or an array of such objects joined with a
/// single space. Supported types: "area", "device", "floor", "text", and
/// "entity" (which intentionally resolves to nil so callers fall through to
/// the entity's own display name — requesting the entity's name is the same
/// as not overriding it). Unknown types (including "parent_device", which HA
/// resolves against device-hierarchy data this app doesn't track) and
/// malformed values degrade to nil rather than crashing.
@interface HAEntityNameResolver : NSObject

/// @param nameValue  The raw "name" value from the Lovelace card/row config.
///                   May be NSString (returned trimmed), NSDictionary,
///                   NSArray of NSDictionary, or any other JSON value —
///                   non-conforming values degrade to nil.
/// @param entityId   The entity this name is being resolved for.
/// @param context    Registry lookups. Pass [HAEntityNameRegistryContext emptyContext] if unavailable.
/// @return A trimmed, non-empty display string, or nil if unresolved or
///         unsupported — callers should fall back to their own default
///         display name (e.g. the entity's friendly name).
+ (NSString *)resolveNameValue:(id)nameValue
                    forEntityId:(NSString *)entityId
                        context:(HAEntityNameRegistryContext *)context;

@end
