#import "HAEntityDisplayHelper.h"
#import "HAEntity.h"
#import "HADashboardConfig.h"
#import "HAIconMapper.h"
#import "HATheme.h"

@implementation HAEntityDisplayHelper

#pragma mark - Display Name

+ (NSString *)displayNameForEntity:(HAEntity *)entity
                        configItem:(HADashboardConfigItem *)configItem
                      nameOverride:(NSString *)nameOverride {
    if (nameOverride.length > 0) return nameOverride;
    // Card-level name override stored in customProperties when a heading claims displayName
    NSString *cardNameOverride = configItem.customProperties[@"nameOverride"];
    if (cardNameOverride.length > 0) return cardNameOverride;
    // When a heading is present, displayName is the heading text — fall back to friendly_name
    BOOL hasHeading = (configItem.displayName.length > 0 && configItem.customProperties[@"headingIcon"] != nil);
    if (!hasHeading && configItem.displayName.length > 0) return configItem.displayName;
    if (entity.friendlyName.length > 0) return entity.friendlyName;
    return entity.entityId ?: @"";
}

+ (NSString *)displayNameForEntity:(HAEntity *)entity
                          entityId:(NSString *)entityId
                           section:(HADashboardConfigSection *)section {
    NSString *override = section.nameOverrides[entityId];
    if (override.length > 0) return override;
    if (entity.friendlyName.length > 0) return entity.friendlyName;
    return entityId ?: @"";
}

#pragma mark - State Formatting

+ (NSString *)formattedStateForEntity:(HAEntity *)entity decimals:(NSInteger)decimals {
    NSString *state = entity.state;
    if (!state) return @"--";

    // input_datetime: use the entity's own date/time formatter to avoid
    // the state string (e.g. "2026-02-12") being parsed as a number ("2,026").
    if ([[entity domain] isEqualToString:@"input_datetime"]) {
        NSString *display = [entity inputDatetimeDisplayString];
        return display ?: state;
    }

    // binary_sensor: device_class-aware friendly state
    if ([[entity domain] isEqualToString:@"binary_sensor"]) {
        return [self binarySensorStateForDeviceClass:[entity deviceClass] isOn:[entity isOn]];
    }

    double numVal = [state doubleValue];
    BOOL isNumeric = (numVal != 0.0 || [state isEqualToString:@"0"] || [state hasPrefix:@"0."]);

    if (isNumeric) {
        // Check for duration units — format as human-readable duration
        NSString *unit = entity.unitOfMeasurement;
        if (unit.length > 0 &&
            ([unit isEqualToString:@"h"] || [unit isEqualToString:@"min"] ||
             [unit isEqualToString:@"s"] || [unit isEqualToString:@"d"])) {
            return [self formattedDurationFromValue:numVal unit:unit];
        }
        return [self formattedNumberString:numVal decimals:decimals];
    }

    // Check for ISO 8601 timestamp
    NSString *deviceClass = [entity deviceClass];
    if (([deviceClass isEqualToString:@"timestamp"]) ||
        (state.length >= 19 && [state characterAtIndex:4] == '-' && [state characterAtIndex:10] == 'T')) {
        NSString *relative = [self relativeTimeFromISO8601:state];
        if (relative) return relative;
    }

    return state;
}

+ (NSString *)stateWithUnitForEntity:(HAEntity *)entity decimals:(NSInteger)decimals {
    NSString *state = [self formattedStateForEntity:entity decimals:decimals];

    // Don't append unit for binary_sensor (state already human-readable)
    if ([[entity domain] isEqualToString:@"binary_sensor"]) return state;

    // Don't append unit for duration values (already formatted with units)
    NSString *unit = entity.unitOfMeasurement;
    if (unit.length > 0 &&
        ([unit isEqualToString:@"h"] || [unit isEqualToString:@"min"] ||
         [unit isEqualToString:@"s"] || [unit isEqualToString:@"d"])) {
        return state;
    }

    if (unit.length > 0) {
        return [NSString stringWithFormat:@"%@ %@", state, unit];
    }
    return state;
}

