#import <Foundation/Foundation.h>
#import "HACacheManager.h"

@class HAEntity;

/// Schedules `block` to run after `delay` seconds. Production code schedules on
/// the main queue via dispatch_after; tests inject a fake that fires (or holds)
/// the block deterministically instead of waiting on the wall clock.
typedef void (^HAEntityStateCacheScheduler)(NSTimeInterval delay, dispatch_block_t block);

/// Caches entity states to disk with heavily debounced, deduplicated writes.
///
/// Writes coalesce to at most 1 per `kHAEntityStateCacheMinWriteInterval`
/// (5 minutes) while entity updates keep arriving. A write whose serialized
/// bytes are identical to the last thing actually written to disk is skipped
/// entirely (sha256 comparison), so a quiet HA instance — or a window where
/// nothing meaningful changed — costs nothing. flushToDisk bypasses the
/// debounce for immediate, synchronous persistence and is also triggered
/// automatically on resign-active, background, terminate, and memory-warning
/// notifications. All disk writes happen on one private serial queue, so
/// writes never overlap and never run on a shared/global concurrent queue.
@interface HAEntityStateCache : NSObject

+ (instancetype)sharedCache;

/// Test seam: inject a fake cache manager and a fake scheduler instead of the
/// real filesystem + wall clock. Also registers the same lifecycle-flush
/// notification observers as the production instance.
- (instancetype)initWithCacheManager:(id<HACacheWriting>)cacheManager
                            scheduler:(HAEntityStateCacheScheduler)scheduler NS_DESIGNATED_INITIALIZER;

/// Load cached entity states from disk. Returns entity_id → raw state dict
/// (same format as HA WebSocket state response: entity_id, state, attributes,
/// last_changed, last_updated). Returns nil if no cache exists.
- (NSDictionary<NSString *, NSDictionary *> *)loadCachedStates;

/// Notify the cache that entity states changed. Triggers a debounced write.
/// Pass the full entity store snapshot (entity_id → HAEntity).
- (void)entitiesDidUpdate:(NSDictionary<NSString *, HAEntity *> *)entities;

/// Flush current entity states to disk immediately, bypassing debounce.
/// Called automatically on resign-active, background, terminate, and memory
/// warning; safe to call manually too. No-op when nothing is pending or the
/// pending snapshot is identical to what's already on disk.
- (void)flushToDisk;

/// Drop any debounced in-memory snapshot so a reset cannot recreate a cache.
- (void)discardPendingWrites;

/// Whether there is a cached state file on disk for the current server.
- (BOOL)hasCachedStates;

@end
