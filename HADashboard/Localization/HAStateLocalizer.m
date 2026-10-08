#import "HAStateLocalizer.h"
#import "HACacheManager.h"
#import "HAConnectionManager.h"
#import "HAStrings.h"
#import "HAEntityDisplayHelper.h"
#import "HALog.h"

static NSString *const kHAStateLocalizerCacheFilePrefix = @"ha-translations-";
static NSString *const kHAStateLocalizerCacheFileSuffix = @".json";
static const unsigned long long kHAStateLocalizerMaxPayloadBytes = 512 * 1024; // 512 KB, per plan §2.7
static const NSTimeInterval kHAStateLocalizerRefreshDebounceInterval = 24 * 60 * 60; // 24h, per plan §2.7

static BOOL HAStateLocalizerIsRunningUnderXCTest(void) {
    return NSClassFromString(@"XCTestCase") != nil;
}

@interface HAStateLocalizer ()
@property (nonatomic, copy, readwrite, nullable) NSString *loadedLanguageCode;
@property (nonatomic, copy, nullable) NSString *previousLanguageCode;
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NSString *> *resources;
@property (nonatomic, strong, nullable) NSDate *lastRefreshDate;
@end

@implementation HAStateLocalizer

+ (instancetype)sharedLocalizer {
    static HAStateLocalizer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HAStateLocalizer alloc] init];
    });
    return instance;
}

- (BOOL)hasResources {
    return self.resources.count > 0;
}

#pragma mark - Dotted key helpers

+ (NSString *)dottedKeyForDomain:(NSString *)domain deviceClass:(NSString *)deviceClass state:(NSString *)state {
    return [NSString stringWithFormat:@"component.%@.entity_component.%@.state.%@", domain, deviceClass, state];
}

+ (NSString *)dottedBucketKeyForDomain:(NSString *)domain state:(NSString *)state {
    return [self dottedKeyForDomain:domain deviceClass:@"_" state:state];
}

+ (NSString *)cacheFilenameForLanguage:(NSString *)languageCode {
    return [NSString stringWithFormat:@"%@%@%@", kHAStateLocalizerCacheFilePrefix, languageCode, kHAStateLocalizerCacheFileSuffix];
}

/// The onStates/offStates tables that used to live at
/// HAEntityDisplayHelper.m:100-153, deleted by docs/plans/i18n-plan.md §2.7.
/// Used ONLY as the final safety net when the localizer has no HA-fetched
/// data yet (first launch, offline, pre-auth) — this is what makes the
/// empty-localizer case byte-identical to the pre-Phase-2 implementation.
/// The moment real HA data loads (even from yesterday's cache) it shadows
/// this table entirely, since `-lookupKey:` always checks live resources
/// first.
+ (NSDictionary<NSString *, NSString *> *)legacyBinarySensorDefaults {
    static NSDictionary<NSString *, NSString *> *defaults = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary<NSString *, NSString *> *onStates = @{
            @"door":             @"Open",
            @"lock":             @"Unlocked",
            @"window":           @"Open",
            @"garage_door":      @"Open",
            @"opening":          @"Open",
            @"connectivity":     @"Connected",
            @"plug":             @"Plugged In",
            @"battery":          @"Low",
            @"battery_charging": @"Charging",
            @"motion":           @"Detected",
            @"occupancy":        @"Detected",
            @"moisture":         @"Wet",
            @"smoke":            @"Detected",
            @"problem":          @"Problem",
            @"safety":           @"Unsafe",
            @"running":          @"Running",
            @"update":           @"Update Available",
            @"presence":         @"Home",
            @"power":            @"On",
        };
        NSDictionary<NSString *, NSString *> *offStates = @{
            @"door":             @"Closed",
            @"lock":             @"Locked",
            @"window":           @"Closed",
            @"garage_door":      @"Closed",
            @"opening":          @"Closed",
            @"connectivity":     @"Disconnected",
            @"plug":             @"Unplugged",
            @"battery":          @"Normal",
            @"battery_charging": @"Not Charging",
            @"motion":           @"Clear",
            @"occupancy":        @"Clear",
            @"moisture":         @"Dry",
            @"smoke":            @"Clear",
            @"problem":          @"OK",
            @"safety":           @"Safe",
            @"running":          @"Not Running",
            @"update":           @"Up-to-date",
            @"presence":         @"Away",
            @"power":            @"Off",
        };
        NSMutableDictionary<NSString *, NSString *> *flat = [NSMutableDictionary dictionary];
        for (NSString *deviceClass in onStates) {
            flat[[self dottedKeyForDomain:@"binary_sensor" deviceClass:deviceClass state:@"on"]] = onStates[deviceClass];
        }
        for (NSString *deviceClass in offStates) {
            flat[[self dottedKeyForDomain:@"binary_sensor" deviceClass:deviceClass state:@"off"]] = offStates[deviceClass];
        }
        defaults = [flat copy];
    });
    return defaults;
}

