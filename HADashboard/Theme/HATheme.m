#import "HATheme.h"
#import "HASunBasedTheme.h"

NSString *const HAThemeDidChangeNotification = @"HAThemeDidChangeNotification";

static NSString *const kThemeModeKey       = @"ha_theme_mode";
static NSString *const kGradientEnabledKey = @"ha_gradient_enabled";
static NSString *const kGradientPresetKey  = @"ha_gradient_preset";
static NSString *const kCustomHex1Key      = @"ha_grad_custom_hex1";
static NSString *const kCustomHex2Key      = @"ha_grad_custom_hex2";
static NSString *const kMigratedV2Key      = @"ha_theme_migrated_v2";
static NSString *const kForceSunEntityKey  = @"ha_force_sun_entity";

@implementation HATheme

#pragma mark - Theme Mode

+ (HAThemeMode)currentMode {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    // One-time migration from old 4-value enum (Auto=0, Gradient=1, Dark=2, Light=3)
    // to new 3-value enum (Auto=0, Dark=1, Light=2) + separate gradient bool.
    if (![ud boolForKey:kMigratedV2Key]) {
        NSInteger stored = [ud integerForKey:kThemeModeKey];
        switch (stored) {
            case 1: // old HAThemeModeGradient → Dark + gradient on
                [ud setInteger:1 forKey:kThemeModeKey]; // new HAThemeModeDark
                [ud setBool:YES forKey:kGradientEnabledKey];
                break;
            case 2: // old HAThemeModeDark → new HAThemeModeDark (1)
                [ud setInteger:1 forKey:kThemeModeKey];
                break;
            case 3: // old HAThemeModeLight → new HAThemeModeLight (2)
                [ud setInteger:2 forKey:kThemeModeKey];
                break;
            default: // 0 = Auto, unchanged
                break;
        }
        [ud setBool:YES forKey:kMigratedV2Key];
        [ud synchronize];
    }

    return (HAThemeMode)[ud integerForKey:kThemeModeKey];
}

+ (void)setCurrentMode:(HAThemeMode)mode {
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kThemeModeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self applyInterfaceStyle];
    [[NSNotificationCenter defaultCenter] postNotificationName:HAThemeDidChangeNotification object:nil];
}

+ (BOOL)forceSunEntity {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kForceSunEntityKey];
}

+ (void)setForceSunEntity:(BOOL)force {
    [[NSUserDefaults standardUserDefaults] setBool:force forKey:kForceSunEntityKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    // Start the sun entity tracker if it wasn't already running (it no-ops on
    // iOS 13+ unless forceSunEntity is enabled, so needs a kick here).
    if (force) {
        [[HASunBasedTheme sharedInstance] start];
    }
    [self applyInterfaceStyle];
    [[NSNotificationCenter defaultCenter] postNotificationName:HAThemeDidChangeNotification object:nil];
}

#pragma mark - Gradient Enabled

+ (BOOL)isGradientEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kGradientEnabledKey];
}

+ (void)setGradientEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kGradientEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:HAThemeDidChangeNotification object:nil];
}

+ (UIBlurEffectStyle)gradientBlurStyle {
    return [self effectiveDarkMode] ? UIBlurEffectStyleDark : UIBlurEffectStyleLight;
}

#pragma mark - Gradient Presets

+ (HAGradientPreset)gradientPreset {
    return (HAGradientPreset)[[NSUserDefaults standardUserDefaults] integerForKey:kGradientPresetKey];
}

+ (void)setGradientPreset:(HAGradientPreset)preset {
    [[NSUserDefaults standardUserDefaults] setInteger:preset forKey:kGradientPresetKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:HAThemeDidChangeNotification object:nil];
}

