#import <Foundation/Foundation.h>

/// Minimal JSON read/write surface used by on-disk caches. Extracted so callers
/// (e.g. HAEntityStateCache) can inject a fake in unit tests instead of hitting
/// the real filesystem via the HACacheManager singleton.
@protocol HACacheWriting <NSObject>

- (id)readJSONFromFile:(NSString *)filename;
- (void)writeJSON:(id)object toFile:(NSString *)filename completion:(void (^)(BOOL success))completion;
- (BOOL)writeJSONSync:(id)object toFile:(NSString *)filename;
- (NSString *)persistentCacheDirectory;

@end

/// Manages disk-based caching for dashboard config, entity states, and registries.
/// Cache directories are keyed by SHA256(serverURL) so switching servers loads
/// that server's cache automatically.
@interface HACacheManager : NSObject <HACacheWriting>

+ (instancetype)sharedManager;

/// The current server URL used for cache directory keying.
/// Must be set before any read/write operations (set on connect).
@property (nonatomic, copy) NSString *serverURL;

#pragma mark - File Operations

/// Read JSON from a cache file. Returns nil if file doesn't exist or parse fails.
- (id)readJSONFromFile:(NSString *)filename;

/// Write JSON-serializable object to a cache file asynchronously.
/// Calls completion on main queue (may be nil).
- (void)writeJSON:(id)object toFile:(NSString *)filename completion:(void (^)(BOOL success))completion;

/// Write JSON-serializable object to a cache file synchronously (for flush-on-resign).
- (BOOL)writeJSONSync:(id)object toFile:(NSString *)filename;

/// Delete a specific cache file.
- (void)deleteCacheFile:(NSString *)filename;

/// Delete all cache files for the current server.
- (void)clearAllCaches;

/// Delete cache directories for every server previously used by this app.
- (void)clearAllServerCaches;

#pragma mark - Paths

/// Returns the Application Support cache directory for the current server.
/// Creates the directory if it doesn't exist.
- (NSString *)persistentCacheDirectory;

/// Returns the Library/Caches directory for expendable data (history, camera frames).
- (NSString *)expendableCacheDirectory;

@end
