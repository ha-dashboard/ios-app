#import <Foundation/Foundation.h>

/// Posted when device registration with HA succeeds. userInfo contains @"webhookId".
extern NSString *const HADeviceRegistrationDidCompleteNotification;

/// Posted when HA returns 410 Gone — webhook is invalid, registration must be redone.
extern NSString *const HADeviceRegistrationDidInvalidateNotification;

@interface HADeviceRegistration : NSObject

+ (instancetype)sharedManager;

/// YES if a webhook_id is stored from a previous registration.
@property (nonatomic, readonly) BOOL isRegistered;

/// The webhook ID returned by HA during registration.
@property (nonatomic, copy, readonly) NSString *webhookId;

/// The Nabu Casa cloudhook URL (nil if not available).
@property (nonatomic, copy, readonly) NSString *cloudhookURL;

/// The Nabu Casa remote UI URL (nil if not available).
@property (nonatomic, copy, readonly) NSString *remoteUIURL;

/// Device name sent to HA. Defaults to UIDevice.currentDevice.name.
@property (nonatomic, copy, readonly) NSString *deviceName;

/// Register this device with Home Assistant.
/// Requires HAAuthManager to be configured (serverURL + accessToken).
/// Calls completion on the main queue.
- (void)registerWithCompletion:(void (^)(BOOL success, NSError *error))completion;

/// Clear local registration (webhook_id, cloudhook, remote_ui).
/// Does NOT unregister from HA server (no API for that).
- (void)unregister;

/// Send a webhook request to HA.
/// @param type The webhook type (e.g. "register_sensor", "update_sensor_states").
/// @param data The payload — NSDictionary or NSArray depending on type.
/// @param completion Called on main queue with HA's response or error.
- (void)sendWebhookWithType:(NSString *)type
                       data:(id)data
                 completion:(void (^)(id response, NSError *error))completion;

/// Resolved webhook URL (cloudhook > remote_ui > local). Nil if not registered.
- (NSURL *)resolvedWebhookURL;

@end
