#import "HAEntityStateCache.h"
#import "HACacheManager.h"
#import "HAEntity.h"
#import "HALog.h"

static NSString *const kEntityStatesFile = @"entity-states.json";
static const NSTimeInterval kDebounceInterval = 5.0;

@interface HAEntityStateCache ()
@property (nonatomic, strong) NSDictionary<NSString *, HAEntity *> *pendingEntities;
@property (nonatomic, assign) BOOL writeScheduled;
@end

@implementation HAEntityStateCache

+ (instancetype)sharedCache {
    static HAEntityStateCache *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HAEntityStateCache alloc] init];
    });
    return instance;
}

#pragma mark - Read

- (NSDictionary<NSString *, NSDictionary *> *)loadCachedStates {
    NSDictionary *json = [[HACacheManager sharedManager] readJSONFromFile:kEntityStatesFile];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;

    // Validate structure: top-level dict of entity_id → dict
    NSMutableDictionary *validated = [NSMutableDictionary dictionaryWithCapacity:json.count];
    for (NSString *key in json) {
        id value = json[key];
        if ([value isKindOfClass:[NSDictionary class]] && [key containsString:@"."]) {
            validated[key] = value;
        }
    }
    HALogI(@"cache", @"Loaded %lu cached entity states", (unsigned long)validated.count);
    return validated.count > 0 ? validated : nil;
}

- (BOOL)hasCachedStates {
    NSString *dir = [[HACacheManager sharedManager] persistentCacheDirectory];
    if (!dir) return NO;
    NSString *path = [dir stringByAppendingPathComponent:kEntityStatesFile];
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

#pragma mark - Write (Debounced)

- (void)entitiesDidUpdate:(NSDictionary<NSString *, HAEntity *> *)entities {
    if (!entities || entities.count == 0) return;
    self.pendingEntities = entities;

    if (!self.writeScheduled) {
        self.writeScheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDebounceInterval * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            self.writeScheduled = NO;
            [self writePendingToDisk];
        });
    }
}

- (void)flushToDisk {
    // Cancel any pending debounce — we're writing NOW (synchronously)
    self.writeScheduled = NO;
    [self writePendingToDiskSync];
}

- (void)discardPendingWrites {
    self.writeScheduled = NO;
    self.pendingEntities = nil;
}

#pragma mark - Private

- (void)writePendingToDisk {
    NSDictionary<NSString *, HAEntity *> *entities = self.pendingEntities;
    if (!entities || entities.count == 0) return;
    self.pendingEntities = nil;

    // Snapshot entity data on main thread — copies string/dict values so the
    // background block doesn't touch HAEntity objects that may be deallocated.
    // This is fast (~1ms) since it copies NSString/NSDictionary refs, not deep data.
    // The slow part (NSJSONSerialization) stays on the background queue.
    NSDictionary *serialized = [self serializeEntities:entities];

    // Write to disk off main thread.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [[HACacheManager sharedManager] writeJSON:serialized toFile:kEntityStatesFile completion:^(BOOL success) {
            if (success) {
                HALogD(@"cache", @"Wrote %lu entity states to disk", (unsigned long)serialized.count);
            }
        }];
    });
}

/// Synchronous version for flushToDisk when we need immediate persistence
- (void)writePendingToDiskSync {
    NSDictionary<NSString *, HAEntity *> *entities = self.pendingEntities;
    if (!entities || entities.count == 0) return;
    self.pendingEntities = nil;

    NSDictionary *serialized = [self serializeEntities:entities];
    BOOL ok = [[HACacheManager sharedManager] writeJSONSync:serialized toFile:kEntityStatesFile];
    if (ok) {
        HALogD(@"cache", @"Flushed %lu entity states to disk (sync)", (unsigned long)serialized.count);
    }
}

- (NSDictionary *)serializeEntities:(NSDictionary<NSString *, HAEntity *> *)entities {
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:entities.count];
    for (NSString *entityId in entities) {
        HAEntity *entity = entities[entityId];
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        if (entity.entityId)    dict[@"entity_id"]    = entity.entityId;
        if (entity.state)       dict[@"state"]        = entity.state;
        if (entity.attributes)  dict[@"attributes"]   = entity.attributes;
        if (entity.lastChanged) dict[@"last_changed"]  = entity.lastChanged;
        if (entity.lastUpdated) dict[@"last_updated"]  = entity.lastUpdated;
        result[entityId] = dict;
    }
    return result;
}

@end
