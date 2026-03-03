#import "HARemoteCommandHandler.h"
#import <UIKit/UIKit.h>
#import "HAConnectionManager.h"
#import "HAAuthManager.h"
#import "HATheme.h"

/// We reuse the existing navigate notification for view switching.
extern NSString *const HAActionNavigateNotification;

NSString *const HARemoteCommandNotification = @"HARemoteCommandNotification";
NSString *const HARemoteCommandReloadNotification = @"HARemoteCommandReloadNotification";

@interface HARemoteCommandHandler ()
@property (nonatomic, assign) NSInteger subscriptionId;
@property (nonatomic, assign) CGFloat savedBrightness; // Stored before screen_off for restore
@end

@implementation HARemoteCommandHandler

- (void)dealloc {
    [self stopListening];
}

#pragma mark - Start / Stop

- (void)startListening {
    if (self.subscriptionId > 0) return; // Already listening

    // Subscribe to mobile_app_notification events.
    // HA fires these when the notify.mobile_app_<device> service is called.
    __weak typeof(self) weakSelf = self;
    self.subscriptionId = [[HAConnectionManager sharedManager]
        subscribeToEventType:@"mobile_app_notification"
                     handler:^(NSDictionary *eventData) {
        [weakSelf handleNotificationEvent:eventData];
    }];

    if (self.subscriptionId == 0) {
        NSLog(@"[HARemoteCommandHandler] Failed to subscribe (not connected)");
    } else {
        NSLog(@"[HARemoteCommandHandler] Subscribed to mobile_app_notification (id=%ld)", (long)self.subscriptionId);
    }
}

- (void)stopListening {
    if (self.subscriptionId > 0) {
        [[HAConnectionManager sharedManager] unsubscribeFromEventWithId:self.subscriptionId];
        self.subscriptionId = 0;
    }
}

#pragma mark - Event Processing

- (void)handleNotificationEvent:(NSDictionary *)eventData {
    // HA notification payloads can contain commands in the "message" field
    // with "command_" prefix (Companion app convention), or in a
    // "homeassistant" dict with a "command" key.
    NSString *message = eventData[@"message"];
    NSDictionary *data = eventData[@"data"];
    if (![data isKindOfClass:[NSDictionary class]]) data = eventData;

    // Check for Companion-style "command_" messages
    if ([message isKindOfClass:[NSString class]] && [message hasPrefix:@"command_"]) {
        [self dispatchCommand:message data:data];
        return;
    }

    // Check for "homeassistant" dict style
    NSDictionary *haDict = eventData[@"homeassistant"];
    if (!haDict) haDict = data[@"homeassistant"];
    if ([haDict isKindOfClass:[NSDictionary class]]) {
        NSString *command = haDict[@"command"];
        if ([command isKindOfClass:[NSString class]]) {
            [self dispatchCommand:command data:haDict];
            return;
        }
    }

    // Check for direct command field (our custom extension)
    NSString *command = data[@"command"];
    if ([command isKindOfClass:[NSString class]]) {
        [self dispatchCommand:command data:data];
    }
}

- (void)dispatchCommand:(NSString *)command data:(NSDictionary *)data {
    NSLog(@"[HARemoteCommandHandler] Dispatching command: %@", command);

    if ([command isEqualToString:@"command_screen_brightness_level"] ||
        [command isEqualToString:@"set_brightness"]) {
        [self handleSetBrightness:data];
    } else if ([command isEqualToString:@"command_screen_on"]) {
        [self handleScreenOn];
    } else if ([command isEqualToString:@"command_screen_off"]) {
        [self handleScreenOff];
    } else if ([command isEqualToString:@"switch_dashboard"]) {
        [self handleSwitchDashboard:data];
    } else if ([command isEqualToString:@"switch_view"] ||
               [command isEqualToString:@"command_navigate"]) {
        [self handleSwitchView:data];
    } else if ([command isEqualToString:@"set_theme"]) {
        [self handleSetTheme:data];
    } else if ([command isEqualToString:@"set_gradient"]) {
        [self handleSetGradient:data];
    } else if ([command isEqualToString:@"set_kiosk_mode"]) {
        [self handleSetKioskMode:data];
    } else if ([command isEqualToString:@"reload"]) {
        [self handleReload];
    } else {
        NSLog(@"[HARemoteCommandHandler] Unknown command: %@", command);
    }

    // Post generic notification for extensibility
    [[NSNotificationCenter defaultCenter] postNotificationName:HARemoteCommandNotification
                                                        object:self
                                                      userInfo:@{@"command": command, @"data": data ?: @{}}];
}

#pragma mark - Command Handlers

- (void)handleSetBrightness:(NSDictionary *)data {
    // Accept "level" (0-100) or "brightness" (0-255 companion style)
    NSNumber *level = data[@"level"];
    if (!level) level = data[@"brightness"];
    if (!level) {
        // Companion style: brightness is in the command data at top level
        level = data[@"command_screen_brightness_level"];
    }
    if (![level isKindOfClass:[NSNumber class]]) return;

    CGFloat value = [level floatValue];
    // Normalize: if > 1 assume 0-100 or 0-255 scale
    if (value > 1.0) {
        value = value > 100 ? value / 255.0 : value / 100.0;
    }
    value = fminf(fmaxf(value, 0.0), 1.0);

    [UIScreen mainScreen].brightness = value;
    NSLog(@"[HARemoteCommandHandler] Set brightness to %.0f%%", value * 100);
}

