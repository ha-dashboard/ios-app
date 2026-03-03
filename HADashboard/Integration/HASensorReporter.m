#import "HASensorReporter.h"
#import <UIKit/UIKit.h>
#import "HADeviceRegistration.h"
#import "HAAuthManager.h"

/// Sensor unique IDs (must match what we register).
static NSString *const kSensorBatteryLevel      = @"battery_level";
static NSString *const kSensorBatteryState      = @"battery_state";
static NSString *const kSensorScreenBrightness  = @"screen_brightness";
static NSString *const kSensorStorage           = @"storage_available";
static NSString *const kSensorAppState          = @"app_state";
static NSString *const kSensorActiveDashboard   = @"active_dashboard";

/// NSUserDefaults keys for per-sensor enable/disable (from Settings UI).
static NSString *const kBatteryLevelEnabledKey    = @"ha_sensor_battery_level_enabled";
static NSString *const kBatteryStateEnabledKey    = @"ha_sensor_battery_state_enabled";
static NSString *const kScreenBrightnessEnabledKey = @"ha_sensor_screen_brightness_enabled";
static NSString *const kStorageEnabledKey          = @"ha_sensor_storage_enabled";
static NSString *const kAppStateEnabledKey         = @"ha_sensor_app_state_enabled";
static NSString *const kActiveDashboardEnabledKey  = @"ha_sensor_active_dashboard_enabled";

/// Notification name for dashboard changes (posted by HADashboardViewController).
extern NSString *const HAConnectionManagerDidReceiveLovelaceNotification;

@interface HASensorReporter ()
@property (nonatomic, assign) BOOL reporting;
@property (nonatomic, strong) NSTimer *storageTimer;
@end

@implementation HASensorReporter

- (void)dealloc {
    [self stopReporting];
}

#pragma mark - Sensor Enable/Disable

- (BOOL)isSensorEnabled:(NSString *)sensorId {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([sensorId isEqualToString:kSensorBatteryLevel]) {
        // Default ON for battery level (most useful for kiosk)
        return [defaults objectForKey:kBatteryLevelEnabledKey] == nil ? YES : [defaults boolForKey:kBatteryLevelEnabledKey];
    }
    if ([sensorId isEqualToString:kSensorBatteryState]) {
        return [defaults boolForKey:kBatteryStateEnabledKey];
    }
    if ([sensorId isEqualToString:kSensorScreenBrightness]) {
        return [defaults boolForKey:kScreenBrightnessEnabledKey];
    }
    if ([sensorId isEqualToString:kSensorStorage]) {
        return [defaults boolForKey:kStorageEnabledKey];
    }
    if ([sensorId isEqualToString:kSensorAppState]) {
        return [defaults boolForKey:kAppStateEnabledKey];
    }
    if ([sensorId isEqualToString:kSensorActiveDashboard]) {
        return [defaults boolForKey:kActiveDashboardEnabledKey];
    }
    return NO;
}

#pragma mark - Sensor Registration

- (void)registerSensors {
    HADeviceRegistration *reg = [HADeviceRegistration sharedManager];
    if (!reg.isRegistered) return;

    if ([self isSensorEnabled:kSensorBatteryLevel]) {
        [self registerSensorWithId:kSensorBatteryLevel
                              name:@"Battery Level"
                       deviceClass:@"battery"
                 unitOfMeasurement:@"%"
                        stateClass:@"measurement"
                              icon:@"mdi:battery"];
    }
    if ([self isSensorEnabled:kSensorBatteryState]) {
        [self registerSensorWithId:kSensorBatteryState
                              name:@"Battery State"
                       deviceClass:nil
                 unitOfMeasurement:nil
                        stateClass:nil
                              icon:@"mdi:battery-charging"];
    }
    if ([self isSensorEnabled:kSensorScreenBrightness]) {
        [self registerSensorWithId:kSensorScreenBrightness
                              name:@"Screen Brightness"
                       deviceClass:nil
                 unitOfMeasurement:@"%"
                        stateClass:@"measurement"
                              icon:@"mdi:brightness-6"];
    }
    if ([self isSensorEnabled:kSensorStorage]) {
        [self registerSensorWithId:kSensorStorage
                              name:@"Storage Available"
                       deviceClass:nil
                 unitOfMeasurement:@"GB"
                        stateClass:@"measurement"
                              icon:@"mdi:harddisk"];
    }
    if ([self isSensorEnabled:kSensorAppState]) {
        [self registerSensorWithId:kSensorAppState
                              name:@"App State"
                       deviceClass:nil
                 unitOfMeasurement:nil
                        stateClass:nil
                              icon:@"mdi:application"];
    }
    if ([self isSensorEnabled:kSensorActiveDashboard]) {
        [self registerSensorWithId:kSensorActiveDashboard
                              name:@"Active Dashboard"
                       deviceClass:nil
                 unitOfMeasurement:nil
                        stateClass:nil
                              icon:@"mdi:view-dashboard"];
    }
}

