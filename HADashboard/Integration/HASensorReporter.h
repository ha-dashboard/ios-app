#import <Foundation/Foundation.h>

/// Reports device sensors (battery, brightness) to HA via webhook API.
/// Uses HADeviceRegistration for webhook transport.
@interface HASensorReporter : NSObject

/// Register all enabled sensors with HA (call once after device registration).
- (void)registerSensors;

/// Start monitoring sensor changes and reporting them.
- (void)startReporting;

/// Stop monitoring and reporting.
- (void)stopReporting;

/// Force an immediate update of all sensors.
- (void)reportAllSensorsNow;

@end