#pragma mark - Binary Sensor State

+ (NSString *)binarySensorStateForDeviceClass:(NSString *)deviceClass isOn:(BOOL)isOn {
    if (!deviceClass) return isOn ? @"On" : @"Off";

    // Map device_class + state to friendly strings (matching HA frontend)
    static NSDictionary *onStates = nil;
    static NSDictionary *offStates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        onStates = @{
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
        offStates = @{
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
    });

    NSDictionary *map = isOn ? onStates : offStates;
    NSString *result = map[deviceClass];
    return result ?: (isOn ? @"On" : @"Off");
}

#pragma mark - Human Readable State

+ (NSString *)humanReadableState:(NSString *)state {
    if (!state || state.length == 0) return @"";

    // First replace underscores with spaces
    NSString *work = [state stringByReplacingOccurrencesOfString:@"_" withString:@" "];

    // Split camelCase: insert space before each uppercase letter that follows a lowercase
    NSMutableString *result = [NSMutableString stringWithCapacity:work.length + 4];
    for (NSUInteger i = 0; i < work.length; i++) {
        unichar ch = [work characterAtIndex:i];
        if (i > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:ch]) {
            unichar prev = [work characterAtIndex:i - 1];
            if ([[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:prev]) {
                [result appendString:@" "];
            }
        }
        [result appendFormat:@"%C", ch];
    }

    // Capitalize each word
    return [result capitalizedString];
}

#pragma mark - Number Formatting

+ (NSString *)formattedNumberString:(double)value decimals:(NSInteger)decimals {
    static NSNumberFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.usesGroupingSeparator = YES;
    });

    formatter.minimumFractionDigits = 0;
    formatter.maximumFractionDigits = decimals;

    // Round via string formatting to avoid IEEE 754 precision artifacts
    NSString *fmt = [NSString stringWithFormat:@"%%.%ldf", (long)decimals];
    NSString *roundedStr = [NSString stringWithFormat:fmt, value];
    double rounded = [roundedStr doubleValue];

    // If the rounded value is an integer, show no decimal places
    if (rounded == floor(rounded) && decimals > 0) {
        formatter.maximumFractionDigits = 0;
    }

    NSString *result = [formatter stringFromNumber:@(rounded)];
    return result ?: [NSString stringWithFormat:@"%g", rounded];
}

#pragma mark - Duration Formatting

+ (NSString *)formattedDurationFromValue:(double)value unit:(NSString *)unit {
    // Convert everything to seconds first
    double totalSeconds;
    if ([unit isEqualToString:@"s"]) {
        totalSeconds = value;
    } else if ([unit isEqualToString:@"min"]) {
        totalSeconds = value * 60.0;
    } else if ([unit isEqualToString:@"h"]) {
        totalSeconds = value * 3600.0;
    } else if ([unit isEqualToString:@"d"]) {
        totalSeconds = value * 86400.0;
    } else {
        return [NSString stringWithFormat:@"%g %@", value, unit];
    }

    NSInteger total = (NSInteger)round(totalSeconds);
    if (total < 0) total = 0;

    NSInteger days    = total / 86400;
    NSInteger hours   = (total % 86400) / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger seconds = total % 60;

    if (days > 0) {
        return [NSString stringWithFormat:@"%ldd %ldh", (long)days, (long)hours];
    } else if (hours > 0) {
        return [NSString stringWithFormat:@"%ldh %ldm", (long)hours, (long)minutes];
    } else if (minutes > 0) {
        return [NSString stringWithFormat:@"%ldm %lds", (long)minutes, (long)seconds];
    } else {
        return [NSString stringWithFormat:@"%lds", (long)seconds];
    }
}

#pragma mark - Relative Time