- (void)registerSensorWithId:(NSString *)uniqueId
                        name:(NSString *)name
                 deviceClass:(NSString *)deviceClass
           unitOfMeasurement:(NSString *)unit
                  stateClass:(NSString *)stateClass
                        icon:(NSString *)icon {
    NSMutableDictionary *sensorData = [NSMutableDictionary dictionary];
    sensorData[@"unique_id"] = uniqueId;
    sensorData[@"name"] = name;
    sensorData[@"type"] = @"sensor";
    sensorData[@"entity_category"] = @"diagnostic";
    if (deviceClass) sensorData[@"device_class"] = deviceClass;
    if (unit)        sensorData[@"unit_of_measurement"] = unit;
    if (stateClass)  sensorData[@"state_class"] = stateClass;
    if (icon)        sensorData[@"icon"] = icon;
    sensorData[@"state"] = [self currentValueForSensor:uniqueId];

    [[HADeviceRegistration sharedManager] sendWebhookWithType:@"register_sensor"
                                                         data:sensorData
                                                   completion:^(id response, NSError *error) {
        if (error) {
            NSLog(@"[HASensorReporter] Failed to register sensor %@: %@", uniqueId, error.localizedDescription);
        }
    }];
}

#pragma mark - Start / Stop

- (void)startReporting {
    if (self.reporting) return;
    self.reporting = YES;

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(batteryLevelDidChange:)
               name:UIDeviceBatteryLevelDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(batteryStateDidChange:)
               name:UIDeviceBatteryStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(brightnessDidChange:)
               name:UIScreenBrightnessDidChangeNotification object:nil];

    // App state notifications
    [nc addObserver:self selector:@selector(appStateDidChange:)
               name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(appStateDidChange:)
               name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(appStateDidChange:)
               name:UIApplicationDidEnterBackgroundNotification object:nil];

    // Active dashboard changes
    [nc addObserver:self selector:@selector(dashboardDidChange:)
               name:HAConnectionManagerDidReceiveLovelaceNotification object:nil];

    // Storage timer — every 15 minutes
    if ([self isSensorEnabled:kSensorStorage]) {
        self.storageTimer = [NSTimer scheduledTimerWithTimeInterval:900.0
                                                             target:self
                                                           selector:@selector(storageTimerFired:)
                                                           userInfo:nil
                                                            repeats:YES];
    }

    [self reportAllSensorsNow];
}

- (void)stopReporting {
    if (!self.reporting) return;
    self.reporting = NO;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:UIDeviceBatteryLevelDidChangeNotification object:nil];
    [nc removeObserver:self name:UIDeviceBatteryStateDidChangeNotification object:nil];
    [nc removeObserver:self name:UIScreenBrightnessDidChangeNotification object:nil];
    [nc removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [nc removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc removeObserver:self name:HAConnectionManagerDidReceiveLovelaceNotification object:nil];

    [self.storageTimer invalidate];
    self.storageTimer = nil;
}

#pragma mark - Notification Handlers

- (void)batteryLevelDidChange:(NSNotification *)note {
    if ([self isSensorEnabled:kSensorBatteryLevel]) [self reportSensor:kSensorBatteryLevel];
}

- (void)batteryStateDidChange:(NSNotification *)note {
    if ([self isSensorEnabled:kSensorBatteryState]) [self reportSensor:kSensorBatteryState];
}

- (void)brightnessDidChange:(NSNotification *)note {
    if ([self isSensorEnabled:kSensorScreenBrightness]) [self reportSensor:kSensorScreenBrightness];
}

- (void)appStateDidChange:(NSNotification *)note {
    if ([self isSensorEnabled:kSensorAppState]) [self reportSensor:kSensorAppState];
}

- (void)dashboardDidChange:(NSNotification *)note {
    if ([self isSensorEnabled:kSensorActiveDashboard]) [self reportSensor:kSensorActiveDashboard];
}

