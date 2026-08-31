#import "HASensorReporter.h"
#import "HALog.h"
#import <UIKit/UIKit.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <SystemConfiguration/SCNetworkReachability.h>
#import <sys/sysctl.h>
#import <netinet/in.h>
#import "HADeviceRegistration.h"
#import "HAAuthManager.h"

/// Sensor unique IDs (must match what we register).
static NSString *const kSensorBatteryLevel      = @"battery_level";
static NSString *const kSensorBatteryState      = @"battery_state";
static NSString *const kSensorScreenBrightness  = @"screen_brightness";
static NSString *const kSensorStorage           = @"storage_available";
static NSString *const kSensorAppState          = @"app_state";
static NSString *const kSensorActiveDashboard   = @"active_dashboard";
static NSString *const kSensorWifiSSID          = @"wifi_ssid";
static NSString *const kSensorWifiBSSID         = @"wifi_bssid";
static NSString *const kSensorConnectionType    = @"connection_type";
static NSString *const kSensorLastUpdateTrigger = @"last_update_trigger";
static NSString *const kSensorDeviceModel       = @"device_model";

extern NSString *const HAConnectionManagerDidReceiveLovelaceNotification;

static NSArray *allSensorIds(void) {
    return @[kSensorBatteryLevel, kSensorBatteryState, kSensorScreenBrightness,
             kSensorStorage, kSensorAppState, kSensorActiveDashboard,
             kSensorWifiSSID, kSensorWifiBSSID, kSensorConnectionType,
             kSensorLastUpdateTrigger, kSensorDeviceModel];
}

@interface HASensorReporter ()
@property (nonatomic, assign) BOOL reporting;
@property (nonatomic, strong) NSTimer *storageTimer;
@property (nonatomic, copy) NSString *lastUpdateTrigger;
@end

@implementation HASensorReporter

- (void)dealloc {
    [self stopReporting];
}

#pragma mark - Sensor Registration

- (void)registerSensors {
    HADeviceRegistration *reg = [HADeviceRegistration sharedManager];
    if (!reg.isRegistered) return;

    [self registerSensorWithId:kSensorBatteryLevel     name:@"Battery Level"     deviceClass:@"battery" unit:@"%" stateClass:@"measurement" icon:@"mdi:battery"];
    [self registerSensorWithId:kSensorBatteryState     name:@"Battery State"     deviceClass:nil        unit:nil  stateClass:nil            icon:@"mdi:battery-charging"];
    [self registerSensorWithId:kSensorScreenBrightness name:@"Screen Brightness" deviceClass:nil        unit:@"%" stateClass:@"measurement" icon:@"mdi:brightness-6"];
    [self registerSensorWithId:kSensorStorage          name:@"Storage Available" deviceClass:nil        unit:@"GB" stateClass:@"measurement" icon:@"mdi:harddisk"];
    [self registerSensorWithId:kSensorAppState         name:@"App State"         deviceClass:nil        unit:nil  stateClass:nil            icon:@"mdi:application"];
    [self registerSensorWithId:kSensorActiveDashboard  name:@"Active Dashboard"  deviceClass:nil        unit:nil  stateClass:nil            icon:@"mdi:view-dashboard"];
    [self registerSensorWithId:kSensorWifiSSID          name:@"WiFi SSID"         deviceClass:nil        unit:nil  stateClass:nil            icon:@"mdi:wifi"];
    [self registerSensorWithId:kSensorWifiBSSID         name:@"WiFi BSSID"        deviceClass:nil        unit:nil  stateClass:nil            icon:@"mdi:wifi"];
    [self registerSensorWithId:kSensorConnectionType    name:@"Connection Type"   deviceClass:nil        unit:nil  stateClass:nil            icon:@"mdi:network"];
    [self registerSensorWithId:kSensorLastUpdateTrigger name:@"Last Update Trigger" deviceClass:nil      unit:nil  stateClass:nil            icon:@"mdi:update"];
    [self registerSensorWithId:kSensorDeviceModel       name:@"Device Model"      deviceClass:nil        unit:nil  stateClass:nil            icon:@"mdi:cellphone"];
}

