#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const HARTSPCredentialErrorDomain;
FOUNDATION_EXPORT NSString *const HARTSPCredentialUsername;

typedef NS_ENUM(NSInteger, HARTSPCredentialErrorCode) {
    HARTSPCredentialErrorRandomGenerationFailed = 1,
    HARTSPCredentialErrorKeychainFailure = 2,
    HARTSPCredentialErrorInvalidStoredCredential = 3,
};

/// An immutable username/password pair for authenticating an RTSP client.
///
/// Passwords are intentionally absent from `description` and `debugDescription`.
/// Callers must also avoid placing the password in logs, telemetry, sensor state,
/// or a URL that may be retained outside the app.
@interface HARTSPCredentials : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSString *username;
@property (nonatomic, copy, readonly) NSString *password;

/// Opaque, non-secret identifier that changes whenever the password rotates.
///
/// This value is safe to persist as an options-flow synchronization marker. It
/// is not an authenticator and must not be accepted in place of the password.
@property (nonatomic, copy, readonly) NSString *revision;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

/// Owns the single per-device RTSP credential used by HA Dashboard streams.
///
/// The password is generated lazily, survives feature toggles and application
/// upgrades, and is stored only in the device Keychain. This-device-only
/// accessibility deliberately prevents backup or migration to another device.
@interface HARTSPCredentialManager : NSObject

@property (class, nonatomic, readonly) HARTSPCredentialManager *sharedManager;

/// The fixed, non-secret username (`hadashboard`).
@property (nonatomic, copy, readonly) NSString *username;

/// Creates a manager backed by a specific Keychain service.
///
/// The shared manager should be used in production. This initializer permits
/// isolated Keychain stores in focused tests without changing process state.
- (nullable instancetype)initWithServiceIdentifier:(NSString *)serviceIdentifier
    NS_DESIGNATED_INITIALIZER;

/// Uses a bundle-identifier-scoped Keychain service.
- (instancetype)init;

/// Returns the stored credential, generating and persisting it when absent.
- (nullable HARTSPCredentials *)credentialsWithError:(NSError **)error;

/// Atomically replaces the password and revision and returns the new values.
- (nullable HARTSPCredentials *)rotateCredentialsWithError:(NSError **)error;

/// Deletes the credential. A later access generates a fresh password/revision.
- (BOOL)deleteCredentialsWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