+ (NSString *)relativeTimeFromISO8601:(NSString *)isoString {
    if (!isoString || isoString.length < 19) return nil;

    static NSDateFormatter *isoFormatter = nil;
    static NSDateFormatter *isoFormatterAlt = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isoFormatter = [[NSDateFormatter alloc] init];
        isoFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";

        isoFormatterAlt = [[NSDateFormatter alloc] init];
        isoFormatterAlt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        isoFormatterAlt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ";
    });

    NSDate *date = [isoFormatter dateFromString:isoString];
    if (!date) date = [isoFormatterAlt dateFromString:isoString];
    if (!date) return nil;

    NSTimeInterval elapsed = -[date timeIntervalSinceNow];
    BOOL isFuture = elapsed < 0;
    NSTimeInterval absElapsed = fabs(elapsed);

    NSString *timeString;
    if (absElapsed < 60) {
        timeString = @"Just now";
        return timeString;
    } else if (absElapsed < 3600) {
        NSInteger mins = (NSInteger)(absElapsed / 60.0);
        timeString = mins == 1 ? @"1 minute" : [NSString stringWithFormat:@"%ld minutes", (long)mins];
    } else if (absElapsed < 86400) {
        NSInteger hrs = (NSInteger)(absElapsed / 3600.0);
        timeString = hrs == 1 ? @"1 hour" : [NSString stringWithFormat:@"%ld hours", (long)hrs];
    } else if (absElapsed < 172800) {
        return isFuture ? @"Tomorrow" : @"Yesterday";
    } else if (absElapsed < 604800) {
        NSInteger days = (NSInteger)(absElapsed / 86400.0);
        timeString = [NSString stringWithFormat:@"%ld days", (long)days];
    } else {
        // More than a week: show short date
        static NSDateFormatter *shortFormatter = nil;
        static dispatch_once_t shortOnce;
        dispatch_once(&shortOnce, ^{
            shortFormatter = [[NSDateFormatter alloc] init];
            shortFormatter.dateStyle = NSDateFormatterShortStyle;
            shortFormatter.timeStyle = NSDateFormatterShortStyle;
        });
        return [shortFormatter stringFromDate:date];
    }

    return isFuture
        ? [NSString stringWithFormat:@"In %@", timeString]
        : [NSString stringWithFormat:@"%@ ago", timeString];
}

#pragma mark - Icon

+ (NSString *)iconGlyphForEntity:(HAEntity *)entity {
    // 1. Entity's explicit icon attribute (user-configured in HA)
    NSString *entityIcon = [entity icon];
    NSString *glyph = nil;
    if (entityIcon) {
        glyph = [HAIconMapper glyphForIconName:entityIcon];
    }
    // 2. Device-class-specific icon for binary_sensor
    if (!glyph && [[entity domain] isEqualToString:@"binary_sensor"]) {
        NSString *deviceClass = [entity deviceClass];
        if (deviceClass) {
            glyph = [self iconGlyphForBinarySensorDeviceClass:deviceClass isOn:[entity isOn]];
        }
    }
    // 3. Humidifier: always use air-humidifier icon
    if (!glyph && [[entity domain] isEqualToString:HAEntityDomainHumidifier]) {
        glyph = [HAIconMapper glyphForIconName:@"air-humidifier"];
    }
    // 3b. Battery sensor: level-based icon
    if (!glyph && [[entity domain] isEqualToString:@"sensor"]) {
        NSString *deviceClass = [entity deviceClass];
        if ([deviceClass isEqualToString:@"battery"]) {
            double level = [entity.state doubleValue];
            if (level >= 95) glyph = [HAIconMapper glyphForIconName:@"battery"];
            else if (level >= 85) glyph = [HAIconMapper glyphForIconName:@"battery-90"];
            else if (level >= 75) glyph = [HAIconMapper glyphForIconName:@"battery-80"];
            else if (level >= 65) glyph = [HAIconMapper glyphForIconName:@"battery-70"];
            else if (level >= 55) glyph = [HAIconMapper glyphForIconName:@"battery-60"];
            else if (level >= 45) glyph = [HAIconMapper glyphForIconName:@"battery-50"];
            else if (level >= 35) glyph = [HAIconMapper glyphForIconName:@"battery-40"];
            else if (level >= 25) glyph = [HAIconMapper glyphForIconName:@"battery-30"];
            else if (level >= 15) glyph = [HAIconMapper glyphForIconName:@"battery-20"];
            else if (level >= 5)  glyph = [HAIconMapper glyphForIconName:@"battery-10"];
            else glyph = [HAIconMapper glyphForIconName:@"battery-alert"];
        }
    }
    // 4. Device-class-specific icon for sensor
    if (!glyph && [[entity domain] isEqualToString:@"sensor"]) {
        NSString *deviceClass = [entity deviceClass];
        if (deviceClass) {
            glyph = [self iconGlyphForSensorDeviceClass:deviceClass];
        }
    }
    // 5. State-aware domain icons (on/off variants)
    if (!glyph) {
        glyph = [self stateAwareIconGlyphForEntity:entity];
    }
    // 6. Domain default icon (static fallback)
    if (!glyph) {
        glyph = [HAIconMapper glyphForDomain:[entity domain]];
    }
    return glyph;
}

