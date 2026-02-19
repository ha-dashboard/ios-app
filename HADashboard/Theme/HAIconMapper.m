#import "HAIconMapper.h"
#import "HAStartupLog.h"
#import <CoreText/CoreText.h>

static NSString *_mdiFontName = nil;
static NSDictionary<NSString *, NSNumber *> *_codepointMap = nil;
static NSDictionary<NSString *, NSString *> *_domainIconMap = nil;

@implementation HAIconMapper

+ (void)initialize {
    if (self != [HAIconMapper class]) return;
    [HAStartupLog log:@"HAIconMapper +initialize BEGIN"];
    [HAStartupLog log:@"  loadFont BEGIN"];
    [self loadFont];
    [HAStartupLog log:@"  loadFont END"];
    [HAStartupLog log:@"  loadCodepoints BEGIN"];
    [self loadCodepoints];
    [HAStartupLog log:@"  loadCodepoints END"];
    [HAStartupLog log:@"  buildDomainMap BEGIN"];
    [self buildDomainMap];
    [HAStartupLog log:@"  buildDomainMap END"];
    [HAStartupLog log:@"HAIconMapper +initialize END"];
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
    [HAStartupLog log:@"    loadFont: scanning registered font families"];
    for (NSString *family in [UIFont familyNames]) {
        for (NSString *name in [UIFont fontNamesForFamilyName:family]) {
            // MDI font PostScript name contains "materialdesignicons"
            if ([name.lowercaseString containsString:@"materialdesignicons"]) {
                _mdiFontName = name;
                [HAStartupLog log:[NSString stringWithFormat:@"    loadFont: found name=%@", _mdiFontName]];
                return;
            }
        }
    }

    // Fallback: if UIAppFonts didn't register the font (shouldn't happen),
    // try the known PostScript name directly
    if ([UIFont fontWithName:@"materialdesignicons-webfont" size:12]) {
        _mdiFontName = @"materialdesignicons-webfont";
        [HAStartupLog log:@"    loadFont: using fallback name"];
        return;
    }

    [HAStartupLog log:@"    loadFont: MDI font NOT FOUND in registered fonts"];
    NSLog(@"[HAIconMapper] MDI font not found — is it listed in UIAppFonts?");
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
    (void)[UIFont monospacedDigitSystemFontOfSize:57 weight:UIFontWeightRegular];
    // Warm the medium-weight system font used by labels
    (void)[UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
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

@end
