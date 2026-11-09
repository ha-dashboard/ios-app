#import "HAEntityStateCache.h"
#import "HACacheManager.h"
#import "HAEntity.h"
#import "HALog.h"
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>

static NSString *const kEntityStatesFile = @"entity-states.json";

// Writes coalesce to at most one per this interval while updates keep
// arriving (previously 5 seconds — on a live HA instance that's ~1.19MB
// every 5s, ~237KB/s / ~16GB/day per kiosk). 5 minutes keeps the cold-start
// cache reasonably fresh while cutting steady-state disk writes ~60x; the
// sha256 dedupe below trims further whenever nothing actually changed.
static const NSTimeInterval kHAEntityStateCacheMinWriteInterval = 300.0;

@interface HAEntityStateCache ()
@property (nonatomic, strong) id<HACacheWriting> cacheManager;
@property (nonatomic, copy) HAEntityStateCacheScheduler scheduler;
@property (nonatomic, strong) dispatch_queue_t writeQueue;
@property (nonatomic, strong) NSDictionary<NSString *, HAEntity *> *pendingEntities;
@property (nonatomic, assign) BOOL writeScheduled;
/// sha256 of the bytes last actually written to disk. Guarded by writeQueue.
@property (nonatomic, copy) NSString *lastWrittenHash;
@end

@implementation HAEntityStateCache

+ (instancetype)sharedCache {
    static HAEntityStateCache *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        HAEntityStateCacheScheduler defaultScheduler = ^(NSTimeInterval delay, dispatch_block_t block) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), block);
        };
        instance = [[HAEntityStateCache alloc] initWithCacheManager:[HACacheManager sharedManager]
                                                            scheduler:defaultScheduler];
    });
    return instance;
}

- (instancetype)init {
    return [self initWithCacheManager:[HACacheManager sharedManager]
                             scheduler:^(NSTimeInterval delay, dispatch_block_t block) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), block);
    }];
}

- (instancetype)initWithCacheManager:(id<HACacheWriting>)cacheManager
                            scheduler:(HAEntityStateCacheScheduler)scheduler {
    self = [super init];
    if (self) {
        _cacheManager = cacheManager;
        _scheduler = [scheduler copy];
        // One private serial queue for the whole read-modify-write pipeline:
        // snapshotting, JSON serialization, hashing, and the disk write all
        // happen here, off the main thread. Serial means writes can never
        // overlap, and nothing is ever dispatched onto a shared/global
        // concurrent queue (the prior design hopped onto the global utility
        // queue on every debounce fire, which is unnecessary contention).
        _writeQueue = dispatch_queue_create("com.hadashboard.entitycache.write",
                                            dispatch_queue_attr_make_with_qos_class(
                                                DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
        [self registerLifecycleObservers];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Lifecycle flush hooks

- (void)registerLifecycleObservers {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    // iOS 9-safe UIKit app-lifecycle notifications. applicationWillResignActive
    // already flushes explicitly (HAAppDelegate), but these cover background,
    // terminate, and low-memory so the latest snapshot is never lost even if
    // a call site forgets, and so we release the in-memory pending snapshot
    // as soon as possible under memory pressure.
    [center addObserver:self selector:@selector(flushToDisk) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(flushToDisk) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(flushToDisk) name:UIApplicationWillTerminateNotification object:nil];
    [center addObserver:self selector:@selector(flushToDisk) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}

#pragma mark - Read

- (NSDictionary<NSString *, NSDictionary *> *)loadCachedStates {
    NSDictionary *json = [self.cacheManager readJSONFromFile:kEntityStatesFile];
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
    NSString *dir = [self.cacheManager persistentCacheDirectory];
    if (!dir) return NO;
    NSString *path = [dir stringByAppendingPathComponent:kEntityStatesFile];
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

#pragma mark - Write (Debounced)

- (void)entitiesDidUpdate:(NSDictionary<NSString *, HAEntity *> *)entities {
    if (!entities || entities.count == 0) return;
    self.pendingEntities = entities;

    if (self.writeScheduled) return;
    self.writeScheduled = YES;

    __weak typeof(self) weakSelf = self;
    self.scheduler(kHAEntityStateCacheMinWriteInterval, ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.writeScheduled = NO;
        [strongSelf writePendingToDiskAsync];
    });
}

- (void)flushToDisk {
    // The scheduled timer (if any) will still fire later and find nothing
    // pending — harmless. We write NOW, synchronously, so the caller can
    // rely on the data being on disk before returning (e.g. resign-active).
    self.writeScheduled = NO;
    [self writePendingToDiskSync];
}

- (void)discardPendingWrites {
    self.writeScheduled = NO;
    self.pendingEntities = nil;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.writeQueue, ^{
        weakSelf.lastWrittenHash = nil;
    });
}

#pragma mark - Private

- (void)writePendingToDiskAsync {
    NSDictionary<NSString *, HAEntity *> *entities = self.pendingEntities;
    if (!entities || entities.count == 0) return;
    self.pendingEntities = nil;

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.writeQueue, ^{
        [weakSelf performWriteWithEntities:entities];
    });
}

- (void)writePendingToDiskSync {
    NSDictionary<NSString *, HAEntity *> *entities = self.pendingEntities;
    if (!entities || entities.count == 0) return;
    self.pendingEntities = nil;

    __weak typeof(self) weakSelf = self;
    dispatch_sync(self.writeQueue, ^{
        [weakSelf performWriteWithEntities:entities];
    });
}

/// Always runs on self.writeQueue (our one private serial queue), so this
/// never overlaps with another call, whether reached via the debounced
/// async path or the synchronous flush path.
- (void)performWriteWithEntities:(NSDictionary<NSString *, HAEntity *> *)entities {
    NSDictionary *serialized = [self serializeEntities:entities];

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:serialized options:0 error:&error];
    if (!jsonData) {
        HALogE(@"cache", @"Failed to serialize entity states: %@", error.localizedDescription);
        return;
    }

    // Cheap dirty check: skip the disk write entirely when the bytes we'd
    // write are identical to what's already on disk (e.g. an event fired
    // but nothing in the full snapshot actually differs).
    NSString *hash = [self sha256OfData:jsonData];
    if (self.lastWrittenHash && [hash isEqualToString:self.lastWrittenHash]) {
        HALogD(@"cache", @"Entity states unchanged (%lu entities), skipping write", (unsigned long)serialized.count);
        return;
    }

    BOOL ok = [self.cacheManager writeJSONSync:serialized toFile:kEntityStatesFile];
    if (ok) {
        self.lastWrittenHash = hash;
        HALogD(@"cache", @"Wrote %lu entity states to disk", (unsigned long)serialized.count);
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

- (NSString *)sha256OfData:(NSData *)data {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", hash[i]];
    }
    return output;
}

@end