+ (NSString *)iconGlyphForBinarySensorDeviceClass:(NSString *)deviceClass isOn:(BOOL)isOn {
    // Map device_class to MDI icon names matching HA's defaults
    static NSDictionary *onMap, *offMap;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        onMap = @{
            @"motion":           @"motion-sensor",
            @"occupancy":        @"home",
            @"door":             @"door-open",
            @"window":           @"window-open",
            @"opening":          @"square-outline",
            @"lock":             @"lock-open",
            @"moisture":         @"water",
            @"smoke":            @"smoke-detector-alert",
            @"gas":              @"alert",
            @"safety":           @"alert",
            @"problem":          @"alert-circle",
            @"sound":            @"music-note",
            @"vibration":        @"vibrate",
            @"connectivity":     @"check-network",
            @"battery":          @"battery",
            @"battery_charging": @"battery-charging",
            @"plug":             @"power-plug",
            @"presence":         @"home",
            @"running":          @"play-circle",
            @"heat":             @"fire",
            @"cold":             @"snowflake",
            @"light":            @"brightness-7",
        };
        offMap = @{
            @"motion":           @"motion-sensor-off",
            @"occupancy":        @"home-outline",
            @"door":             @"door-closed",
            @"window":           @"window-closed",
            @"opening":          @"square",
            @"lock":             @"lock",
            @"moisture":         @"water-off",
            @"smoke":            @"smoke-detector",
            @"gas":              @"checkbox-marked-circle",
            @"safety":           @"checkbox-marked-circle",
            @"problem":          @"check-circle",
            @"sound":            @"music-note-off",
            @"vibration":        @"crop-portrait",
            @"connectivity":     @"close-network",
            @"battery":          @"battery-outline",
            @"battery_charging": @"battery",
            @"plug":             @"power-plug-off",
            @"presence":         @"home-outline",
            @"running":          @"stop-circle",
            @"heat":             @"thermometer",
            @"cold":             @"thermometer",
            @"light":            @"brightness-5",
        };
    });
    NSDictionary *iconMap = isOn ? onMap : offMap;
    NSString *iconName = iconMap[deviceClass];
    return iconName ? [HAIconMapper glyphForIconName:iconName] : nil;
}

+ (NSString *)iconGlyphForSensorDeviceClass:(NSString *)deviceClass {
    // Map sensor device_class to MDI icon names matching HA's defaults
    static NSDictionary *sensorIconMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sensorIconMap = @{
            @"temperature":      @"thermometer",
            @"humidity":         @"water-percent",
            @"pressure":         @"gauge",
            @"power":            @"flash",
            @"energy":           @"lightning-bolt",
            @"battery":          @"battery",
            @"illuminance":      @"brightness-5",
            @"voltage":          @"sine-wave",
            @"current":          @"current-ac",
            @"gas":              @"meter-gas",
            @"moisture":         @"water",
            @"carbon_dioxide":   @"molecule-co2",
            @"carbon_monoxide":  @"molecule-co",
            @"signal_strength":  @"wifi",
            @"timestamp":        @"clock-outline",
            @"duration":         @"timer-outline",
            @"speed":            @"speedometer",
            @"weight":           @"weight",
            @"distance":         @"ruler",
            @"frequency":        @"sine-wave",
            @"pm25":             @"air-filter",
            @"pm10":             @"air-filter",
            @"aqi":              @"air-filter",
            @"irradiance":       @"sun-wireless",
            @"precipitation":    @"weather-rainy",
            @"wind_speed":       @"weather-windy",
        };
    });
    NSString *iconName = sensorIconMap[deviceClass];
    return iconName ? [HAIconMapper glyphForIconName:iconName] : nil;
}