#pragma mark - Consume

- (NSString *)localizedStateForDomain:(NSString *)domain
                           deviceClass:(NSString *)deviceClass
                              platform:(NSString *)platform
                        translationKey:(NSString *)translationKey
                                 state:(NSString *)state {
    if (state == nil) return state;

    // Checked FIRST, before any HA-sourced lookup — HA does not serve these
    // over the WebSocket either (plan §2.3); they are app-owned keys that
    // must match the app's pre-Phase-2 text exactly.
    if ([state isEqualToString:@"unavailable"]) {
        return HALocalizedString(@"state.default.unavailable", @"Shown for an entity Home Assistant reports as unavailable.");
    }
    if ([state isEqualToString:@"unknown"]) {
        return HALocalizedString(@"state.default.unknown", @"Shown for an entity Home Assistant reports as unknown.");
    }

    if (domain.length > 0) {
        // Rung 1 of the §2.2 chain (category `entity`, keyed by
        // platform+translationKey) is deliberately not fetched in Phase 2 —
        // see plan §2.7 "Recommendation". platform/translationKey are
        // accepted here only so this signature doesn't need to change again
        // if a future Phase 2b adds that fetch.
        (void)platform;
        (void)translationKey;

        NSString *deviceClassKey = deviceClass.length > 0
            ? [[self class] dottedKeyForDomain:domain deviceClass:deviceClass state:state]
            : nil;
        NSString *bucketKey = [[self class] dottedBucketKeyForDomain:domain state:state];

        // Rungs 2 and 3: live/cached HA data always wins outright, over
        // EITHER rung, before the legacy fallback table is even consulted —
        // otherwise a device_class our legacy table happens to know about
        // would shadow HA's own (possibly different, possibly non-English)
        // translation of the generic `_` bucket.
        if (deviceClassKey) {
            NSString *liveHit = self.resources[deviceClassKey];
            if (liveHit.length > 0) return liveHit;
        }
        NSString *liveBucketHit = self.resources[bucketKey];
        if (liveBucketHit.length > 0) return liveBucketHit;

        // No live data for this key at all — fall back to the legacy
        // binary_sensor defaults (the pre-Phase-2 English table). This is
        // what makes the empty-localizer case byte-identical to how the app
        // behaved before this class existed.
        if (deviceClassKey) {
            NSString *legacyHit = [[self class] legacyBinarySensorDefaults][deviceClassKey];
            if (legacyHit.length > 0) return legacyHit;
        }
    }

    NSString *human = [HAEntityDisplayHelper humanReadableState:state];
    if (human.length > 0) return human;

    return state;
}

#pragma mark - Cache load (sync, launch-time)

- (void)loadCachedStateForLanguage:(NSString *)languageCode {
    if (HAStateLocalizerIsRunningUnderXCTest()) return;

    NSString *normalized = [[self class] normalizedLanguageCode:languageCode];
    NSString *filename = [[self class] cacheFilenameForLanguage:normalized];
    id json = [[HACacheManager sharedManager] readJSONFromFile:filename];
    NSDictionary<NSString *, NSString *> *validated = [self validatedResourcesFromJSON:json];
    if (!validated) return;

    self.resources = validated;
    self.loadedLanguageCode = normalized;
    self.lastRefreshDate = [NSDate date];
    HALogI(@"i18n", @"Loaded cached HA translations for '%@': %lu keys", normalized, (unsigned long)validated.count);
}

#pragma mark - Fetch (async, over the existing connect sequence)

- (void)refreshForLanguage:(NSString *)languageCode
          connectionManager:(HAConnectionManager *)connectionManager {
    if (HAStateLocalizerIsRunningUnderXCTest()) return;
    if (!connectionManager) return;

    NSString *normalized = [[self class] normalizedLanguageCode:languageCode];

    // Debounce: don't refetch on every reconnect if the cache we already
    // hold for this exact language is still fresh.
    if ([self.loadedLanguageCode isEqualToString:normalized] && self.lastRefreshDate &&
        -[self.lastRefreshDate timeIntervalSinceNow] < kHAStateLocalizerRefreshDebounceInterval) {
        return;
    }

    NSDictionary *command = @{
        @"type": @"frontend/get_translations",
        @"language": normalized,
        @"category": @"entity_component",
    };

    __weak typeof(self) weakSelf = self;
    [connectionManager sendCommand:command completion:^(id result, NSError *error) {
        HAStateLocalizer *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) {
            HALogW(@"i18n", @"frontend/get_translations('%@') failed: %@", normalized, error.localizedDescription);
            return;
        }

        NSDictionary *resourcesField = nil;
        if ([result isKindOfClass:[NSDictionary class]]) {
            id res = result[@"resources"];
            if ([res isKindOfClass:[NSDictionary class]]) resourcesField = res;
        }
        NSDictionary<NSString *, NSString *> *validated = [strongSelf validatedResourcesFromJSON:resourcesField];
        if (!validated) {
            // Empty/oversized response — e.g. an unavailable language per
            // plan §2.6. Keep whatever we already have (possibly nothing);
            // every lookup degrades gracefully regardless.
            HALogW(@"i18n", @"frontend/get_translations('%@') returned no usable resources", normalized);
            return;
        }

        NSString *oldCurrent = strongSelf.loadedLanguageCode;
        strongSelf.resources = validated;
        strongSelf.loadedLanguageCode = normalized;
        strongSelf.lastRefreshDate = [NSDate date];
        if (oldCurrent.length > 0 && ![oldCurrent isEqualToString:normalized]) {
            strongSelf.previousLanguageCode = oldCurrent;
        }

        [strongSelf cacheResources:validated forLanguage:normalized];
    }];
}

