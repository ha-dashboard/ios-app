#import "HAEntityNameResolver.h"

static NSString *const kHAEntityNameJoinSeparator = @" ";

#pragma mark - HAEntityNameRegistryContext

@implementation HAEntityNameRegistryContext

+ (instancetype)contextWithEntityAreaMap:(NSDictionary<NSString *, NSString *> *)entityAreaMap
                                areaNames:(NSDictionary<NSString *, NSString *> *)areaNames
                          entityDeviceMap:(NSDictionary<NSString *, NSString *> *)entityDeviceMap
                              deviceNames:(NSDictionary<NSString *, NSString *> *)deviceNames
                       floorNamesByAreaId:(NSDictionary<NSString *, NSString *> *)floorNamesByAreaId {
    HAEntityNameRegistryContext *context = [[HAEntityNameRegistryContext alloc] init];
    context.entityAreaMap = entityAreaMap ?: @{};
    context.areaNames = areaNames ?: @{};
    context.entityDeviceMap = entityDeviceMap ?: @{};
    context.deviceNames = deviceNames ?: @{};
    context.floorNamesByAreaId = floorNamesByAreaId ?: @{};
    return context;
}

+ (instancetype)emptyContext {
    return [self contextWithEntityAreaMap:@{} areaNames:@{} entityDeviceMap:@{} deviceNames:@{} floorNamesByAreaId:@{}];
}

@end


#pragma mark - HAEntityNameResolver

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

    // Resolve every item (nonsense entries, e.g. a nested array, resolve to
    // an empty slot rather than throwing), matching HA's per-item mapping.
    NSMutableArray<NSString *> *resolvedParts = [NSMutableArray arrayWithCapacity:items.count];
    for (id itemRaw in items) {
        NSString *part = [self _resolvePart:itemRaw forEntityId:entityId context:context];
        [resolvedParts addObject:part ?: @""];
    }

    // A single-item config carries its resolved value directly (or is
    // unresolved — fall back to the caller's default rather than HA's own
    // behavior of showing a blank name, since this app has no card editor
    // to let the user notice and fix a bad config).
    if (resolvedParts.count == 1) {
        NSString *only = resolvedParts.firstObject;
        return only.length > 0 ? only : nil;
    }

    NSMutableArray<NSString *> *nonEmptyParts = [NSMutableArray arrayWithCapacity:resolvedParts.count];
    for (NSString *part in resolvedParts) {
        if (part.length > 0) [nonEmptyParts addObject:part];
    }
    if (nonEmptyParts.count == 0) return nil;
    return [nonEmptyParts componentsJoinedByString:kHAEntityNameJoinSeparator];
}

@end
