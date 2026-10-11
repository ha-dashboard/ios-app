#import "HAClockCardFormatter.h"
#import "HAStrings.h"
#import "HAStateLocalizer.h"

// Each value token maps to the CLDR skeleton Intl.DateTimeFormat would use
// for the same single-field options (clock-date-format.ts DATE_PART_OPTIONS).
// Expanding the skeleton with +dateFormatFromTemplate: picks the same
// stand-alone forms Intl does ("LLLL"/"cccc") and any locale literals
// ("11日" in ja), rather than a hand-written pattern.
static NSDictionary<NSString *, NSString *> *HAClockDatePartTemplates(void) {
    static NSDictionary *templates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        templates = @{
            @"weekday-short": @"EEE",
            @"weekday-long":  @"EEEE",
            @"day-numeric":   @"d",
            @"day-2-digit":   @"dd",
            @"month-short":   @"MMM",
            @"month-long":    @"MMMM",
            @"month-numeric": @"M",
            @"month-2-digit": @"MM",
            @"year-2-digit":  @"yy",
            @"year-numeric":  @"y",
        };
    });
    return templates;
}

static NSDictionary<NSString *, NSString *> *HAClockDateSeparators(void) {
    static NSDictionary *separators = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        separators = @{
            @"separator-dash":     @"-",
            @"separator-slash":    @"/",
            @"separator-dot":      @".",
            @"separator-new-line": @"\n",
        };
    });
    return separators;
}

@implementation HAClockCardFormatter

+ (NSArray<NSString *> *)supportedDateParts {
    static NSArray *parts = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        parts = @[@"weekday-short", @"weekday-long", @"day-numeric", @"day-2-digit",
                  @"month-short", @"month-long", @"month-numeric", @"month-2-digit",
                  @"year-2-digit", @"year-numeric",
                  @"separator-dash", @"separator-slash", @"separator-dot", @"separator-new-line"];
    });
    return parts;
}

+ (NSArray<NSString *> *)normalizedDateParts:(id)rawParts {
    if (![rawParts isKindOfClass:[NSArray class]]) return @[];
    NSArray *supported = [self supportedDateParts];
    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:[(NSArray *)rawParts count]];
    for (id part in (NSArray *)rawParts) {
        if ([part isKindOfClass:[NSString class]] && [supported containsObject:part]) {
            [result addObject:part];
        }
    }
    return [result copy];
}

+ (NSString *)dateStringForDate:(NSDate *)date
                          parts:(NSArray<NSString *> *)parts
                         locale:(NSLocale *)locale
                       timeZone:(NSTimeZone *)timeZone {
    NSMutableString *result = [NSMutableString string];
    BOOL previousWasValue = NO;
    NSDictionary *separators = HAClockDateSeparators();
    NSDictionary *templates = HAClockDatePartTemplates();

    for (NSString *part in parts) {
        NSString *separator = separators[part];
        if (separator) {
            [result appendString:separator];
            previousWasValue = NO;
            continue;
        }
        NSString *template = templates[part];
        if (!template) continue;
        NSString *value = [self stringFromDate:date
                                        format:[self patternForTemplate:template locale:locale]
                                        locale:locale
                                      timeZone:timeZone];
        if (value.length == 0) continue;
        if (previousWasValue) [result appendString:@" "];
        [result appendString:value];
        previousWasValue = YES;
    }
    return [result copy];
}

+ (BOOL)usesTwelveHourClockForTimeFormat:(id)timeFormat languageLocale:(NSLocale *)languageLocale {
    NSString *format = nil;
    if ([timeFormat isKindOfClass:[NSString class]]) {
        format = timeFormat;
    } else if ([timeFormat isKindOfClass:[NSNumber class]]) {
        format = [timeFormat stringValue];
    }
    if ([format isEqualToString:@"12"]) return YES;
    if ([format isEqualToString:@"24"]) return NO;

    NSLocale *locale = [format isEqualToString:@"system"] ? [NSLocale autoupdatingCurrentLocale] : languageLocale;
    // "j" is the CLDR "preferred hour" skeleton: it expands to "HH"/"H" (or
    // "k") for 24-hour locales and to an "h"/"K" pattern for 12-hour ones.
    NSString *pattern = [NSDateFormatter dateFormatFromTemplate:@"j" options:0 locale:locale];
    if (pattern.length == 0) return NO;
    return [pattern rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"Hk"]].location == NSNotFound;
}

+ (NSTimeZone *)timeZoneForConfigValue:(id)value {
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        NSTimeZone *zone = [NSTimeZone timeZoneWithName:value];
        if (zone) return zone;
    }
    return [NSTimeZone localTimeZone];
}

+ (NSString *)currentLanguageCode {
    NSString *code = [HAStrings overrideLanguageCode];
    if (code.length == 0) code = [HAStateLocalizer sharedLocalizer].loadedLanguageCode;
    if (code.length == 0) code = [HAStateLocalizer lastResolvedLanguageCode];
    if (code.length == 0) code = [HAStrings activeLanguageCode];
    return [HAStateLocalizer normalizedLanguageCode:code];
}

+ (NSLocale *)localeForLanguageCode:(NSString *)languageCode {
    NSString *code = languageCode.length > 0 ? languageCode : @"en";
    return [NSLocale localeWithLocaleIdentifier:code];
}

+ (NSString *)stringFromDate:(NSDate *)date
                      format:(NSString *)format
                      locale:(NSLocale *)locale
                    timeZone:(NSTimeZone *)timeZone {
    static NSMutableDictionary<NSString *, NSDateFormatter *> *cache = nil;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", locale.localeIdentifier, timeZone.name, format];
    NSDateFormatter *formatter = cache[key];
    if (!formatter) {
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = locale;
        formatter.timeZone = timeZone;
        formatter.dateFormat = format;
        cache[key] = formatter;
    }
    return [formatter stringFromDate:date] ?: @"";
}

+ (NSArray<NSString *> *)amPmSymbolsForLocale:(NSLocale *)locale {
    static NSMutableDictionary<NSString *, NSArray *> *cache = nil;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSArray *symbols = cache[locale.localeIdentifier];
    if (!symbols) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = locale;
        symbols = @[formatter.AMSymbol ?: @"AM", formatter.PMSymbol ?: @"PM"];
        cache[locale.localeIdentifier] = symbols;
    }
    return symbols;
}

#pragma mark - Private

+ (NSString *)patternForTemplate:(NSString *)template locale:(NSLocale *)locale {
    static NSMutableDictionary<NSString *, NSString *> *cache = nil;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@|%@", locale.localeIdentifier, template];
    NSString *pattern = cache[key];
    if (!pattern) {
        pattern = [NSDateFormatter dateFormatFromTemplate:template options:0 locale:locale] ?: template;
        cache[key] = pattern;
    }
    return pattern;
}

@end
