#import "HAEntityNameResolver.h"

static NSString *const kHAEntityNameJoinSeparator = @" ";

#pragma mark - HAEntityNameRegistryContext

@implementation HAEntityNameRegistryContext

+ (instancetype)contextWithEntityAreaMap:(NSDictionary<NSString *, NSString *> *)entityAreaMap
                                areaNames:(NSDictionary<NSString *, NSString *> *)areaNames
                          entityDeviceMap:(NSDictionary<NSString *, NSString *> *)entityDeviceMap
                              deviceNames:(NSDictionary<NSString *, NSString *> *)deviceNames
                       floorNamesByAreaId:(NSDictionary<NSString *, NSString *> *)floorNamesByAreaId
                      entityRegistryNames:(NSDictionary<NSString *, NSString *> *)entityRegistryNames {
    HAEntityNameRegistryContext *context = [[HAEntityNameRegistryContext alloc] init];
    context.entityAreaMap = entityAreaMap ?: @{};
    context.areaNames = areaNames ?: @{};
    context.entityDeviceMap = entityDeviceMap ?: @{};
    context.deviceNames = deviceNames ?: @{};
    context.floorNamesByAreaId = floorNamesByAreaId ?: @{};
    context.entityRegistryNames = entityRegistryNames ?: @{};
    return context;
}

+ (instancetype)emptyContext {
    return [self contextWithEntityAreaMap:@{} areaNames:@{} entityDeviceMap:@{} deviceNames:@{}
                        floorNamesByAreaId:@{} entityRegistryNames:@{}];
}

@end


#pragma mark - HAEntityNameResolver

/// Separators HA accepts between a device name and the rest of an entity
/// name when stripping the device-name prefix (strip_prefix_from_entity_name.ts).
static NSArray<NSString *> *HAEntityNameStripSeparators(void) {
    static NSArray<NSString *> *separators;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        separators = @[@" ", @": ", @" - "];
    });
    return separators;
}

@implementation HAEntityNameResolver

/// Resolve a single @{"type": ...} name item. Returns nil for "entity" (by
/// design — see header), for unsupported types such as "parent_device"
/// (no device-hierarchy data is tracked locally), and for anything
/// malformed.
+ (NSString *)_resolvePart:(NSDictionary *)item
                forEntityId:(NSString *)entityId
                    context:(HAEntityNameRegistryContext *)context {
    if (![item isKindOfClass:[NSDictionary class]]) return nil;

    id typeRaw = item[@"type"];
    if (![typeRaw isKindOfClass:[NSString class]]) return nil;
    NSString *type = (NSString *)typeRaw;

    if ([type isEqualToString:@"text"]) {
        id text = item[@"text"];
        if (![text isKindOfClass:[NSString class]]) return nil;
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        return trimmed.length > 0 ? trimmed : nil;
    }

    if ([type isEqualToString:@"entity"]) {
        // Requesting the entity's own name is equivalent to no override —
        // let the caller fall back to its normal entity display name.
        return nil;
    }

    if ([type isEqualToString:@"area"]) {
        NSString *areaId = context.entityAreaMap[entityId];
        if (!areaId) return nil;
        NSString *name = context.areaNames[areaId];
        return name.length > 0 ? name : nil;
    }

    if ([type isEqualToString:@"device"]) {
        NSString *deviceId = context.entityDeviceMap[entityId];
        if (!deviceId) return nil;
        NSString *name = context.deviceNames[deviceId];
        return name.length > 0 ? name : nil;
    }

    if ([type isEqualToString:@"floor"]) {
        NSString *areaId = context.entityAreaMap[entityId];
        if (!areaId) return nil;
        NSString *name = context.floorNamesByAreaId[areaId];
        return name.length > 0 ? name : nil;
    }

    // Unknown/unsupported type (e.g. "parent_device"): degrade gracefully.
    return nil;
}

/// Whether `entityName` is the device name itself (plus only separator
/// characters) — core treats that as the entity having no name of its own.
/// Mirrors isDeviceName in strip_prefix_from_entity_name.ts.
+ (BOOL)_entityName:(NSString *)entityName isJustDeviceName:(NSString *)deviceName {
    if (deviceName.length == 0) return NO;
    NSString *lowerName = [entityName lowercaseString];
    NSString *lowerDevice = [deviceName lowercaseString];
    if (![lowerName hasPrefix:lowerDevice]) return NO;
    NSString *remainder = [lowerName substringFromIndex:lowerDevice.length];
    NSCharacterSet *nonSeparator = [[NSCharacterSet characterSetWithCharactersInString:@" :-"] invertedSet];
    return [remainder rangeOfCharacterFromSet:nonSeparator].location == NSNotFound;
}

