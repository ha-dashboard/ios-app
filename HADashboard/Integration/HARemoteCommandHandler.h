#import <Foundation/Foundation.h>

/// Notification posted when a remote command is dispatched.
/// userInfo: @{@"command": NSString, @"data": NSDictionary}
extern NSString *const HARemoteCommandNotification;

/// Notification posted when a reload command is received.
/// HADeviceIntegrationManager handles this to coordinate stop→disconnect→reconnect→start.
extern NSString *const HARemoteCommandReloadNotification;

/// Listens for remote commands from HA and dispatches them to the app.
/// Commands arrive via push notification payloads or WebSocket events.
@interface HARemoteCommandHandler : NSObject

/// Start listening for commands on the WebSocket.
- (void)startListening;

/// Stop listening.
- (void)stopListening;

@end