- (void)storageTimerFired:(NSTimer *)timer {
    if ([self isSensorEnabled:kSensorStorage]) [self reportSensor:kSensorStorage];
}

#pragma mark - Reporting

- (void)reportAllSensorsNow {
    if (![HADeviceRegistration sharedManager].isRegistered) return;

    NSArray *allSensors = @[kSensorBatteryLevel, kSensorBatteryState, kSensorScreenBrightness,
                            kSensorStorage, kSensorAppState, kSensorActiveDashboard];
    NSMutableArray *sensorData = [NSMutableArray array];
    for (NSString *sensorId in allSensors) {
        if ([self isSensorEnabled:sensorId]) {
            [sensorData addObject:@{
                @"unique_id": sensorId,
                @"type": @"sensor",
                @"state": [self currentValueForSensor:sensorId],
                @"icon": [self iconForSensor:sensorId],
            }];
        }
    }
    if (sensorData.count == 0) return;

    [[HADeviceRegistration sharedManager] sendWebhookWithType:@"update_sensor_states"
                                                         data:sensorData
                                                   completion:^(id response, NSError *error) {
        if (error) {
            NSLog(@"[HASensorReporter] Batch update error: %@", error.localizedDescription);
        }
    }];
}

- (void)reportSensor:(NSString *)sensorId {
    if (![HADeviceRegistration sharedManager].isRegistered) return;

    NSDictionary *entry = @{
        @"unique_id": sensorId,
        @"type": @"sensor",
        @"state": [self currentValueForSensor:sensorId],
        @"icon": [self iconForSensor:sensorId],
    };

    [[HADeviceRegistration sharedManager] sendWebhookWithType:@"update_sensor_states"
                                                         data:@[entry]
                                                   completion:^(id response, NSError *error) {
        if (error) {
            NSLog(@"[HASensorReporter] Update %@ error: %@", sensorId, error.localizedDescription);
        }
    }];
}

#pragma mark - Sensor Values

- (NSString *)iconForSensor:(NSString *)sensorId {
    if ([sensorId isEqualToString:kSensorBatteryLevel])     return @"mdi:battery";
    if ([sensorId isEqualToString:kSensorBatteryState])     return @"mdi:battery-charging";
    if ([sensorId isEqualToString:kSensorScreenBrightness]) return @"mdi:brightness-6";
    if ([sensorId isEqualToString:kSensorStorage])          return @"mdi:harddisk";
    if ([sensorId isEqualToString:kSensorAppState])         return @"mdi:application";
    if ([sensorId isEqualToString:kSensorActiveDashboard])  return @"mdi:view-dashboard";
    return @"mdi:cellphone";
}

- (id)currentValueForSensor:(NSString *)sensorId {
    if ([sensorId isEqualToString:kSensorBatteryLevel]) {
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) return @(-1); // Unknown
        return @((NSInteger)(level * 100));
    }
    if ([sensorId isEqualToString:kSensorBatteryState]) {
        switch ([UIDevice currentDevice].batteryState) {
            case UIDeviceBatteryStateCharging:    return @"Charging";
            case UIDeviceBatteryStateFull:        return @"Full";
            case UIDeviceBatteryStateUnplugged:   return @"Not Charging";
            default:                              return @"Unknown";
        }
    }
    if ([sensorId isEqualToString:kSensorScreenBrightness]) {
        CGFloat brightness = [UIScreen mainScreen].brightness;
        return @((NSInteger)(brightness * 100));
    }
    if ([sensorId isEqualToString:kSensorStorage]) {
        NSError *error = nil;
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:&error];
        if (attrs) {
            unsigned long long freeBytes = [attrs[NSFileSystemFreeSize] unsignedLongLongValue];
            double freeGB = freeBytes / (1024.0 * 1024.0 * 1024.0);
            return @(round(freeGB * 10.0) / 10.0); // 1 decimal place
        }
        return @(-1);
    }
    if ([sensorId isEqualToString:kSensorAppState]) {
        UIApplicationState state = [UIApplication sharedApplication].applicationState;
        switch (state) {
            case UIApplicationStateActive:     return @"Active";
            case UIApplicationStateInactive:   return @"Inactive";
            case UIApplicationStateBackground: return @"Background";
        }
        return @"Unknown";
    }
    if ([sensorId isEqualToString:kSensorActiveDashboard]) {
        NSString *path = [[HAAuthManager sharedManager] selectedDashboardPath];
        return path.length > 0 ? path : @"default";
    }
    return @"unknown";
}

@end
