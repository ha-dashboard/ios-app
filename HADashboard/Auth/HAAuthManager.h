#import <Foundation/Foundation.h>

extern NSString *const HAAuthManagerDidUpdateNotification;

typedef NS_ENUM(NSInteger, HAAuthMode) {
    HAAuthModeToken = 0,   // Long-lived access token
    HAAuthModeOAuth = 1    // Username/password login (OAuth flow)
};

@interface HAAuthManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, copy, readonly) NSString *serverURL;
@property (nonatomic, copy, readonly) NSString *accessToken;
@property (nonatomic, readonly, getter=isConfigured) BOOL configured;

@property (nonatomic, assign, readonly) HAAuthMode authMode;
@property (nonatomic, copy, readonly) NSString *refreshToken;
@property (nonatomic, copy, readonly) NSDate *tokenExpiresAt;

/// Selected dashboard URL path (nil = default dashboard)
@property (nonatomic, copy, readonly) NSString *selectedDashboardPath;

/// Kiosk mode: hides nav bar, disables screen sleep
@property (nonatomic, readonly, getter=isKioskMode) BOOL kioskMode;

/// Wake on touch after idle: dims screen after 60 s inactivity, wakes on touch.
/// Only active when kiosk mode is also enabled.
@property (nonatomic, readonly) BOOL proximityWakeEnabled;

/// Demo mode: uses bundled demo data instead of connecting to a real server
@property (nonatomic, readonly, getter=isDemoMode) BOOL demoMode;

/// Auto-reload dashboard when its Lovelace config changes on the server (default: YES)
@property (nonatomic, readonly) BOOL autoReloadDashboard;

/// Camera streams are muted by default in grid and fullscreen (default: YES)
@property (nonatomic, readonly) BOOL cameraGlobalMute;

/// Save long-lived access token (existing flow)
- (void)saveServerURL:(NSString *)url token:(NSString *)token;

/// Save OAuth credentials from login flow
- (void)saveOAuthCredentials:(NSString *)serverURL
                 accessToken:(NSString *)accessToken
                refreshToken:(NSString *)refreshToken
                   expiresIn:(NSTimeInterval)expiresIn;

/// Update just the access token after a refresh
- (void)updateAccessToken:(NSString *)accessToken expiresIn:(NSTimeInterval)expiresIn;

/// YES if access token expires within 5 minutes
- (BOOL)needsTokenRefresh;

/// Refresh the access token using the stored refresh token.
/// Only works in HAAuthModeOAuth. Calls completion on main queue.
- (void)refreshAccessTokenWithCompletion:(void (^)(BOOL success, NSError *error))completion;

/// Handle an authentication failure by attempting a token refresh if in OAuth mode.
/// On success, returns the new access token. On failure (or non-OAuth mode), returns an error.
/// Callers should update their local token copy and retry their operation on success.
- (void)handleAuthFailureWithCompletion:(void (^)(NSString *newToken, NSError *error))completion;

- (void)saveSelectedDashboardPath:(NSString *)urlPath;
- (void)setKioskMode:(BOOL)enabled;
- (void)setProximityWakeEnabled:(BOOL)enabled;
- (void)setDemoMode:(BOOL)enabled;
- (void)setAutoReloadDashboard:(BOOL)enabled;
- (void)setCameraGlobalMute:(BOOL)muted;
- (void)clearCredentials;

/// Returns full base URL for REST API, e.g. http://192.168.1.100:8123/api
- (NSURL *)restBaseURL;

/// Returns WebSocket URL, e.g. ws://192.168.1.100:8123/api/websocket
- (NSURL *)webSocketURL;

/// Strips trailing slashes from a URL string.
+ (NSString *)normalizedURL:(NSString *)url;

@end