- (void)registerSensorWithId:(NSString *)uniqueId name:(NSString *)name
                 deviceClass:(NSString *)deviceClass unit:(NSString *)unit
                  stateClass:(NSString *)stateClass icon:(NSString *)icon {
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    data[@"unique_id"] = uniqueId;
    data[@"name"] = name;
    data[@"type"] = @"sensor";
    data[@"entity_category"] = @"diagnostic";
    if (deviceClass) data[@"device_class"] = deviceClass;
    if (unit)        data[@"unit_of_measurement"] = unit;
    if (stateClass)  data[@"state_class"] = stateClass;
    if (icon)        data[@"icon"] = icon;
    data[@"state"] = [self currentValueForSensor:uniqueId];

    [[HADeviceRegistration sharedManager] sendWebhookWithType:@"register_sensor"
                                                         data:data
                                                   completion:^(id response, NSError *error) {
        if (error) {
            HALogE(@"sensor", @"Failed to register sensor %@: %@", uniqueId, error.localizedDescription);
        }
    }];
}

#pragma mark - Start / Stop

- (void)startReporting {
    if (self.reporting) return;
    self.reporting = YES;
    self.lastUpdateTrigger = @"launch";

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(batteryLevelDidChange:)
               name:UIDeviceBatteryLevelDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(batteryStateDidChange:)
               name:UIDeviceBatteryStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(brightnessDidChange:)
               name:UIScreenBrightnessDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(appStateDidChange:)
               name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(appStateDidChange:)
               name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(appStateDidChange:)
               name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(dashboardDidChange:)
               name:HAConnectionManagerDidReceiveLovelaceNotification object:nil];

    // Storage timer — every 15 minutes
    self.storageTimer = [NSTimer scheduledTimerWithTimeInterval:900.0
                                                         target:self
                                                       selector:@selector(storageTimerFired:)
                                                       userInfo:nil
                                                        repeats:YES];

    [self reportAllSensorsNow];
}

- (void)stopReporting {
    if (!self.reporting) return;
    self.reporting = NO;

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.storageTimer invalidate];
    self.storageTimer = nil;
}

#pragma mark - Notification Handlers

- (void)batteryLevelDidChange:(NSNotification *)note     { [self reportSensor:kSensorBatteryLevel]; }
- (void)batteryStateDidChange:(NSNotification *)note     { [self reportSensor:kSensorBatteryState]; }
- (void)brightnessDidChange:(NSNotification *)note       { [self reportSensor:kSensorScreenBrightness]; }
- (void)appStateDidChange:(NSNotification *)note {
    // Update trigger based on notification
    if ([note.name isEqualToString:UIApplicationDidBecomeActiveNotification]) {
        self.lastUpdateTrigger = @"foreground";
    } else if ([note.name isEqualToString:UIApplicationDidEnterBackgroundNotification]) {
        self.lastUpdateTrigger = @"background";
    }
    [self reportSensor:kSensorAppState];
    [self reportSensor:kSensorLastUpdateTrigger];
    // WiFi/connection may change when returning to foreground
    [self reportSensor:kSensorWifiSSID];
    [self reportSensor:kSensorWifiBSSID];
    [self reportSensor:kSensorConnectionType];
}
- (void)dashboardDidChange:(NSNotification *)note        { [self reportSensor:kSensorActiveDashboard]; }
- (void)storageTimerFired:(NSTimer *)timer               { [self reportSensor:kSensorStorage]; }

#pragma mark - Reporting

- (void)reportAllSensorsNow {
    if (![HADeviceRegistration sharedManager].isRegistered) return;

    NSMutableArray *batch = [NSMutableArray array];
    for (NSString *sensorId in allSensorIds()) {
        [batch addObject:@{
            @"unique_id": sensorId,
            @"type": @"sensor",
            @"state": [self currentValueForSensor:sensorId],
            @"icon": [self iconForSensor:sensorId],
        }];
    }

    [[HADeviceRegistration sharedManager] sendWebhookWithType:@"update_sensor_states"
                                                         data:batch
                                                   completion:^(id response, NSError *error) {
        if (error) {
            HALogE(@"sensor", @"Batch update error: %@", error.localizedDescription);
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
            HALogE(@"sensor", @"Update %@ error: %@", sensorId, error.localizedDescription);
        }
    }];
}

#pragma mark - Sensor Values