+ (NSArray<UIColor *> *)gradientColors {
    BOOL dark = [self effectiveDarkMode];
    HAGradientPreset preset = [self gradientPreset];
    switch (preset) {
        case HAGradientPresetPurpleDream:
            return dark
                ? @[[self colorFromHex:@"1a0533"], [self colorFromHex:@"2d1b69"], [self colorFromHex:@"0f0f2e"]]
                : @[[self colorFromHex:@"f0e6ff"], [self colorFromHex:@"e0d0f5"], [self colorFromHex:@"f5f0ff"]];
        case HAGradientPresetOceanBlue:
            return dark
                ? @[[self colorFromHex:@"0c2340"], [self colorFromHex:@"1a4a7a"], [self colorFromHex:@"0a1628"]]
                : @[[self colorFromHex:@"e0f0ff"], [self colorFromHex:@"c8e0f5"], [self colorFromHex:@"f0f5ff"]];
        case HAGradientPresetSunset:
            return dark
                ? @[[self colorFromHex:@"2d1f3d"], [self colorFromHex:@"6b2f4a"], [self colorFromHex:@"1a1020"]]
                : @[[self colorFromHex:@"fff0e6"], [self colorFromHex:@"ffe0d0"], [self colorFromHex:@"fff5f0"]];
        case HAGradientPresetForest:
            return dark
                ? @[[self colorFromHex:@"0d2818"], [self colorFromHex:@"1a4a2e"], [self colorFromHex:@"0a1a10"]]
                : @[[self colorFromHex:@"e6ffe0"], [self colorFromHex:@"d0f5c8"], [self colorFromHex:@"f0fff0"]];
        case HAGradientPresetMidnight:
            return dark
                ? @[[self colorFromHex:@"0a0a1a"], [self colorFromHex:@"1a1a2e"], [self colorFromHex:@"050510"]]
                : @[[self colorFromHex:@"f0f0ff"], [self colorFromHex:@"e8e8f5"], [self colorFromHex:@"f5f5ff"]];
        case HAGradientPresetCustom: {
            NSString *h1 = [self customGradientHex1] ?: @"1a0533";
            NSString *h2 = [self customGradientHex2] ?: @"0f0f2e";
            return @[[self colorFromHex:h1], [self colorFromHex:h2]];
        }
    }
    return dark
        ? @[[self colorFromHex:@"1a0533"], [self colorFromHex:@"0f0f2e"]]
        : @[[self colorFromHex:@"f0e6ff"], [self colorFromHex:@"f5f0ff"]];
}

+ (void)setCustomGradientHex1:(NSString *)hex1 hex2:(NSString *)hex2 {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:hex1 forKey:kCustomHex1Key];
    [ud setObject:hex2 forKey:kCustomHex2Key];
    [ud synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:HAThemeDidChangeNotification object:nil];
}

+ (NSString *)customGradientHex1 {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kCustomHex1Key];
}

+ (NSString *)customGradientHex2 {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kCustomHex2Key];
}

#pragma mark - Interface Style

+ (void)applyInterfaceStyle {
    if (@available(iOS 13.0, *)) {
        UIWindow *window = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { window = w; break; }
                }
                if (window) break;
            }
        }
        if (!window) {
            // Fallback for early launch or iOS 13.0-13.3
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            window = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
        }
        if (!window) return;

        HAThemeMode mode = [self currentMode];
        switch (mode) {
            case HAThemeModeLight:
                window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
                break;
            case HAThemeModeDark:
                window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
                break;
            case HAThemeModeAuto:
            default:
                if ([self forceSunEntity]) {
                    // Override window style to match sun entity state so UIKit
                    // controls (status bar, switches) stay consistent.
                    window.overrideUserInterfaceStyle = [self effectiveDarkMode]
                        ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
                } else {
                    window.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
                }
                break;
        }
    }
}

#pragma mark - Dark Mode Detection

+ (BOOL)isDarkMode {
    return [self effectiveDarkMode];
}

+ (BOOL)effectiveDarkMode {
    HAThemeMode mode = [self currentMode];
    if (mode == HAThemeModeDark) return YES;
    if (mode == HAThemeModeLight) return NO;
    // Auto — follow system on iOS 13+, sun entity on iOS 9-12.
    // "Force Sun Entity" overrides system dark mode with HA sun.sun state,
    // useful when the device doesn't respect system appearance settings.
    // Use NSProcessInfo instead of @available because @available checks the
    // SDK version on RosettaSim x86_64 simulators, returning YES on iOS 9.3.
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 13
        && ![self forceSunEntity]) {
        if (@available(iOS 13.0, *)) {
            return [UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark;
        }
    }
    return [HASunBasedTheme sharedInstance].isSunBelowHorizon;
}

#pragma mark - Utility

+ (UIColor *)colorFromHex:(NSString *)hex {
    NSString *clean = [hex stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"# "]];
    if (clean.length != 6) return [UIColor blackColor];

    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    [scanner scanHexInt:&rgb];

    CGFloat r = ((rgb >> 16) & 0xFF) / 255.0;
    CGFloat g = ((rgb >> 8)  & 0xFF) / 255.0;
    CGFloat b = (rgb & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
}

