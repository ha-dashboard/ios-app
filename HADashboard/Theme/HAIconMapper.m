#import "HAIconMapper.h"
#import "HAAutoLayout.h"
#import "HALog.h"
#import "UIFont+HACompat.h"
#import <CoreText/CoreText.h>

static NSString *_mdiFontName = nil;
static NSDictionary<NSString *, NSNumber *> *_codepointMap = nil;
static NSDictionary<NSString *, NSString *> *_domainIconMap = nil;

@implementation HAIconMapper

+ (void)initialize {
    if (self != [HAIconMapper class]) return;
    HALogD(@"icon", @"HAIconMapper +initialize BEGIN");
    HALogD(@"icon", @"  loadFont BEGIN");
    [self loadFont];
    HALogD(@"icon", @"  loadFont END");
    HALogD(@"icon", @"  loadCodepoints BEGIN");
    [self loadCodepoints];
    HALogD(@"icon", @"  loadCodepoints END");
    HALogD(@"icon", @"  buildDomainMap BEGIN");
    [self buildDomainMap];
    HALogD(@"icon", @"  buildDomainMap END");
    HALogD(@"icon", @"HAIconMapper +initialize END");
}

+ (void)loadFont {
    // The font file is declared in Info.plist UIAppFonts, so iOS registers it
    // automatically at launch. We must NOT use CGFontCreateWithDataProvider or
    // CTFontManagerRegisterGraphicsFont here — both make IPC calls to the font
    // daemon that block the main thread indefinitely on jailbroken iOS 9,
    // causing a watchdog kill (0x8badf00d).
    //
    // Instead, look up the PostScript name from the already-registered font
    // by scanning the font family list. This is pure in-process work.
    HALogD(@"icon", @"    loadFont: scanning registered font families");
    for (NSString *family in [UIFont familyNames]) {
        for (NSString *name in [UIFont fontNamesForFamilyName:family]) {
            // MDI font PostScript name contains "materialdesignicons"
            if ([name.lowercaseString rangeOfString:@"materialdesignicons"].location != NSNotFound) {
                _mdiFontName = name;
                HALogD(@"icon", @"    loadFont: found name=%@", _mdiFontName);
                return;
            }
        }
    }

    // Fallback: if UIAppFonts didn't register the font (shouldn't happen),
    // try the known PostScript name directly
    if ([UIFont fontWithName:@"materialdesignicons-webfont" size:12]) {
        _mdiFontName = @"materialdesignicons-webfont";
        HALogD(@"icon", @"    loadFont: using fallback name");
        return;
    }

    // Manual registration fallback: on jailbroken iOS 5 with the app in
    // /Applications/ (not sandboxed), UIAppFonts may not be processed.
    // Use CTFontManagerRegisterGraphicsFont which is safe on iOS 5
    // (the IPC hang only affects jailbroken iOS 9).
    HALogD(@"icon", @"    loadFont: UIAppFonts didn't register, trying CTFont manual registration");
    NSString *fontPath = [[NSBundle mainBundle] pathForResource:@"materialdesignicons-webfont" ofType:@"ttf"];
    if (!fontPath) fontPath = [[NSBundle mainBundle] pathForResource:@"MaterialDesignIcons" ofType:@"ttf"];
    if (fontPath) {
        NSData *fontData = [NSData dataWithContentsOfFile:fontPath];
        if (fontData) {
            CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)fontData);
            CGFontRef cgFont = CGFontCreateWithDataProvider(provider);
            CGDataProviderRelease(provider);
            if (cgFont) {
                CFErrorRef error = NULL;
                if (CTFontManagerRegisterGraphicsFont(cgFont, &error)) {
                    // Get the PostScript name from the registered font
                    CFStringRef psName = CGFontCopyPostScriptName(cgFont);
                    if (psName) {
                        _mdiFontName = (__bridge_transfer NSString *)psName;
                        HALogD(@"icon", @"    loadFont: manually registered, name=%@", _mdiFontName);
                    }
                } else {
                    HALogE(@"icon", @"    loadFont: CTFontManagerRegisterGraphicsFont failed: %@", error);
                    if (error) CFRelease(error);
                }
                CGFontRelease(cgFont);
            }
        }
    }

    if (!_mdiFontName) {
        HALogE(@"icon", @"MDI font not found — is it listed in UIAppFonts?");
    }
}