- (NSString *)iconForSensor:(NSString *)sensorId {
    if ([sensorId isEqualToString:kSensorBatteryLevel])      return @"mdi:battery";
    if ([sensorId isEqualToString:kSensorBatteryState])      return @"mdi:battery-charging";
    if ([sensorId isEqualToString:kSensorScreenBrightness])  return @"mdi:brightness-6";
    if ([sensorId isEqualToString:kSensorStorage])           return @"mdi:harddisk";
    if ([sensorId isEqualToString:kSensorAppState])          return @"mdi:application";
    if ([sensorId isEqualToString:kSensorActiveDashboard])   return @"mdi:view-dashboard";
    if ([sensorId isEqualToString:kSensorWifiSSID])          return @"mdi:wifi";
    if ([sensorId isEqualToString:kSensorWifiBSSID])         return @"mdi:wifi";
    if ([sensorId isEqualToString:kSensorConnectionType])    return @"mdi:network";
    if ([sensorId isEqualToString:kSensorLastUpdateTrigger]) return @"mdi:update";
    if ([sensorId isEqualToString:kSensorDeviceModel])       return @"mdi:cellphone";
    return @"mdi:cellphone";
}

- (id)currentValueForSensor:(NSString *)sensorId {
    if ([sensorId isEqualToString:kSensorBatteryLevel]) {
        float level = [UIDevice currentDevice].batteryLevel;
        if (level < 0) return @(-1);
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
        // Mac Catalyst reports -1 because it has no device display brightness.
        // Preserve the same unavailable sentinel used for battery level rather
        // than publishing an impossible -100% diagnostic value to HA.
        if (brightness < 0) return @(-1);
        return @((NSInteger)(brightness * 100));
    }
    if ([sensorId isEqualToString:kSensorStorage]) {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
        if (attrs) {
            unsigned long long freeBytes = [attrs[NSFileSystemFreeSize] unsignedLongLongValue];
            double freeGB = freeBytes / (1024.0 * 1024.0 * 1024.0);
            return @(round(freeGB * 10.0) / 10.0);
        }
        return @(-1);
    }
    if ([sensorId isEqualToString:kSensorAppState]) {
        switch ([UIApplication sharedApplication].applicationState) {
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
    if ([sensorId isEqualToString:kSensorWifiSSID]) {
        return [self currentWiFiSSID] ?: @"Unknown";
    }
    if ([sensorId isEqualToString:kSensorWifiBSSID]) {
        return [self currentWiFiBSSID] ?: @"Unknown";
    }
    if ([sensorId isEqualToString:kSensorConnectionType]) {
        return [self currentConnectionType];
    }
    if ([sensorId isEqualToString:kSensorLastUpdateTrigger]) {
        return self.lastUpdateTrigger ?: @"unknown";
    }
    if ([sensorId isEqualToString:kSensorDeviceModel]) {
        return [self machineModel];
    }
    return @"unknown";
}

#pragma mark - WiFi Info

- (NSString *)currentWiFiSSID {
    return [self currentWiFiInfoForKey:@"SSID"];
}

- (NSString *)currentWiFiBSSID {
    return [self currentWiFiInfoForKey:@"BSSID"];
}

- (NSString *)currentWiFiInfoForKey:(NSString *)key {
    // CNCopyCurrentNetworkInfo requires Access WiFi Information entitlement on iOS 12+
    // and location authorization on iOS 13+. Returns nil if unavailable.
    NSArray *interfaces = (__bridge_transfer NSArray *)CNCopySupportedInterfaces();
    for (NSString *iface in interfaces) {
        NSDictionary *info = (__bridge_transfer NSDictionary *)CNCopyCurrentNetworkInfo((__bridge CFStringRef)iface);
        if (info[key]) return info[key];
    }
    return nil;
}

#pragma mark - Connection Type

- (NSString *)currentConnectionType {
    struct sockaddr_in zeroAddress;
    memset(&zeroAddress, 0, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;

    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(
        kCFAllocatorDefault, (const struct sockaddr *)&zeroAddress);
    if (!reachability) return @"No Connection";

    SCNetworkReachabilityFlags flags;
    BOOL success = SCNetworkReachabilityGetFlags(reachability, &flags);
    CFRelease(reachability);

    if (!success || !(flags & kSCNetworkReachabilityFlagsReachable)) {
        return @"No Connection";
    }
    if (flags & kSCNetworkReachabilityFlagsIsWWAN) {
        return @"Cellular";
    }
    return @"WiFi";
}

#pragma mark - Device Model

- (NSString *)machineModel {
    static NSString *model;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        size_t size;
        sysctlbyname("hw.machine", NULL, &size, NULL, 0);
        if (size > 0) {
            char *machine = malloc(size);
            if (sysctlbyname("hw.machine", machine, &size, NULL, 0) == 0) {
                model = [NSString stringWithUTF8String:machine];
            }
            free(machine);
        }
        if (!model) model = @"Unknown";
    });
    return model;
}

@end
