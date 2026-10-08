#import <Foundation/Foundation.h>

/// Caches Lovelace dashboard configuration JSON with hash-based invalidation.
/// Per-dashboard storage: each dashboard path gets its own cache file.
@interface HADashboardConfigCache : NSObject

+ (instancetype)sharedCache;

/// Load cached dashboard config for the given dashboard path.
/// Pass nil for the default dashboard.
/// Returns the raw Lovelace config dict, or nil if no cache exists.
- (NSDictionary *)loadCachedConfigForDashboard:(NSString *)dashboardPath;

/// Cache a dashboard config. Computes a SHA256 hash of the JSON data.
/// Returns YES if the config changed (hash differs from cached version).
/// Returns NO if the config is identical to the cached version (skip re-render).
- (BOOL)cacheConfig:(NSDictionary *)config forDashboard:(NSString *)dashboardPath;

/// Same as -cacheConfig:forDashboard:, but with a completion hook for callers
/// (tests, primarily) that need to observe when the underlying disk write —
/// which happens asynchronously — has actually finished, instead of guessing
/// at a delay. `success` is NO when nothing was written (unchanged config, or
/// the config could not be serialized), YES once the write completes.
- (BOOL)cacheConfig:(NSDictionary *)config
       forDashboard:(NSString *)dashboardPath
         completion:(nullable void (^)(BOOL success))completion;

/// Whether there is a cached config file for the given dashboard path.
- (BOOL)hasCachedConfigForDashboard:(NSString *)dashboardPath;

/// Delete cached config for a specific dashboard.
- (void)clearCacheForDashboard:(NSString *)dashboardPath;

@end
