#import "HADashboardConfigCache.h"
#import "HALog.h"
#import "HACacheManager.h"
#import <CommonCrypto/CommonDigest.h>

@interface HADashboardConfigCache ()
/// In-memory hash of the last cached config per dashboard path, to avoid re-reading from disk.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *cachedHashes;
@end

@implementation HADashboardConfigCache

+ (instancetype)sharedCache {
    static HADashboardConfigCache *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HADashboardConfigCache alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cachedHashes = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - File Naming

- (NSString *)filenameForDashboard:(NSString *)dashboardPath {
    NSString *key = dashboardPath.length > 0 ? dashboardPath : @"_default";
    // Sanitize path for use as filename
    key = [key stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    return [NSString stringWithFormat:@"dashboard-config-%@.json", key];
}

- (NSString *)hashFilenameForDashboard:(NSString *)dashboardPath {
    NSString *key = dashboardPath.length > 0 ? dashboardPath : @"_default";
    key = [key stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    return [NSString stringWithFormat:@"dashboard-hash-%@.txt", key];
}

#pragma mark - Read

- (NSDictionary *)loadCachedConfigForDashboard:(NSString *)dashboardPath {
    NSString *filename = [self filenameForDashboard:dashboardPath];
    id json = [[HACacheManager sharedManager] readJSONFromFile:filename];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    HALogI(@"cache", @"Loaded cached dashboard config for '%@'", dashboardPath ?: @"default");
    return json;
}

- (BOOL)hasCachedConfigForDashboard:(NSString *)dashboardPath {
    NSString *dir = [[HACacheManager sharedManager] persistentCacheDirectory];
    if (!dir) return NO;
    NSString *filename = [self filenameForDashboard:dashboardPath];
    NSString *path = [dir stringByAppendingPathComponent:filename];
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

#pragma mark - Write with Hash Comparison

- (BOOL)cacheConfig:(NSDictionary *)config forDashboard:(NSString *)dashboardPath {
    if (!config) return NO;

    // Compute hash of new config
    NSError *error = nil;
    NSJSONWritingOptions writingOptions = 0;
    if (@available(iOS 11.0, *)) {
        writingOptions = NSJSONWritingSortedKeys;
    }
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:config
                                                      options:writingOptions
                                                        error:&error];
    if (!jsonData) {
        HALogE(@"cache", @"Failed to serialize dashboard config: %@", error.localizedDescription);
        return YES; // Assume changed if we can't serialize
    }

    NSString *newHash = [self sha256OfData:jsonData];
    NSString *cacheKey = dashboardPath ?: @"_default";

    // Compare with in-memory cached hash
    NSString *oldHash = self.cachedHashes[cacheKey];
    if (!oldHash) {
        // Try reading hash from disk
        oldHash = [self readHashForDashboard:dashboardPath];
    }

    BOOL changed = ![newHash isEqualToString:oldHash];

    if (changed) {
        // Write config and hash
        NSString *configFile = [self filenameForDashboard:dashboardPath];
        [[HACacheManager sharedManager] writeJSON:config toFile:configFile completion:^(BOOL success) {
            if (success) {
                HALogI(@"cache", @"Cached dashboard config for '%@'", dashboardPath ?: @"default");
            }
        }];
        [self writeHash:newHash forDashboard:dashboardPath];
        self.cachedHashes[cacheKey] = newHash;
    } else {
        HALogD(@"cache", @"Dashboard config unchanged for '%@', skipping write", dashboardPath ?: @"default");
    }

    return changed;
}

#pragma mark - Clear

- (void)clearCacheForDashboard:(NSString *)dashboardPath {
    NSString *configFile = [self filenameForDashboard:dashboardPath];
    NSString *hashFile = [self hashFilenameForDashboard:dashboardPath];
    [[HACacheManager sharedManager] deleteCacheFile:configFile];
    [[HACacheManager sharedManager] deleteCacheFile:hashFile];
    NSString *cacheKey = dashboardPath ?: @"_default";
    [self.cachedHashes removeObjectForKey:cacheKey];
}

#pragma mark - Private Hash Helpers

- (NSString *)sha256OfData:(NSData *)data {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", hash[i]];
    }
    return output;
}

- (NSString *)readHashForDashboard:(NSString *)dashboardPath {
    NSString *dir = [[HACacheManager sharedManager] persistentCacheDirectory];
    if (!dir) return nil;
    NSString *hashFile = [self hashFilenameForDashboard:dashboardPath];
    NSString *path = [dir stringByAppendingPathComponent:hashFile];
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

- (void)writeHash:(NSString *)hash forDashboard:(NSString *)dashboardPath {
    NSString *dir = [[HACacheManager sharedManager] persistentCacheDirectory];
    if (!dir || !hash) return;
    NSString *hashFile = [self hashFilenameForDashboard:dashboardPath];
    NSString *path = [dir stringByAppendingPathComponent:hashFile];
    [hash writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

@end
