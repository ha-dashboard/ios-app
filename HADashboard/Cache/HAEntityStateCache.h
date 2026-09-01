#import <Foundation/Foundation.h>

@class HAEntity;

/// Caches entity states to disk with debounced writes.
/// Writes coalesce to max 1 per 5 seconds. flushToDisk bypasses the debounce
/// for immediate persistence (call on applicationWillResignActive:).
@interface HAEntityStateCache : NSObject

+ (instancetype)sharedCache;

/// Load cached entity states from disk. Returns entity_id → raw state dict
/// (same format as HA WebSocket state response: entity_id, state, attributes,
/// last_changed, last_updated). Returns nil if no cache exists.
- (NSDictionary<NSString *, NSDictionary *> *)loadCachedStates;

/// Notify the cache that entity states changed. Triggers a debounced write.
/// Pass the full entity store snapshot (entity_id → HAEntity).
- (void)entitiesDidUpdate:(NSDictionary<NSString *, HAEntity *> *)entities;

/// Flush current entity states to disk immediately, bypassing debounce.
/// Call this on applicationWillResignActive:.
- (void)flushToDisk;

/// Drop any debounced in-memory snapshot so a reset cannot recreate a cache.
- (void)discardPendingWrites;

/// Whether there is a cached state file on disk for the current server.
- (BOOL)hasCachedStates;

@end