/// Returns a state-aware icon glyph for domains that change icon based on on/off state.
/// Returns nil if the domain doesn't have state-aware icons (caller falls back to static domain map).
+ (NSString *)stateAwareIconGlyphForEntity:(HAEntity *)entity {
    NSString *domain = [entity domain];
    BOOL isOn = [entity isOn];

    // Light: lightbulb vs lightbulb-off-outline
    if ([domain isEqualToString:HAEntityDomainLight]) {
        return [HAIconMapper glyphForIconName:isOn ? @"lightbulb" : @"lightbulb-off-outline"];
    }
    // Switch: toggle-switch vs toggle-switch-off
    if ([domain isEqualToString:HAEntityDomainSwitch]) {
        return [HAIconMapper glyphForIconName:isOn ? @"toggle-switch" : @"toggle-switch-off"];
    }
    // Input Boolean: toggle-switch vs toggle-switch-off
    if ([domain isEqualToString:HAEntityDomainInputBoolean]) {
        return [HAIconMapper glyphForIconName:isOn ? @"toggle-switch" : @"toggle-switch-off"];
    }
    // Lock: lock vs lock-open
    if ([domain isEqualToString:HAEntityDomainLock]) {
        return [HAIconMapper glyphForIconName:[entity isLocked] ? @"lock" : @"lock-open"];
    }
    // Cover: device_class-specific icons with open/closed state
    if ([domain isEqualToString:HAEntityDomainCover]) {
        NSString *deviceClass = [entity deviceClass];
        if (deviceClass) {
            NSString *glyph = [self iconGlyphForCoverDeviceClass:deviceClass state:entity.state];
            if (glyph) return glyph;
        }
        // No device_class or unmapped: fall through to domain default
        return nil;
    }

    return nil;
}

/// Returns a device-class-specific icon for cover entities.
+ (NSString *)iconGlyphForCoverDeviceClass:(NSString *)deviceClass state:(NSString *)state {
    BOOL isOpen = [state isEqualToString:@"open"] || [state isEqualToString:@"opening"];

    if ([deviceClass isEqualToString:@"garage"]) {
        return [HAIconMapper glyphForIconName:isOpen ? @"garage-open" : @"garage"];
    }
    if ([deviceClass isEqualToString:@"window"]) {
        return [HAIconMapper glyphForIconName:isOpen ? @"window-open" : @"window-closed"];
    }
    if ([deviceClass isEqualToString:@"blind"] || [deviceClass isEqualToString:@"shade"]) {
        return [HAIconMapper glyphForIconName:isOpen ? @"blinds-horizontal" : @"blinds-horizontal-closed"];
    }
    if ([deviceClass isEqualToString:@"shutter"]) {
        return [HAIconMapper glyphForIconName:isOpen ? @"window-shutter-open" : @"window-shutter"];
    }
    if ([deviceClass isEqualToString:@"curtain"]) {
        return [HAIconMapper glyphForIconName:isOpen ? @"curtains" : @"curtains-closed"];
    }
    if ([deviceClass isEqualToString:@"awning"]) {
        return [HAIconMapper glyphForIconName:isOpen ? @"awning-outline" : @"awning"];
    }
    if ([deviceClass isEqualToString:@"door"]) {
        return [HAIconMapper glyphForIconName:isOpen ? @"door-open" : @"door-closed"];
    }
    if ([deviceClass isEqualToString:@"gate"]) {
        return [HAIconMapper glyphForIconName:isOpen ? @"gate-open" : @"gate"];
    }
    if ([deviceClass isEqualToString:@"damper"]) {
        return [HAIconMapper glyphForIconName:isOpen ? @"circle" : @"circle-slice-8"];
    }
    return nil;
}

