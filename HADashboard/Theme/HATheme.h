#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, HAThemeMode) {
    HAThemeModeAuto  = 0,  // Follows system on iOS 13+, sun-based on iOS 9-12
    HAThemeModeDark  = 1,  // Solid dark
    HAThemeModeLight = 2,  // Flat light
};

typedef NS_ENUM(NSInteger, HAGradientPreset) {
    HAGradientPresetPurpleDream = 0,
    HAGradientPresetOceanBlue   = 1,
    HAGradientPresetSunset      = 2,
    HAGradientPresetForest      = 3,
    HAGradientPresetMidnight    = 4,
    HAGradientPresetCustom      = 5,
};

extern NSString *const HAThemeDidChangeNotification;

/// Provides semantic colors that adapt based on the selected theme mode.
/// Supports Auto (system), Gradient (dark + gradient bg), Dark, and Light.
@interface HATheme : NSObject

// Theme mode management
+ (HAThemeMode)currentMode;
+ (void)setCurrentMode:(HAThemeMode)mode;

// Gradient background (independent of appearance mode)
+ (BOOL)isGradientEnabled;
+ (void)setGradientEnabled:(BOOL)enabled;
/// Returns the blur effect style for frosted-glass card backgrounds.
/// Single source of truth — adapts to dark/light appearance.
+ (UIBlurEffectStyle)gradientBlurStyle;

+ (HAGradientPreset)gradientPreset;
+ (void)setGradientPreset:(HAGradientPreset)preset;
+ (NSArray<UIColor *> *)gradientColors;
+ (void)setCustomGradientHex1:(NSString *)hex1 hex2:(NSString *)hex2;
+ (NSString *)customGradientHex1;
+ (NSString *)customGradientHex2;

// Apply the theme's interface style to the key window (iOS 13+).
// Call once after the window is visible and again whenever the mode changes.
+ (void)applyInterfaceStyle;

// Force sun entity for Auto dark mode (bypasses system appearance on iOS 13+)
+ (BOOL)forceSunEntity;
+ (void)setForceSunEntity:(BOOL)force;

// Effective dark mode (accounts for manual override)
+ (BOOL)effectiveDarkMode;
+ (BOOL)isDarkMode;

// Utility
+ (UIColor *)colorFromHex:(NSString *)hex;

/// Parses a color string: named colors (green, yellow, red, orange, blue, purple,
/// teal, grey/gray, white, black, cyan, pink, indigo, amber) or hex (#RRGGBB / RRGGBB).
+ (UIColor *)colorFromString:(NSString *)colorString;

// Backgrounds
+ (UIColor *)backgroundColor;
+ (UIColor *)cellBackgroundColor;
+ (UIColor *)badgeBackgroundColor;
+ (UIColor *)cellBorderColor;

// Text
+ (UIColor *)primaryTextColor;
+ (UIColor *)secondaryTextColor;
+ (UIColor *)tertiaryTextColor;

// Semantic
+ (UIColor *)accentColor;
+ (UIColor *)switchTintColor;
+ (UIColor *)destructiveColor;
+ (UIColor *)successColor;
+ (UIColor *)warningColor;

// State tints (for entity cells)
+ (UIColor *)onTintColor;
+ (UIColor *)heatTintColor;
+ (UIColor *)coolTintColor;
+ (UIColor *)activeTintColor;

// Controls (buttons, dropdowns)
+ (UIColor *)buttonBackgroundColor;
+ (UIColor *)controlBackgroundColor;
+ (UIColor *)controlBorderColor;

// Connection bar
+ (UIColor *)connectionBarColor;
+ (UIColor *)connectionBarTextColor;

// Section headers
+ (UIColor *)sectionHeaderColor;

@end
