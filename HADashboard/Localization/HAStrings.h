#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Looks up `key` in the active localisation bundle (the in-app override bundle
/// when one is set, else the main bundle) and falls back to `en` when the active
/// bundle has no value for the key. `comment` is unused at runtime; it exists so
/// `genstrings -s HALocalizedString` (and human readers) can still extract it.
#define HALocalizedString(key, comment) [HAStrings localizedStringForKey:(key)]

/// Plural variant, backed by Localizable.stringsdict via `NSString(format:)`.
#define HALocalizedPlural(key, count) [HAStrings localizedPluralForKey:(key) count:(count)]

/// Resolves app-chrome strings against an overridable language bundle.
///
/// Three-tier fallback, matching docs/plans/i18n-plan.md §1.5-§1.6:
///   1. The in-app override bundle (HASettingsViewController language picker), if set.
///   2. `[NSBundle mainBundle]`'s own iOS-negotiated `preferredLocalizations`.
///   3. `en.lproj`, loaded directly, as a last-resort safety net.
///
/// The override is a bundle swap, not an `AppleLanguages` rewrite, so it takes
/// effect on the next view reload with no relaunch required.
@interface HAStrings : NSObject

/// All language codes actually present in the app bundle as `<code>.lproj`,
/// sorted with `en` first. Drives the Settings language picker so new `.lproj`
/// folders (e.g. a future `fr.lproj`) show up automatically with no code change.
+ (NSArray<NSString *> *)availableLanguageCodes;

/// The in-app override language code (e.g. "fr"), or nil for "System default".
/// Persisted via HAAuthManager so it survives relaunch.
@property (class, nonatomic, copy, nullable) NSString *overrideLanguageCode;

/// The bundle currently used to resolve strings: the override bundle if set,
/// else the main bundle. Exposed for callers (HAStateLocalizer) that need to
/// resolve the *effective* language code rather than just app strings.
+ (NSBundle *)activeBundle;

/// The effective two-letter-ish language code in use right now, taking the
/// override into account. Never nil; falls back to "en".
+ (NSString *)activeLanguageCode;

+ (NSString *)localizedStringForKey:(NSString *)key;
+ (NSString *)localizedPluralForKey:(NSString *)key count:(NSInteger)count;

/// Human-readable endonym for a language code, used in the Settings picker
/// ("Français" rather than "French"). Falls back to the code itself if the
/// device has no name for it.
+ (NSString *)displayNameForLanguageCode:(NSString *)code;

@end

NS_ASSUME_NONNULL_END