+ (UIColor *)iconColorForEntity:(HAEntity *)entity {
    if (!entity || !entity.isAvailable) return [HATheme tertiaryTextColor];

    NSString *domain = [entity domain];

    // ── Light: amber/yellow when on ──
    if ([domain isEqualToString:HAEntityDomainLight]) {
        return [entity isOn]
            ? [UIColor colorWithRed:1.0 green:0.76 blue:0.03 alpha:1.0]  // #FFC107 amber
            : [HATheme secondaryTextColor];
    }

    // ── Switch / Input Boolean / Automation / Siren: blue when on ──
    if ([domain isEqualToString:HAEntityDomainSwitch] ||
        [domain isEqualToString:HAEntityDomainInputBoolean] ||
        [domain isEqualToString:HAEntityDomainAutomation] ||
        [domain isEqualToString:HAEntityDomainSiren]) {
        return [entity isOn]
            ? [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0]   // Blue
            : [HATheme secondaryTextColor];
    }

    // ── Fan: teal/cyan when on ──
    if ([domain isEqualToString:HAEntityDomainFan]) {
        return [entity isOn]
            ? [UIColor colorWithRed:0.0 green:0.75 blue:0.75 alpha:1.0]  // Teal
            : [HATheme secondaryTextColor];
    }

    // ── Lock: green=locked, red/orange=unlocked, red=jammed ──
    if ([domain isEqualToString:HAEntityDomainLock]) {
        if ([entity isLocked]) {
            return [UIColor colorWithRed:0.3 green:0.75 blue:0.3 alpha:1.0];  // Green
        } else if ([entity isJammed]) {
            return [UIColor colorWithRed:0.9 green:0.25 blue:0.2 alpha:1.0];  // Red
        } else if ([entity isUnlocked]) {
            return [UIColor colorWithRed:0.95 green:0.45 blue:0.15 alpha:1.0]; // Orange-red
        }
        return [HATheme secondaryTextColor];
    }

    // ── Climate: state-aware heat/cool/auto colors ──
    if ([domain isEqualToString:HAEntityDomainClimate]) {
        NSString *hvac = [entity hvacMode];
        if ([hvac isEqualToString:@"heat"] || [hvac isEqualToString:@"heat_cool"]) {
            return [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0]; // Warm orange
        } else if ([hvac isEqualToString:@"cool"]) {
            return [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0];   // Cool blue
        } else if ([hvac isEqualToString:@"auto"]) {
            return [UIColor colorWithRed:0.0 green:0.75 blue:0.75 alpha:1.0]; // Teal
        } else if ([hvac isEqualToString:@"dry"]) {
            return [UIColor colorWithRed:1.0 green:0.76 blue:0.03 alpha:1.0]; // Amber
        } else if ([hvac isEqualToString:@"fan_only"]) {
            return [UIColor colorWithRed:0.0 green:0.75 blue:0.75 alpha:1.0]; // Teal
        } else if ([hvac isEqualToString:@"off"]) {
            return [HATheme secondaryTextColor];
        }
        return [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0]; // Default orange
    }

    // ── Cover: teal when open ──
    if ([domain isEqualToString:HAEntityDomainCover]) {
        NSString *state = entity.state;
        if ([state isEqualToString:@"open"] || [state isEqualToString:@"opening"]) {
            return [UIColor colorWithRed:0.0 green:0.75 blue:0.75 alpha:1.0]; // Teal
        }
        return [HATheme secondaryTextColor];
    }

    // ── Sensor: device-class-aware colors ──
    if ([domain isEqualToString:HAEntityDomainSensor]) {
        NSString *deviceClass = [entity deviceClass];
        if (deviceClass) {
            return [self iconColorForSensorDeviceClass:deviceClass];
        }
        return [HATheme secondaryTextColor];
    }

    // ── Binary Sensor: device-class-aware colors (active state only) ──
    if ([domain isEqualToString:HAEntityDomainBinarySensor]) {
        if ([entity isOn]) {
            NSString *deviceClass = [entity deviceClass];
            if (deviceClass) {
                return [self iconColorForBinarySensorDeviceClassActive:deviceClass];
            }
            return [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0]; // Blue default active
        }
        return [HATheme secondaryTextColor];
    }

    // ── Alarm Control Panel: state-aware ──
    if ([domain isEqualToString:HAEntityDomainAlarmControlPanel]) {
        NSString *alarm = [entity alarmState];
        if ([alarm isEqualToString:@"disarmed"]) {
            return [UIColor colorWithRed:0.3 green:0.75 blue:0.3 alpha:1.0];  // Green
        } else if ([alarm isEqualToString:@"triggered"]) {
            return [UIColor colorWithRed:0.9 green:0.25 blue:0.2 alpha:1.0];  // Red
        } else if ([alarm hasPrefix:@"armed"] || [alarm isEqualToString:@"pending"]) {
            return [UIColor colorWithRed:0.9 green:0.25 blue:0.2 alpha:1.0];  // Red
        }
        return [HATheme secondaryTextColor];
    }

    // ── Media Player: blue when playing ──
    if ([domain isEqualToString:HAEntityDomainMediaPlayer]) {
        if ([entity isPlaying]) {
            return [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0]; // Blue
        } else if ([entity isPaused]) {
            return [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:0.6]; // Muted blue
        }
        return [HATheme secondaryTextColor];
    }

    // ── Vacuum: teal when cleaning ──
    if ([domain isEqualToString:HAEntityDomainVacuum]) {
        return [entity isOn]
            ? [UIColor colorWithRed:0.0 green:0.75 blue:0.75 alpha:1.0] // Teal
            : [HATheme secondaryTextColor];
    }

    // ── Humidifier: teal when on ──
    if ([domain isEqualToString:HAEntityDomainHumidifier]) {
        return [entity isOn]
            ? [UIColor colorWithRed:0.0 green:0.75 blue:0.75 alpha:1.0] // Teal
            : [HATheme secondaryTextColor];
    }

    // ── Scene / Script / Button: gradient-derived tint when available ──
    if ([domain isEqualToString:HAEntityDomainScene] ||
        [domain isEqualToString:HAEntityDomainScript] ||
        [domain isEqualToString:HAEntityDomainButton] ||
        [domain isEqualToString:HAEntityDomainInputButton]) {
        return [HATheme switchTintColor];
    }

    // ── Update: orange when update available ──
    if ([domain isEqualToString:HAEntityDomainUpdate]) {
        return [entity updateAvailable]
            ? [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0] // Orange
            : [HATheme secondaryTextColor];
    }

    // ── Person: blue when home ──
    if ([domain isEqualToString:HAEntityDomainPerson]) {
        if ([entity.state isEqualToString:@"home"]) {
            return [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0]; // Blue
        }
        return [HATheme secondaryTextColor];
    }

    return [HATheme secondaryTextColor];
}

