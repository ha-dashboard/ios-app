#import <Foundation/Foundation.h>

extern NSString *const HACameraRegistrationDidChangeNotification;

/// Creates or updates Home Assistant Generic Camera config entries for the
/// app's local RTSP sources using the currently logged-in user's token.
@interface HACameraRegistrationManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, readonly, getter=isRegistering) BOOL registering;
@property (nonatomic, copy, readonly) NSArray<NSString *> *registeredEntryIDs;
@property (nonatomic, strong, readonly) NSError *lastError;
/// A transient Home Assistant/config-flow failure is waiting for its next
/// retry. `retryAttempt` counts retries after the initial attempt.
@property (nonatomic, readonly, getter=isRetryScheduled) BOOL retryScheduled;
@property (nonatomic, readonly) NSUInteger retryAttempt;
@property (nonatomic, readonly) NSTimeInterval scheduledRetryDelay;

/// YES when the current server is HTTPS or a loopback, .local, link-local, or
/// private-network HTTP address. Non-local HTTP is refused.
@property (nonatomic, readonly) BOOL automaticRegistrationTransportAllowed;

/// Reconciliation is asynchronous. A retryable failure keeps `completion`
/// pending across context-bound retries; it reports eventual success or a
/// terminal failure. Cancellation invalidates the work without invoking it.
- (void)ensureCameraEntriesForStreamURLs:(NSArray<NSString *> *)streamURLs
                              deviceName:(NSString *)deviceName
                                username:(NSString *)username
                                password:(NSString *)password
                      credentialRevision:(NSString *)credentialRevision
                         framesPerSecond:(NSInteger)framesPerSecond
                              completion:(void (^)(BOOL success, NSError *error))completion;

/// Cancels in-flight requests and scheduled retries, invalidates their
/// callbacks, and releases all in-memory copies of the stream credential.
- (void)cancelRegistration;

/// Cancels registration and clears this manager's in-memory result/error state.
/// Persistent app defaults are cleared by the caller's full reset transaction.
- (void)resetLocalRegistrationState;

@end