/// Strips a leading "<deviceName><separator>" from entityName, where
/// separator is one of " ", ": ", " - " (case-insensitive match on the
/// device name). Capitalizes the remainder's first letter unless its first
/// word already contains an uppercase letter. Returns nil if entityName
/// doesn't start with the device name in one of those forms, or if nothing
/// is left after stripping. Mirrors stripPrefixFromEntityName in
/// strip_prefix_from_entity_name.ts.
+ (NSString *)_stripDeviceNamePrefix:(NSString *)deviceName fromEntityName:(NSString *)entityName {
    NSString *lowerName = [entityName lowercaseString];
    NSString *lowerDevice = [deviceName lowercaseString];
    for (NSString *separator in HAEntityNameStripSeparators()) {
        NSString *lowerPrefix = [lowerDevice stringByAppendingString:separator];
        if (![lowerName hasPrefix:lowerPrefix]) continue;
        NSString *newName = [entityName substringFromIndex:lowerPrefix.length];
        if (newName.length == 0) continue;

        NSRange spaceRange = [newName rangeOfString:@" "];
        NSString *firstWord = (spaceRange.location == NSNotFound) ? newName : [newName substringToIndex:spaceRange.location];
        BOOL firstWordHasUpperCase = ![[firstWord lowercaseString] isEqualToString:firstWord];
        if (firstWordHasUpperCase) return newName;

        NSString *firstChar = [[newName substringToIndex:1] uppercaseString];
        return [firstChar stringByAppendingString:[newName substringFromIndex:1]];
    }
    return nil;
}

/// Resolves the "entity" part of a *multi-item* name config to the entity's
/// own name (registry "name" or "original_name"), with a leading
/// device-name prefix stripped the way HA's frontend does — e.g. device
/// "Kitchen Google" + entity "Kitchen Google Volume" => "Volume". Returns
/// nil if the registry name isn't known, or if the entity has no name of
/// its own beyond the device name. See the header for what this
/// intentionally does not reproduce (next_name_part gating).
+ (NSString *)_resolveEntityOwnNamePartForEntityId:(NSString *)entityId context:(HAEntityNameRegistryContext *)context {
    NSString *registryName = context.entityRegistryNames[entityId];
    if (registryName.length == 0) return nil;

    NSString *deviceId = context.entityDeviceMap[entityId];
    NSString *deviceName = deviceId ? context.deviceNames[deviceId] : nil;
    if (deviceName.length == 0) return registryName;

    if ([self _entityName:registryName isJustDeviceName:deviceName]) return nil;

    NSString *stripped = [self _stripDeviceNamePrefix:deviceName fromEntityName:registryName];
    return stripped ?: registryName;
}

+ (NSString *)resolveNameValue:(id)nameValue
                    forEntityId:(NSString *)entityId
                        context:(HAEntityNameRegistryContext *)context {
    if (![entityId isKindOfClass:[NSString class]] || entityId.length == 0) return nil;
    context = context ?: [HAEntityNameRegistryContext emptyContext];

    if ([nameValue isKindOfClass:[NSString class]]) {
        NSString *trimmed = [(NSString *)nameValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        return trimmed.length > 0 ? trimmed : nil;
    }

    NSArray *items;
    if ([nameValue isKindOfClass:[NSDictionary class]]) {
        items = @[nameValue];
    } else if ([nameValue isKindOfClass:[NSArray class]]) {
        items = (NSArray *)nameValue;
    } else {
        // Nonsense value (number, nil, bool, etc.) — degrade gracefully.
        return nil;
    }
    if (items.count == 0) return nil;

    // A single-item config carries its resolved value directly (or is
    // unresolved — fall back to the caller's default rather than HA's own
    // behavior of showing a blank name, since this app has no card editor
    // to let the user notice and fix a bad config). "entity" stays nil here
    // by design — see header — so this path matches _resolvePart: exactly.
    if (items.count == 1) {
        NSString *only = [self _resolvePart:items.firstObject forEntityId:entityId context:context];
        return only.length > 0 ? only : nil;
    }

    // Multi-item array: HA joins in the entity's *own* name (device-prefix
    // stripped) for an explicit "entity" item, unlike the single-item case —
    // see the header for why. Resolve every item (nonsense entries, e.g. a
    // nested array, resolve to an empty slot rather than throwing), matching
    // HA's per-item mapping.
    NSMutableArray<NSString *> *resolvedParts = [NSMutableArray arrayWithCapacity:items.count];
    for (id itemRaw in items) {
        NSString *part;
        if ([itemRaw isKindOfClass:[NSDictionary class]] && [itemRaw[@"type"] isEqual:@"entity"]) {
            part = [self _resolveEntityOwnNamePartForEntityId:entityId context:context];
        } else {
            part = [self _resolvePart:itemRaw forEntityId:entityId context:context];
        }
        [resolvedParts addObject:part ?: @""];
    }

    NSMutableArray<NSString *> *nonEmptyParts = [NSMutableArray arrayWithCapacity:resolvedParts.count];
    for (NSString *part in resolvedParts) {
        if (part.length > 0) [nonEmptyParts addObject:part];
    }
    if (nonEmptyParts.count == 0) return nil;
    return [nonEmptyParts componentsJoinedByString:kHAEntityNameJoinSeparator];
}

@end