/// Returns icon color for sensor entities based on device_class.
+ (UIColor *)iconColorForSensorDeviceClass:(NSString *)deviceClass {
    if ([deviceClass isEqualToString:@"temperature"]) {
        return [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0]; // Orange
    }
    if ([deviceClass isEqualToString:@"humidity"] || [deviceClass isEqualToString:@"moisture"]) {
        return [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0];   // Blue
    }
    if ([deviceClass isEqualToString:@"power"] || [deviceClass isEqualToString:@"energy"]) {
        return [UIColor colorWithRed:1.0 green:0.76 blue:0.03 alpha:1.0]; // Yellow/amber
    }
    if ([deviceClass isEqualToString:@"battery"]) {
        return [UIColor colorWithRed:0.3 green:0.75 blue:0.3 alpha:1.0];  // Green
    }
    if ([deviceClass isEqualToString:@"carbon_dioxide"] || [deviceClass isEqualToString:@"carbon_monoxide"]) {
        return [UIColor colorWithRed:0.0 green:0.75 blue:0.75 alpha:1.0]; // Teal
    }
    if ([deviceClass isEqualToString:@"illuminance"]) {
        return [UIColor colorWithRed:1.0 green:0.76 blue:0.03 alpha:1.0]; // Yellow/amber
    }
    if ([deviceClass isEqualToString:@"pressure"]) {
        return [UIColor colorWithRed:0.6 green:0.4 blue:0.8 alpha:1.0];   // Purple
    }
    if ([deviceClass isEqualToString:@"voltage"] || [deviceClass isEqualToString:@"current"] ||
        [deviceClass isEqualToString:@"frequency"]) {
        return [UIColor colorWithRed:1.0 green:0.76 blue:0.03 alpha:1.0]; // Yellow/amber
    }
    if ([deviceClass isEqualToString:@"gas"]) {
        return [UIColor colorWithRed:0.6 green:0.4 blue:0.8 alpha:1.0];   // Purple
    }
    if ([deviceClass isEqualToString:@"pm25"] || [deviceClass isEqualToString:@"pm10"] ||
        [deviceClass isEqualToString:@"aqi"]) {
        return [UIColor colorWithRed:0.0 green:0.75 blue:0.75 alpha:1.0]; // Teal
    }
    return [HATheme secondaryTextColor];
}

