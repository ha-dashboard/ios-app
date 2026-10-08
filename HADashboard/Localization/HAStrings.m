#import "HAStrings.h"

static NSString *const kHAOverrideLanguageDefaultsKey = @"ha_override_language_code";

@implementation HAStrings

#pragma mark - Override language

+ (NSString *)overrideLanguageCode {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kHAOverrideLanguageDefaultsKey];
}

+ (void)setOverrideLanguageCode:(NSString *)languageCode {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (languageCode.length > 0) {
        [defaults setObject:languageCode forKey:kHAOverrideLanguageDefaultsKey];
    } else {
        [defaults removeObjectForKey:kHAOverrideLanguageDefaultsKey];
    }
    [defaults synchronize];
}

#pragma mark - Bundle resolution

+ (NSArray<NSString *> *)availableLanguageCodes {
    NSMutableArray<NSString *> *codes = [NSMutableArray array];
    NSArray<NSString *> *lprojPaths = [[NSBundle mainBundle] pathsForResourcesOfType:@"lproj" inDirectory:nil];
    for (NSString *path in lprojPaths) {
        NSString *code = [[path lastPathComponent] stringByDeletingPathExtension];
        // Base.lproj (storyboards) is not a spoken language; skip it.
        if ([code isEqualToString:@"Base"]) {
            continue;
        }
        if (code.length > 0 && ![codes containsObject:code]) {
            [codes addObject:code];
        }
    }
    [codes sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        if ([a isEqualToString:@"en"]) return NSOrderedAscending;
        if ([b isEqualToString:@"en"]) return NSOrderedDescending;
        return [a compare:b];
    }];
    return codes;
}

+ (NSBundle *)activeBundle {
    NSString *override = [self overrideLanguageCode];
    if (override.length > 0) {
        NSString *path = [[NSBundle mainBundle] pathForResource:override ofType:@"lproj"];
        if (path) {
            NSBundle *bundle = [NSBundle bundleWithPath:path];
            if (bundle) {
                return bundle;
            }
        }
    }
    return [NSBundle mainBundle];
}

+ (NSString *)activeLanguageCode {
    NSString *override = [self overrideLanguageCode];
    if (override.length > 0) {
        return override;
    }
    NSString *preferred = [[NSBundle mainBundle] preferredLocalizations].firstObject;
    return preferred.length > 0 ? preferred : @"en";
}

#pragma mark - Lookup

+ (NSBundle *)enBundleFallback {
    static NSBundle *enBundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"en" ofType:@"lproj"];
        enBundle = path ? [NSBundle bundleWithPath:path] : [NSBundle mainBundle];
    });
    return enBundle;
}

+ (NSString *)localizedStringForKey:(NSString *)key {
    if (key.length == 0) {
        return @"";
    }
    NSBundle *bundle = [self activeBundle];
    NSString *value = [bundle localizedStringForKey:key value:nil table:@"Localizable"];
    if (value && ![value isEqualToString:key]) {
        return value;
    }
    // Miss in the active (override) bundle — fall back to en before giving up,
    // so a key present in en but not yet translated degrades gracefully.
    if (bundle != [self enBundleFallback]) {
        NSString *enValue = [[self enBundleFallback] localizedStringForKey:key value:nil table:@"Localizable"];
        if (enValue && ![enValue isEqualToString:key]) {
            return enValue;
        }
    }
#if DEBUG
    NSLog(@"[HAStrings] Missing localisation key: %@", key);
#endif
    return key;
}

+ (NSString *)localizedPluralForKey:(NSString *)key count:(NSInteger)count {
    NSBundle *bundle = [self activeBundle];
    NSString *format = [bundle localizedStringForKey:key value:nil table:@"Localizable"];
    if (!format || [format isEqualToString:key]) {
        bundle = [self enBundleFallback];
        format = [bundle localizedStringForKey:key value:nil table:@"Localizable"];
    }
    if (!format || [format isEqualToString:key]) {
        return key;
    }
    return [NSString stringWithFormat:format, count];
}

+ (NSString *)displayNameForLanguageCode:(NSString *)code {
    if ([code isEqualToString:@"en"]) {
        return @"English";
    }
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:code];
    NSString *name = [locale displayNameForKey:NSLocaleIdentifier value:code];
    return name.length > 0 ? [name capitalizedStringWithLocale:locale] : code;
}

@end
