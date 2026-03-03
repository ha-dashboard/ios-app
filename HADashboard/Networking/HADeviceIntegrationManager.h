#import <Foundation/Foundation.h>

/// Coordinates device registration, sensor reporting, and remote command handling.
/// Singleton — lifecycle tied to connection state.
@interface HADeviceIntegrationManager : NSObject

+ (instancetype)sharedManager;

/// Whether device integration is enabled (user toggle in settings).
@property (nonatomic, assign) BOOL enabled;

/// Whether the device is currently registered with HA (delegates to HADeviceRegistration).
@property (nonatomic, readonly) BOOL isRegistered;

/// Start integration (called automatically on connection if enabled and registered).
- (void)start;

/// Stop integration (called automatically on disconnect).
- (void)stop;

@end