/// Returns icon color for binary_sensor entities in active (on) state based on device_class.
+ (UIColor *)iconColorForBinarySensorDeviceClassActive:(NSString *)deviceClass {
    // Problem/safety/smoke/gas alerts: red
    if ([deviceClass isEqualToString:@"problem"] || [deviceClass isEqualToString:@"safety"] ||
        [deviceClass isEqualToString:@"smoke"] || [deviceClass isEqualToString:@"gas"]) {
        return [UIColor colorWithRed:0.9 green:0.25 blue:0.2 alpha:1.0];  // Red
    }
    // Motion/occupancy/presence: blue
    if ([deviceClass isEqualToString:@"motion"] || [deviceClass isEqualToString:@"occupancy"] ||
        [deviceClass isEqualToString:@"presence"]) {
        return [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];  // Blue
    }
    // Door/window/opening: orange
    if ([deviceClass isEqualToString:@"door"] || [deviceClass isEqualToString:@"window"] ||
        [deviceClass isEqualToString:@"opening"] || [deviceClass isEqualToString:@"garage_door"]) {
        return [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0]; // Orange
    }
    // Lock (binary_sensor): unlocked=red
    if ([deviceClass isEqualToString:@"lock"]) {
        return [UIColor colorWithRed:0.9 green:0.25 blue:0.2 alpha:1.0];  // Red
    }
    // Moisture: blue
    if ([deviceClass isEqualToString:@"moisture"]) {
        return [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0];   // Blue
    }
    // Battery low: orange warning
    if ([deviceClass isEqualToString:@"battery"]) {
        return [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0]; // Orange
    }
    // Connectivity: green when connected
    if ([deviceClass isEqualToString:@"connectivity"] || [deviceClass isEqualToString:@"plug"]) {
        return [UIColor colorWithRed:0.3 green:0.75 blue:0.3 alpha:1.0];  // Green
    }
    // Default active binary sensor: blue
    return [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
}

#pragma mark - Toggle Detection

+ (BOOL)isNumericString:(NSString *)string {
    if (!string || string.length == 0) return NO;
    if ([string isEqualToString:@"unavailable"] ||
        [string isEqualToString:@"unknown"] ||
        [string isEqualToString:@"on"] ||
        [string isEqualToString:@"off"]) {
        return NO;
    }
    NSScanner *scanner = [NSScanner scannerWithString:string];
    double value;
    return [scanner scanDouble:&value] && [scanner isAtEnd];
}

+ (BOOL)isEntityToggleable:(HAEntity *)entity {
    NSString *domain = [entity domain];
    return [domain isEqualToString:HAEntityDomainSwitch] ||
           [domain isEqualToString:HAEntityDomainLight] ||
           [domain isEqualToString:HAEntityDomainInputBoolean] ||
           [domain isEqualToString:HAEntityDomainFan] ||
           [domain isEqualToString:HAEntityDomainAutomation] ||
           [domain isEqualToString:HAEntityDomainSiren];
}

@end