+ (UIColor *)colorFromString:(NSString *)colorString {
    if (!colorString || ![colorString isKindOfClass:[NSString class]]) return nil;
    NSString *lower = [colorString lowercaseString];

    // Named colors
    static NSDictionary *namedColors = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        namedColors = @{
            @"green":  [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0],
            @"yellow": [UIColor colorWithRed:1.00 green:0.85 blue:0.00 alpha:1.0],
            @"red":    [UIColor colorWithRed:0.95 green:0.20 blue:0.20 alpha:1.0],
            @"orange": [UIColor colorWithRed:1.00 green:0.60 blue:0.00 alpha:1.0],
            @"blue":   [UIColor colorWithRed:0.30 green:0.60 blue:1.00 alpha:1.0],
            @"purple": [UIColor colorWithRed:0.60 green:0.30 blue:0.90 alpha:1.0],
            @"teal":   [UIColor colorWithRed:0.00 green:0.80 blue:0.70 alpha:1.0],
            @"grey":   [UIColor grayColor],
            @"gray":   [UIColor grayColor],
            @"white":  [UIColor whiteColor],
            @"black":  [UIColor blackColor],
            @"cyan":   [UIColor cyanColor],
            @"pink":   [UIColor colorWithRed:0.90 green:0.40 blue:0.70 alpha:1.0],
            @"indigo": [UIColor colorWithRed:0.25 green:0.32 blue:0.71 alpha:1.0],
            @"amber":  [UIColor colorWithRed:1.00 green:0.76 blue:0.03 alpha:1.0],
        };
    });

    UIColor *named = namedColors[lower];
    if (named) return named;

    // Hex color (with or without # prefix)
    return [self colorFromHex:colorString];
}

#pragma mark - Color Helpers

/// Resolves a color based on the current theme mode.
/// Auto: iOS 13+ dynamic provider, light on iOS 9-12.
/// Light: always light. Dark/Gradient: always dark.
+ (UIColor *)colorWithLight:(UIColor *)light dark:(UIColor *)dark {
    // On real iOS 13+, return dynamic colors that auto-resolve on trait
    // changes.  On iOS 9-12 (including RosettaSim), resolve statically —
    // the sun-based theme posts HAThemeDidChangeNotification to trigger
    // manual refreshes.  Use NSProcessInfo instead of @available because
    // @available misreports on RosettaSim legacy simulators.
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 13) {
        if (@available(iOS 13.0, *)) {
            return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
                return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
            }];
        }
    }
    return [self effectiveDarkMode] ? dark : light;
}

/// Three-arg variant: when gradient is enabled, uses a special color (e.g. semi-transparent).
/// The gradient color adapts to the effective appearance (caller provides dark gradient variant;
/// light variant is derived automatically or caller can provide both).
+ (UIColor *)colorWithLight:(UIColor *)light dark:(UIColor *)dark gradient:(UIColor *)gradient {
    return [self colorWithLight:light dark:dark gradientLight:gradient gradientDark:gradient];
}

/// Four-arg variant: separate gradient colors for light and dark appearance.
+ (UIColor *)colorWithLight:(UIColor *)light dark:(UIColor *)dark
               gradientLight:(UIColor *)gradientLight gradientDark:(UIColor *)gradientDark {
    if (![self isGradientEnabled]) return [self colorWithLight:light dark:dark];
    UIColor *gColor = [self effectiveDarkMode] ? gradientDark : gradientLight;
    // On iOS 13+, wrap in dynamic provider so trait changes resolve correctly
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 13) {
        if (@available(iOS 13.0, *)) {
            return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
                return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? gradientDark : gradientLight;
            }];
        }
    }
    return gColor;
}

#pragma mark - Backgrounds

+ (UIColor *)backgroundColor {
    return [self colorWithLight:[UIColor colorWithWhite:0.95 alpha:1.0]
                           dark:[UIColor colorWithRed:0.07 green:0.07 blue:0.09 alpha:1.0]];
}

+ (UIColor *)cellBackgroundColor {
    // Cells always use UIVisualEffectView blur as backgroundView,
    // so the contentView background is clear (content renders over the blur).
    return [UIColor clearColor];
}

/// Badge pill background — semi-transparent to match the frosted blur appearance of card cells.
/// Card cells use UIVisualEffectView (set by willDisplayCell), but individual badge views inside
/// HABadgeRowCell can't reliably host blur views across iOS 9-26. A matched alpha color gives
/// the same visual result on small pill shapes.
+ (UIColor *)badgeBackgroundColor {
    return [self effectiveDarkMode]
        ? [UIColor colorWithWhite:0.12 alpha:0.65]
        : [UIColor colorWithWhite:1.0 alpha:0.65];
}

+ (UIColor *)cellBorderColor {
    return [self colorWithLight:[UIColor colorWithWhite:0.88 alpha:1.0]
                           dark:[UIColor clearColor]];
}

#pragma mark - Text

+ (UIColor *)primaryTextColor {
    return [self colorWithLight:[UIColor darkTextColor]
                           dark:[UIColor colorWithWhite:0.93 alpha:1.0]];
}

+ (UIColor *)secondaryTextColor {
    return [self colorWithLight:[UIColor grayColor]
                           dark:[UIColor colorWithWhite:0.6 alpha:1.0]];
}

