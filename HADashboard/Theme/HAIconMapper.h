#import <UIKit/UIKit.h>

/// Maps MDI (Material Design Icons) icon names from Home Assistant to font glyphs.
/// Uses the bundled materialdesignicons-webfont.ttf for crisp vector icons.
@interface HAIconMapper : NSObject

/// Preload MDI font and warm system font caches. Call early at app launch.
+ (void)warmFonts;

/// The MDI font name (after registration). Nil if font failed to load.
+ (NSString *)mdiFontName;

/// Returns a UIFont for MDI icons at the given size.
+ (UIFont *)mdiFontOfSize:(CGFloat)size;

/// Returns a plain NSString containing the single Unicode character for the icon.
/// Nil if the icon name is not recognized.
+ (NSString *)glyphForIconName:(NSString *)mdiName;

/// Convenience: returns a glyph string for a domain's default icon.
+ (NSString *)glyphForDomain:(NSString *)domain;

/// Render an MDI icon name to a UIImage using CoreText. Works on iOS 5+
/// where UILabel can't render Supplementary Private Use Area codepoints.
/// Returns nil if the icon name is not recognized or the font isn't loaded.
+ (UIImage *)imageForIconName:(NSString *)mdiName size:(CGFloat)size color:(UIColor *)color;

/// Set an MDI glyph on a UILabel. On iOS 6+, sets text directly (UILabel can
/// render SMP codepoints). On iOS 5, renders via CoreText into a background
/// image since UILabel's old text engine can't handle the Private Use Area.
+ (void)setGlyph:(NSString *)glyphString onLabel:(UILabel *)label;

@end