- (nullable NSDictionary<NSString *, NSString *> *)validatedResourcesFromJSON:(id)json {
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *dict = (NSDictionary *)json;

    NSMutableDictionary<NSString *, NSString *> *validated = [NSMutableDictionary dictionaryWithCapacity:dict.count];
    for (id key in dict) {
        id value = dict[key];
        if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]]) {
            validated[key] = value;
        }
    }
    if (validated.count == 0) return nil;

    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:validated options:0 error:&jsonError];
    if (!data || jsonError) return nil;
    if (data.length > kHAStateLocalizerMaxPayloadBytes) {
        HALogW(@"i18n", @"Discarding HA translations payload of %lu bytes (over the 512 KB cap)", (unsigned long)data.length);
        return nil;
    }
    return validated;
}

#pragma mark - Caching (persistent, 2-language cap)

- (void)cacheResources:(NSDictionary<NSString *, NSString *> *)resources forLanguage:(NSString *)languageCode {
    NSString *filename = [[self class] cacheFilenameForLanguage:languageCode];
    [[HACacheManager sharedManager] writeJSON:resources toFile:filename completion:^(BOOL success) {
        if (!success) {
            HALogW(@"i18n", @"Failed to write HA translations cache for '%@'", languageCode);
        }
    }];
    [self evictStaleCachedLanguages];
}

- (void)evictStaleCachedLanguages {
    NSString *dir = [[HACacheManager sharedManager] persistentCacheDirectory];
    if (!dir) return;

    NSMutableSet<NSString *> *keep = [NSMutableSet set];
    if (self.loadedLanguageCode.length > 0) [keep addObject:self.loadedLanguageCode];
    if (self.previousLanguageCode.length > 0) [keep addObject:self.previousLanguageCode];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *entry in entries) {
        if (![entry hasPrefix:kHAStateLocalizerCacheFilePrefix] || ![entry hasSuffix:kHAStateLocalizerCacheFileSuffix]) continue;
        NSString *lang = entry;
        lang = [lang substringFromIndex:kHAStateLocalizerCacheFilePrefix.length];
        lang = [lang substringToIndex:lang.length - kHAStateLocalizerCacheFileSuffix.length];
        if (![keep containsObject:lang]) {
            [fm removeItemAtPath:[dir stringByAppendingPathComponent:entry] error:nil];
        }
    }
}

#pragma mark - Language resolution (pure — no network, no I/O)

+ (NSString *)normalizedLanguageCode:(NSString *)code {
    NSString *trimmed = [[code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
    if (trimmed.length == 0) return @"en";

    NSRange separator = [trimmed rangeOfString:@"-"];
    if (separator.location == NSNotFound) separator = [trimmed rangeOfString:@"_"];
    NSString *bare = (separator.location != NSNotFound) ? [trimmed substringToIndex:separator.location] : trimmed;
    if (bare.length == 0) return @"en";

    static NSSet<NSString *> *validCodes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        validCodes = [NSSet setWithArray:[NSLocale ISOLanguageCodes]];
    });
    if (![validCodes containsObject:bare]) return @"en";
    return bare;
}

+ (NSString *)resolveLanguageWithOverride:(NSString *)overrideLanguageCode
                          userDataLanguage:(NSString *)userDataLanguage
                            configLanguage:(NSString *)configLanguage
                         appChromeLanguage:(NSString *)appChromeLanguage {
    NSString *chosen = overrideLanguageCode.length > 0 ? overrideLanguageCode : nil;
    if (!chosen) chosen = userDataLanguage.length > 0 ? userDataLanguage : nil;
    if (!chosen) chosen = configLanguage.length > 0 ? configLanguage : nil;
    if (!chosen) chosen = appChromeLanguage.length > 0 ? appChromeLanguage : nil;
    return [self normalizedLanguageCode:chosen];
}

#pragma mark - Test support

- (void)test_setResources:(NSDictionary<NSString *, NSString *> *)resources
              languageCode:(NSString *)languageCode {
    self.resources = resources;
    self.loadedLanguageCode = languageCode;
    self.previousLanguageCode = nil;
    self.lastRefreshDate = resources ? [NSDate date] : nil;
}

@end