- (void)handleScreenOn {
    CGFloat restore = self.savedBrightness > 0 ? self.savedBrightness : 0.5;
    [UIScreen mainScreen].brightness = restore;
    NSLog(@"[HARemoteCommandHandler] Screen on (brightness %.0f%%)", restore * 100);
}

- (void)handleScreenOff {
    CGFloat current = [UIScreen mainScreen].brightness;
    if (current > 0) self.savedBrightness = current;
    [UIScreen mainScreen].brightness = 0.0;
    NSLog(@"[HARemoteCommandHandler] Screen off (saved brightness %.0f%%)", self.savedBrightness * 100);
}

- (void)handleSwitchDashboard:(NSDictionary *)data {
    NSString *dashboard = data[@"dashboard"];
    if (![dashboard isKindOfClass:[NSString class]]) return;

    HAAuthManager *auth = [HAAuthManager sharedManager];
    [auth saveSelectedDashboardPath:dashboard];
    [[HAConnectionManager sharedManager] fetchLovelaceConfig:dashboard];
    NSLog(@"[HARemoteCommandHandler] Switched to dashboard: %@", dashboard);
}

- (void)handleSwitchView:(NSDictionary *)data {
    NSString *path = data[@"path"];
    if (!path) path = data[@"view"];
    if (!path) {
        NSNumber *index = data[@"index"];
        if ([index isKindOfClass:[NSNumber class]]) {
            path = [index stringValue];
        }
    }
    if (![path isKindOfClass:[NSString class]]) return;

    // Reuse the existing navigate notification — HADashboardViewController already handles it
    [[NSNotificationCenter defaultCenter] postNotificationName:HAActionNavigateNotification
                                                        object:nil
                                                      userInfo:@{@"path": path}];
    NSLog(@"[HARemoteCommandHandler] Switch view to: %@", path);
}

- (void)handleSetTheme:(NSDictionary *)data {
    NSString *mode = data[@"mode"];
    if (![mode isKindOfClass:[NSString class]]) return;

    if ([mode caseInsensitiveCompare:@"dark"] == NSOrderedSame) {
        [HATheme setCurrentMode:HAThemeModeDark];
    } else if ([mode caseInsensitiveCompare:@"light"] == NSOrderedSame) {
        [HATheme setCurrentMode:HAThemeModeLight];
    } else {
        [HATheme setCurrentMode:HAThemeModeAuto];
    }
    NSLog(@"[HARemoteCommandHandler] Set theme mode: %@", mode);
}

- (void)handleSetGradient:(NSDictionary *)data {
    NSString *preset = data[@"preset"];
    if ([preset isKindOfClass:[NSString class]]) {
        // Map preset name to enum
        NSDictionary *presetMap = @{
            @"purple_dream": @(HAGradientPresetPurpleDream),
            @"ocean_blue":   @(HAGradientPresetOceanBlue),
            @"sunset":       @(HAGradientPresetSunset),
            @"forest":       @(HAGradientPresetForest),
            @"midnight":     @(HAGradientPresetMidnight),
        };
        NSNumber *value = presetMap[[preset lowercaseString]];
        if (value) {
            [HATheme setGradientEnabled:YES];
            [HATheme setGradientPreset:[value integerValue]];
            NSLog(@"[HARemoteCommandHandler] Set gradient preset: %@", preset);
            return;
        }
    }

    // Custom hex colors
    NSString *hex1 = data[@"color1"];
    NSString *hex2 = data[@"color2"];
    if ([hex1 isKindOfClass:[NSString class]] && [hex2 isKindOfClass:[NSString class]]) {
        [HATheme setGradientEnabled:YES];
        [HATheme setGradientPreset:HAGradientPresetCustom];
        [HATheme setCustomGradientHex1:hex1 hex2:hex2];
        NSLog(@"[HARemoteCommandHandler] Set custom gradient: %@ → %@", hex1, hex2);
        return;
    }

    // Disable gradient
    NSNumber *enabled = data[@"enabled"];
    if ([enabled isKindOfClass:[NSNumber class]] && ![enabled boolValue]) {
        [HATheme setGradientEnabled:NO];
        NSLog(@"[HARemoteCommandHandler] Disabled gradient");
    }
}

- (void)handleSetKioskMode:(NSDictionary *)data {
    NSNumber *enabled = data[@"enabled"];
    if (![enabled isKindOfClass:[NSNumber class]]) return;

    [[HAAuthManager sharedManager] setKioskMode:[enabled boolValue]];
    NSLog(@"[HARemoteCommandHandler] Kiosk mode: %@", [enabled boolValue] ? @"ON" : @"OFF");
}

- (void)handleReload {
    // Post notification so HADeviceIntegrationManager can coordinate stop→disconnect→reconnect→start
    [[NSNotificationCenter defaultCenter] postNotificationName:HARemoteCommandReloadNotification object:nil];
    NSLog(@"[HARemoteCommandHandler] Reload requested");
}

@end
