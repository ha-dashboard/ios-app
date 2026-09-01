#import "HACacheManager.h"
#import "HALog.h"
#import <CommonCrypto/CommonDigest.h>

@interface HACacheManager ()
@property (nonatomic, strong) dispatch_queue_t writeQueue;
@property (nonatomic, copy) NSString *cachedServerHash;
@end

@implementation HACacheManager

+ (instancetype)sharedManager {
    static HACacheManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HACacheManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _writeQueue = dispatch_queue_create("com.hadashboard.cache.write", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Server URL Keying

- (void)setServerURL:(NSString *)serverURL {
    if ([_serverURL isEqualToString:serverURL]) return;
    _serverURL = [serverURL copy];
    _cachedServerHash = serverURL ? [self sha256:serverURL] : nil;
}

- (NSString *)sha256:(NSString *)input {
    const char *cstr = [input UTF8String];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(cstr, (CC_LONG)strlen(cstr), hash);
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < 8; i++) { // First 8 bytes (16 hex chars) is enough for keying
        [output appendFormat:@"%02x", hash[i]];
    }
    return output;
}

#pragma mark - Paths

- (NSString *)persistentCacheDirectory {
    if (!self.cachedServerHash) return nil;
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [appSupport stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"HACache/%@", self.cachedServerHash]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSString *)expendableCacheDirectory {
    if (!self.cachedServerHash) return nil;
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [caches stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"HACache/%@", self.cachedServerHash]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSString *)pathForFile:(NSString *)filename {
    NSString *dir = [self persistentCacheDirectory];
    if (!dir) return nil;
    return [dir stringByAppendingPathComponent:filename];
}

#pragma mark - File Operations

- (id)readJSONFromFile:(NSString *)filename {
    NSString *path = [self pathForFile:filename];
    if (!path) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;

    NSError *error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error) {
        HALogE(@"cache", @"Failed to parse %@: %@", filename, error.localizedDescription);
        // Corrupt cache — delete it
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return nil;
    }
    return json;
}

- (void)writeJSON:(id)object toFile:(NSString *)filename completion:(void (^)(BOOL))completion {
    NSString *path = [self pathForFile:filename];
    if (!path || !object) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        return;
    }

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (error || !data) {
        HALogE(@"cache", @"Failed to serialize %@: %@", filename, error.localizedDescription);
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        return;
    }

    dispatch_async(self.writeQueue, ^{
        BOOL ok = [data writeToFile:path atomically:YES];
        if (!ok) {
            HALogE(@"cache", @"Failed to write %@", path);
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(ok); });
        }
    });
}

- (BOOL)writeJSONSync:(id)object toFile:(NSString *)filename {
    NSString *path = [self pathForFile:filename];
    if (!path || !object) return NO;

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (error || !data) {
        HALogE(@"cache", @"Failed to serialize %@ (sync): %@", filename, error.localizedDescription);
        return NO;
    }
    return [data writeToFile:path atomically:YES];
}

- (void)deleteCacheFile:(NSString *)filename {
    NSString *path = [self pathForFile:filename];
    if (path) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

- (void)clearAllCaches {
    NSString *persistDir = [self persistentCacheDirectory];
    NSString *expendDir = [self expendableCacheDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (persistDir) [fm removeItemAtPath:persistDir error:nil];
    if (expendDir) [fm removeItemAtPath:expendDir error:nil];
}

- (void)clearAllServerCaches {
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *caches = [NSSearchPathForDirectoriesInDomains(
        NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    // Drain queued writes first so an older dashboard snapshot cannot recreate
    // the cache immediately after Log Out & Reset removes it.
    dispatch_sync(self.writeQueue, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        if (appSupport.length) {
            [fm removeItemAtPath:[appSupport stringByAppendingPathComponent:@"HACache"] error:nil];
        }
        if (caches.length) {
            [fm removeItemAtPath:[caches stringByAppendingPathComponent:@"HACache"] error:nil];
        }
    });
    self.serverURL = nil;
}

@end
