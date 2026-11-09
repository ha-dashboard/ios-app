#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Locale, time-zone and date-part formatting for the built-in Home
/// Assistant `clock` card (HAClockCardCell). A port of the frontend's
/// `clock-date-format.ts` plus the `useAmPm` / time-zone resolution used by
/// `hui-clock-card-digital.ts` and `hui-clock-card-analog.ts`.
///
/// Formatters are cached per locale/time zone/pattern. Main thread only, like
/// every other UI formatter in the app.
@interface HAClockCardFormatter : NSObject

/// Every `date_format` token the HA card editor offers, in editor order.
+ (NSArray<NSString *> *)supportedDateParts;

/// Filters a raw `date_format` config value down to recognised tokens,
/// preserving their literal order (HA `normalizeDateParts`). Anything that is
/// not an array of strings yields an empty array.
+ (NSArray<NSString *> *)normalizedDateParts:(nullable id)rawParts;

/// Builds the date string from `parts` exactly like HA `formatClockCardDate`:
/// each value token is localised on its own, separators (`-`, `/`, `.`, and a
/// newline) are inserted literally, and a single space is only inserted
/// between two adjacent value tokens. Returns @"" for no parts.
+ (NSString *)dateStringForDate:(NSDate *)date
                          parts:(NSArray<NSString *> *)parts
                         locale:(NSLocale *)locale
                       timeZone:(NSTimeZone *)timeZone;

/// HA `useAmPm`: YES for a 12-hour clock. `timeFormat` is the card's
/// `time_format` ("12", "24", "language", "system"; numbers accepted).
/// "language" (and a missing/unknown value, matching HA's profile default)
/// asks `languageLocale`; "system" asks the device's current locale, which
/// honours the iOS 24-Hour Time switch.
+ (BOOL)usesTwelveHourClockForTimeFormat:(nullable id)timeFormat
                          languageLocale:(NSLocale *)languageLocale;

/// The card's `time_zone` as an NSTimeZone. An IANA name ("Europe/Paris")
/// resolves directly; anything else — nil, "local", "server" (the app does
/// not track the HA server's configured zone), or an unknown name — falls
/// back to the device's local time zone.
+ (NSTimeZone *)timeZoneForConfigValue:(nullable id)value;

/// The Home Assistant content language the app is currently rendering in
/// (in-app override, then the HA profile/config language last resolved by
/// HAStateLocalizer, then the app chrome language), as a bare code ("fr").
+ (NSString *)currentLanguageCode;

/// An NSLocale for a HA language code ("fr", "en-GB", "pt_BR"). Falls back to
/// "en" for nil/empty input.
+ (NSLocale *)localeForLanguageCode:(nullable NSString *)languageCode;

/// Formats `date` with an explicit `dateFormat` pattern through a cached
/// formatter for `locale` + `timeZone`.
+ (NSString *)stringFromDate:(NSDate *)date
                      format:(NSString *)format
                      locale:(NSLocale *)locale
                    timeZone:(NSTimeZone *)timeZone;

/// The locale's AM/PM symbols, in that order.
+ (NSArray<NSString *> *)amPmSymbolsForLocale:(NSLocale *)locale;

@end

NS_ASSUME_NONNULL_END