+ (UIColor *)tertiaryTextColor {
    return [self colorWithLight:[UIColor lightGrayColor]
                           dark:[UIColor colorWithWhite:0.4 alpha:1.0]];
}

#pragma mark - Semantic

+ (UIColor *)accentColor {
    return [self colorWithLight:[UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0]
                           dark:[UIColor colorWithRed:0.35 green:0.6 blue:1.0 alpha:1.0]];
}

+ (UIColor *)switchTintColor {
    if (![self isGradientEnabled]) {
        return [self accentColor];
    }
    // Brighter accent derived from each gradient preset
    switch ([self gradientPreset]) {
        case HAGradientPresetPurpleDream: return [self colorFromHex:@"9b6dff"];
        case HAGradientPresetOceanBlue:   return [self colorFromHex:@"4d9de0"];
        case HAGradientPresetSunset:      return [self colorFromHex:@"e07850"];
        case HAGradientPresetForest:      return [self colorFromHex:@"4dbd6a"];
        case HAGradientPresetMidnight:    return [self colorFromHex:@"7070cc"];
        case HAGradientPresetCustom: {
            // Use the first custom gradient color brightened
            NSArray<UIColor *> *colors = [self gradientColors];
            return colors.count > 0 ? colors[0] : [self accentColor];
        }
    }
    return [self accentColor];
}

+ (UIColor *)destructiveColor {
    return [self colorWithLight:[UIColor colorWithRed:0.85 green:0.2 blue:0.2 alpha:1.0]
                           dark:[UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:1.0]];
}

+ (UIColor *)successColor {
    return [self colorWithLight:[UIColor colorWithRed:0.2 green:0.7 blue:0.2 alpha:1.0]
                           dark:[UIColor colorWithRed:0.3 green:0.85 blue:0.3 alpha:1.0]];
}

+ (UIColor *)warningColor {
    return [self colorWithLight:[UIColor colorWithRed:0.9 green:0.6 blue:0.0 alpha:1.0]
                           dark:[UIColor colorWithRed:1.0 green:0.75 blue:0.2 alpha:1.0]];
}

#pragma mark - State Tints

+ (UIColor *)onTintColor {
    return [self colorWithLight:[UIColor colorWithRed:1.0 green:0.98 blue:0.9 alpha:1.0]
                           dark:[UIColor colorWithRed:0.2 green:0.18 blue:0.1 alpha:1.0]];
}

+ (UIColor *)heatTintColor {
    return [self colorWithLight:[UIColor colorWithRed:1.0 green:0.95 blue:0.9 alpha:1.0]
                           dark:[UIColor colorWithRed:0.22 green:0.15 blue:0.1 alpha:1.0]];
}

+ (UIColor *)coolTintColor {
    return [self colorWithLight:[UIColor colorWithRed:0.9 green:0.95 blue:1.0 alpha:1.0]
                           dark:[UIColor colorWithRed:0.1 green:0.15 blue:0.22 alpha:1.0]];
}

+ (UIColor *)activeTintColor {
    return [self colorWithLight:[UIColor colorWithRed:0.93 green:0.95 blue:1.0 alpha:1.0]
                           dark:[UIColor colorWithRed:0.12 green:0.15 blue:0.22 alpha:1.0]];
}

#pragma mark - Controls

+ (UIColor *)buttonBackgroundColor {
    return [self colorWithLight:[UIColor colorWithWhite:0.92 alpha:1.0]
                           dark:[UIColor colorWithWhite:0.25 alpha:1.0]];
}

+ (UIColor *)controlBackgroundColor {
    return [self colorWithLight:[UIColor whiteColor]
                           dark:[UIColor colorWithRed:0.18 green:0.19 blue:0.22 alpha:1.0]];
}

+ (UIColor *)controlBorderColor {
    return [self colorWithLight:[UIColor colorWithWhite:0.8 alpha:1.0]
                           dark:[UIColor colorWithWhite:0.3 alpha:1.0]];
}

#pragma mark - Connection Bar

+ (UIColor *)connectionBarColor {
    return [self colorWithLight:[UIColor colorWithRed:0.9 green:0.3 blue:0.2 alpha:1.0]
                           dark:[UIColor colorWithRed:0.7 green:0.2 blue:0.15 alpha:1.0]];
}

+ (UIColor *)connectionBarTextColor {
    return [UIColor whiteColor];
}

#pragma mark - Section Headers

+ (UIColor *)sectionHeaderColor {
    return [self colorWithLight:[UIColor colorWithWhite:0.3 alpha:1.0]
                           dark:[UIColor colorWithWhite:0.75 alpha:1.0]];
}

@end