+ (void)loadCodepoints {
    NSString *tsvPath = [[NSBundle mainBundle] pathForResource:@"mdi-codepoints" ofType:@"tsv"];
    if (!tsvPath) {
        _codepointMap = @{};
        return;
    }

    NSString *content = [NSString stringWithContentsOfFile:tsvPath encoding:NSUTF8StringEncoding error:nil];
    if (!content) { _codepointMap = @{}; return; }

    NSMutableDictionary *map = [NSMutableDictionary dictionaryWithCapacity:7500];
    for (NSString *line in [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSArray *parts = [line componentsSeparatedByString:@"\t"];
        if (parts.count < 2) continue;
        unsigned int codepoint = 0;
        [[NSScanner scannerWithString:parts[1]] scanHexInt:&codepoint];
        if (codepoint > 0) {
            map[parts[0]] = @(codepoint);
        }
    }
    _codepointMap = [map copy];
}

+ (void)buildDomainMap {
    _domainIconMap = @{
        @"light":               @"lightbulb",
        @"switch":              @"toggle-switch",
        @"sensor":              @"eye",
        @"binary_sensor":       @"checkbox-blank-circle-outline",
        @"climate":             @"thermometer",
        @"cover":               @"window-shutter",
        @"fan":                 @"fan",
        @"lock":                @"lock",
        @"camera":              @"video",
        @"media_player":        @"cast",
        @"weather":             @"weather-partly-cloudy",
        @"person":              @"account",
        @"scene":               @"palette",
        @"script":              @"script-text",
        @"automation":          @"robot",
        @"input_boolean":       @"toggle-switch-outline",
        @"input_number":        @"ray-vertex",
        @"input_select":        @"format-list-bulleted",
        @"input_text":          @"form-textbox",
        @"input_datetime":      @"calendar-clock",
        @"input_button":        @"gesture-tap-button",
        @"button":              @"gesture-tap-button",
        @"number":              @"ray-vertex",
        @"select":              @"format-list-bulleted",
        @"humidifier":          @"air-humidifier",
        @"vacuum":              @"robot-vacuum",
        @"alarm_control_panel": @"shield-home",
        @"timer":               @"timer-outline",
        @"counter":             @"counter",
        @"update":              @"package-up",
        @"siren":               @"bullhorn",
        @"water_heater":        @"thermometer",
    };
}

#pragma mark - Public API

+ (void)warmFonts {
    // Triggers +initialize (loadFont + loadCodepoints + buildDomainMap) and warms
    // font descriptor caches so the first cell render doesn't pay the full cost.
    (void)[self mdiFontOfSize:16];
    // Warm the monospaced digit system font used by thermostat gauge (57pt primary)
    if ([UIFont respondsToSelector:@selector(monospacedDigitSystemFontOfSize:weight:)]) {
        (void)[UIFont monospacedDigitSystemFontOfSize:57 weight:HAFontWeightRegular];
    }
    // Warm the medium-weight system font used by labels
    if ([UIFont respondsToSelector:@selector(systemFontOfSize:weight:)]) {
        (void)[UIFont systemFontOfSize:16 weight:HAFontWeightMedium];
    } else {
        (void)[UIFont boldSystemFontOfSize:16]; // iOS 5 fallback
    }
}

+ (NSString *)mdiFontName { return _mdiFontName; }

+ (UIFont *)mdiFontOfSize:(CGFloat)size {
    if (!_mdiFontName) return [UIFont systemFontOfSize:size];
    return [UIFont fontWithName:_mdiFontName size:size] ?: [UIFont systemFontOfSize:size];
}

+ (NSString *)glyphForIconName:(NSString *)mdiName {
    if (!mdiName || mdiName.length == 0) return nil;
    NSString *name = [mdiName lowercaseString];
    if ([name hasPrefix:@"mdi:"]) name = [name substringFromIndex:4];

    NSNumber *codepoint = _codepointMap[name];
    if (!codepoint) return nil;

    uint32_t cp = [codepoint unsignedIntValue];

    // On iOS 5, CoreText may not map Supplementary Private Use Area codepoints
    // (U+F0000+) via NSString rendering. Verify the glyph exists in the font
    // and log diagnostics for the first lookup.
    static BOOL _didLogGlyphCheck = NO;
    if (!_didLogGlyphCheck && _mdiFontName) {
        _didLogGlyphCheck = YES;
        CTFontRef ctFont = CTFontCreateWithName((__bridge CFStringRef)_mdiFontName, 16, NULL);
        if (ctFont) {
            UniChar surrogates[2];
            surrogates[0] = (UniChar)(0xD800 + ((cp - 0x10000) >> 10));
            surrogates[1] = (UniChar)(0xDC00 + ((cp - 0x10000) & 0x3FF));
            CGGlyph glyphs[2] = {0, 0};
            BOOL ok = CTFontGetGlyphsForCharacters(ctFont, surrogates, glyphs, 2);
            HALogI(@"icon", @"Glyph check: cp=U+%X ok=%d glyph[0]=%u glyph[1]=%u font=%@",
                   cp, ok, glyphs[0], glyphs[1], _mdiFontName);
            CFRelease(ctFont);
        }
    }

    if (cp <= 0xFFFF) {
        unichar ch = (unichar)cp;
        return [NSString stringWithCharacters:&ch length:1];
    }
    uint32_t offset = cp - 0x10000;
    unichar pair[2] = { (unichar)(0xD800 + (offset >> 10)), (unichar)(0xDC00 + (offset & 0x3FF)) };
    return [NSString stringWithCharacters:pair length:2];
}

+ (NSString *)glyphForDomain:(NSString *)domain {
    NSString *name = _domainIconMap[domain];
    return name ? [self glyphForIconName:name] : nil;
}

+ (UIImage *)imageForIconName:(NSString *)mdiName size:(CGFloat)size color:(UIColor *)color {
    if (!mdiName || !_mdiFontName) return nil;
    NSString *name = [mdiName lowercaseString];
    if ([name hasPrefix:@"mdi:"]) name = [name substringFromIndex:4];

    NSNumber *codepoint = _codepointMap[name];
    if (!codepoint) return nil;

    uint32_t cp = [codepoint unsignedIntValue];

    CTFontRef ctFont = CTFontCreateWithName((__bridge CFStringRef)_mdiFontName, size, NULL);
    if (!ctFont) return nil;

    // Convert codepoint to UTF-16 (may need surrogate pair)
    UniChar chars[2];
    NSInteger charCount;
    if (cp <= 0xFFFF) {
        chars[0] = (UniChar)cp;
        charCount = 1;
    } else {
        uint32_t offset = cp - 0x10000;
        chars[0] = (UniChar)(0xD800 + (offset >> 10));
        chars[1] = (UniChar)(0xDC00 + (offset & 0x3FF));
        charCount = 2;
    }

    CGGlyph glyphs[2] = {0, 0};
    if (!CTFontGetGlyphsForCharacters(ctFont, chars, glyphs, charCount)) {
        CFRelease(ctFont);
        return nil;
    }

    // Get glyph bounding box for sizing
    CGRect bbox = CTFontGetBoundingRectsForGlyphs(ctFont, kCTFontOrientationDefault, glyphs, NULL, 1);
    CGSize imageSize = CGSizeMake(ceilf(size), ceilf(size));

    UIGraphicsBeginImageContextWithOptions(imageSize, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) { CFRelease(ctFont); UIGraphicsEndImageContext(); return nil; }

    // Flip coordinate system for CoreText
    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    CGContextTranslateCTM(ctx, 0, imageSize.height);
    CGContextScaleCTM(ctx, 1.0, -1.0);

    // Center the glyph
    CGFloat dx = (imageSize.width - bbox.size.width) / 2.0 - bbox.origin.x;
    CGFloat dy = (imageSize.height - bbox.size.height) / 2.0 - bbox.origin.y;

    CGContextSetFillColorWithColor(ctx, color.CGColor);
    CGPoint position = CGPointMake(dx, dy);
    CTFontDrawGlyphs(ctFont, glyphs, &position, 1, ctx);

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CFRelease(ctFont);
    return image;
}

+ (void)setGlyph:(NSString *)glyphString onLabel:(UILabel *)label {
    if (!glyphString || !label) return;

    // iOS 6+: UILabel can render SMP codepoints directly
    if (HASystemMajorVersion() >= 6) {
        label.text = glyphString;
        return;
    }

    // iOS 5: UILabel's old text engine can't render Supplementary PUA glyphs.
    // Render via CoreText into the label's layer as a sublayer.
    label.text = @""; // clear text

    CGFloat fontSize = label.font.pointSize;
    if (fontSize <= 0) fontSize = 16;
    HALogD(@"icon", @"setGlyph: fontSize=%.0f labelBounds=%@ charCount=%lu",
           fontSize, NSStringFromCGRect(label.bounds), (unsigned long)glyphString.length);
    UIColor *color = label.textColor ?: [UIColor blackColor];

    // Find the icon name from the glyph string by reverse lookup
    // (glyphString is a Unicode character, we need the codepoint for imageForIconName)
    if (!_mdiFontName) return;

    CTFontRef ctFont = CTFontCreateWithName((__bridge CFStringRef)_mdiFontName, fontSize, NULL);
    if (!ctFont) return;

    // Extract codepoint from the glyph string
    UniChar chars[2];
    NSInteger charCount = glyphString.length;
    [glyphString getCharacters:chars range:NSMakeRange(0, MIN(charCount, 2))];

    CGGlyph glyphs[2] = {0, 0};
    if (!CTFontGetGlyphsForCharacters(ctFont, chars, glyphs, charCount)) {
        CFRelease(ctFont);
        return;
    }

    CGRect bbox = CTFontGetBoundingRectsForGlyphs(ctFont, kCTFontOrientationDefault, glyphs, NULL, 1);
    CGSize labelSize = label.bounds.size;
    if (labelSize.width == 0) labelSize = CGSizeMake(fontSize, fontSize);

    UIGraphicsBeginImageContextWithOptions(labelSize, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
        CGContextTranslateCTM(ctx, 0, labelSize.height);
        CGContextScaleCTM(ctx, 1.0, -1.0);

        CGFloat dx = (labelSize.width - bbox.size.width) / 2.0 - bbox.origin.x;
        CGFloat dy = (labelSize.height - bbox.size.height) / 2.0 - bbox.origin.y;

        CGContextSetFillColorWithColor(ctx, color.CGColor);
        CGPoint position = CGPointMake(dx, dy);
        CTFontDrawGlyphs(ctFont, glyphs, &position, 1, ctx);
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CFRelease(ctFont);

    if (image) {
        // Add a UIImageView as a subview instead of setting layer.contents,
        // because UILabel's -drawTextInRect: overwrites layer contents.
        static const NSInteger kIconImageViewTag = 9999;
        UIImageView *iv = (UIImageView *)[label viewWithTag:kIconImageViewTag];
        if (!iv) {
            iv = [[UIImageView alloc] init];
            iv.tag = kIconImageViewTag;
            iv.contentMode = UIViewContentModeCenter;
            iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [label addSubview:iv];
        }
        iv.frame = label.bounds;
        // If label has zero bounds (not laid out yet), defer frame to layoutSubviews
        if (CGRectIsEmpty(label.bounds)) {
            iv.frame = CGRectMake(0, 0, fontSize, fontSize);
        }
        iv.image = image;
    }
}

@end
