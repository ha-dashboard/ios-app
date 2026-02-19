#import "HAAuthManager.h"
#import "HAKeychainHelper.h"
#import "HAOAuthClient.h"
#import "HAStartupLog.h"

NSString *const HAAuthManagerDidUpdateNotification = @"HAAuthManagerDidUpdateNotification";

static NSString *const kServerURLKey     = @"ha_server_url";
static NSString *const kAccessTokenKey   = @"ha_access_token";
static NSString *const kAuthModeKey      = @"ha_auth_mode";
static NSString *const kRefreshTokenKey  = @"ha_refresh_token";
static NSString *const kTokenExpiryKey   = @"ha_token_expiry";
static NSString *const kSelectedDashboardKey = @"ha_selected_dashboard";
static NSString *const kKioskModeKey     = @"ha_kiosk_mode";
static NSString *const kDemoModeKey      = @"ha_demo_mode";

@interface HAAuthManager ()
@property (nonatomic, copy, readwrite) NSString *serverURL;
@property (nonatomic, copy, readwrite) NSString *accessToken;
@property (nonatomic, assign, readwrite) HAAuthMode authMode;
@property (nonatomic, copy, readwrite) NSString *refreshToken;
@property (nonatomic, copy, readwrite) NSDate *tokenExpiresAt;
@property (nonatomic, copy, readwrite) NSString *selectedDashboardPath;
@property (nonatomic, assign, readwrite, getter=isKioskMode) BOOL kioskMode;
@property (nonatomic, assign, readwrite, getter=isDemoMode) BOOL demoMode;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, assign) BOOL isRefreshing;
@end

@implementation HAAuthManager

+ (instancetype)sharedManager {
    static HAAuthManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HAAuthManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [HAStartupLog log:@"HAAuthManager init BEGIN — keychain reads"];
        _serverURL = [HAKeychainHelper stringForKey:kServerURLKey];
        [HAStartupLog log:@"  keychain: serverURL done"];
        _accessToken = [HAKeychainHelper stringForKey:kAccessTokenKey];
        [HAStartupLog log:@"  keychain: accessToken done"];
        _refreshToken = [HAKeychainHelper stringForKey:kRefreshTokenKey];
        [HAStartupLog log:@"  keychain: refreshToken done"];
        _selectedDashboardPath = [[NSUserDefaults standardUserDefaults] stringForKey:kSelectedDashboardKey];
        _kioskMode = [[NSUserDefaults standardUserDefaults] boolForKey:kKioskModeKey];
        _demoMode = [[NSUserDefaults standardUserDefaults] boolForKey:kDemoModeKey];

        // Restore auth mode
        NSString *modeStr = [HAKeychainHelper stringForKey:kAuthModeKey];
        [HAStartupLog log:@"  keychain: authMode done"];
        _authMode = [modeStr integerValue]; // 0 (token) if nil

        // Restore token expiry
        NSString *expiryStr = [HAKeychainHelper stringForKey:kTokenExpiryKey];
        [HAStartupLog log:@"  keychain: tokenExpiry done"];
        if (expiryStr) {
            _tokenExpiresAt = [NSDate dateWithTimeIntervalSince1970:[expiryStr doubleValue]];
        }

        [HAStartupLog log:@"HAAuthManager init END"];

        // Schedule refresh if needed
        if (_authMode == HAAuthModeOAuth && _refreshToken.length > 0) {
            [self scheduleTokenRefresh];
        }
    }
    return self;
}

- (BOOL)isConfigured {
    if (self.demoMode) return YES;
    return self.serverURL.length > 0 && self.accessToken.length > 0;
}

#pragma mark - Save Credentials

+ (NSString *)normalizedURL:(NSString *)url {
    NSString *normalized = url;
    while ([normalized hasSuffix:@"/"]) {
        normalized = [normalized substringToIndex:normalized.length - 1];
    }
    return normalized;
}

- (void)saveServerURL:(NSString *)url token:(NSString *)token {
    NSString *normalizedURL = [HAAuthManager normalizedURL:url];

    [HAKeychainHelper setString:normalizedURL forKey:kServerURLKey];
    [HAKeychainHelper setString:token forKey:kAccessTokenKey];
    [HAKeychainHelper setString:@"0" forKey:kAuthModeKey];

    // Clear OAuth-specific keys
    [HAKeychainHelper removeItemForKey:kRefreshTokenKey];
    [HAKeychainHelper removeItemForKey:kTokenExpiryKey];

    self.serverURL = normalizedURL;
    self.accessToken = token;
    self.authMode = HAAuthModeToken;
    self.refreshToken = nil;
    self.tokenExpiresAt = nil;

    [self.refreshTimer invalidate];
    self.refreshTimer = nil;

    [[NSNotificationCenter defaultCenter] postNotificationName:HAAuthManagerDidUpdateNotification object:self];
}

- (void)saveOAuthCredentials:(NSString *)serverURL
                 accessToken:(NSString *)accessToken
                refreshToken:(NSString *)refreshToken
                   expiresIn:(NSTimeInterval)expiresIn {
    NSString *normalizedURL = [HAAuthManager normalizedURL:serverURL];
    NSDate *expiry = [NSDate dateWithTimeIntervalSinceNow:expiresIn];

    [HAKeychainHelper setString:normalizedURL forKey:kServerURLKey];
    [HAKeychainHelper setString:accessToken forKey:kAccessTokenKey];
    [HAKeychainHelper setString:@"1" forKey:kAuthModeKey];
    [HAKeychainHelper setString:refreshToken forKey:kRefreshTokenKey];
    [HAKeychainHelper setString:[NSString stringWithFormat:@"%f", [expiry timeIntervalSince1970]] forKey:kTokenExpiryKey];

    self.serverURL = normalizedURL;
    self.accessToken = accessToken;
    self.authMode = HAAuthModeOAuth;
    self.refreshToken = refreshToken;
    self.tokenExpiresAt = expiry;

    [self scheduleTokenRefresh];

    [[NSNotificationCenter defaultCenter] postNotificationName:HAAuthManagerDidUpdateNotification object:self];
}

- (void)updateAccessToken:(NSString *)accessToken expiresIn:(NSTimeInterval)expiresIn {
    NSDate *expiry = [NSDate dateWithTimeIntervalSinceNow:expiresIn];

    [HAKeychainHelper setString:accessToken forKey:kAccessTokenKey];
    [HAKeychainHelper setString:[NSString stringWithFormat:@"%f", [expiry timeIntervalSince1970]] forKey:kTokenExpiryKey];

    self.accessToken = accessToken;
    self.tokenExpiresAt = expiry;

    [self scheduleTokenRefresh];

    [[NSNotificationCenter defaultCenter] postNotificationName:HAAuthManagerDidUpdateNotification object:self];
}

#pragma mark - Token Refresh

- (BOOL)needsTokenRefresh {
    if (self.authMode != HAAuthModeOAuth) return NO;
    if (!self.tokenExpiresAt) return NO;
    // Refresh if within 5 minutes of expiry
    return [self.tokenExpiresAt timeIntervalSinceNow] < 300.0;
}

- (void)scheduleTokenRefresh {
    [self.refreshTimer invalidate];

    if (self.authMode != HAAuthModeOAuth || !self.tokenExpiresAt) return;

    NSTimeInterval delay = [self.tokenExpiresAt timeIntervalSinceNow] - 300.0;
    if (delay < 10.0) delay = 10.0; // At least 10 seconds from now

    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                         target:self
                                                       selector:@selector(proactiveRefresh)
                                                       userInfo:nil
                                                        repeats:NO];
}

- (void)proactiveRefresh {
    NSLog(@"[HAAuth] Proactive token refresh triggered");
    [self refreshAccessTokenWithCompletion:^(BOOL success, NSError *error) {
        if (success) {
            NSLog(@"[HAAuth] Proactive refresh succeeded");
        } else {
            NSLog(@"[HAAuth] Proactive refresh failed: %@", error.localizedDescription);
        }
    }];
}

- (void)refreshAccessTokenWithCompletion:(void (^)(BOOL success, NSError *error))completion {
    if (self.authMode != HAAuthModeOAuth || self.refreshToken.length == 0 || self.serverURL.length == 0) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"HAAuthManager" code:0
                                           userInfo:@{NSLocalizedDescriptionKey: @"Not in OAuth mode or no refresh token"}];
            completion(NO, err);
        }
        return;
    }

    if (self.isRefreshing) {
        // Already refreshing, skip duplicate
        if (completion) completion(NO, nil);
        return;
    }
    self.isRefreshing = YES;

    HAOAuthClient *oauth = [[HAOAuthClient alloc] initWithServerURL:self.serverURL];
    [oauth refreshWithToken:self.refreshToken completion:^(NSDictionary *tokenResponse, NSError *error) {
        self.isRefreshing = NO;

        if (error || !tokenResponse[@"access_token"]) {
            NSLog(@"[HAAuth] Token refresh failed: %@", error.localizedDescription);
            if (completion) completion(NO, error);
            return;
        }

        NSString *newToken = tokenResponse[@"access_token"];
        NSTimeInterval expiresIn = [tokenResponse[@"expires_in"] doubleValue];
        if (expiresIn <= 0) expiresIn = 1800; // Default 30 min

        [self updateAccessToken:newToken expiresIn:expiresIn];
        NSLog(@"[HAAuth] Token refreshed, expires in %.0fs", expiresIn);

        if (completion) completion(YES, nil);
    }];
}

#pragma mark - Other Settings

- (void)saveSelectedDashboardPath:(NSString *)urlPath {
    self.selectedDashboardPath = urlPath;
    if (urlPath) {
        [[NSUserDefaults standardUserDefaults] setObject:urlPath forKey:kSelectedDashboardKey];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSelectedDashboardKey];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:HAAuthManagerDidUpdateNotification object:self];
}

- (void)setKioskMode:(BOOL)enabled {
    _kioskMode = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kKioskModeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:HAAuthManagerDidUpdateNotification object:self];
}

- (void)setDemoMode:(BOOL)enabled {
    _demoMode = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kDemoModeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:HAAuthManagerDidUpdateNotification object:self];
}

- (void)clearCredentials {
    [HAKeychainHelper removeItemForKey:kServerURLKey];
    [HAKeychainHelper removeItemForKey:kAccessTokenKey];
    [HAKeychainHelper removeItemForKey:kAuthModeKey];
    [HAKeychainHelper removeItemForKey:kRefreshTokenKey];
    [HAKeychainHelper removeItemForKey:kTokenExpiryKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSelectedDashboardKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kKioskModeKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDemoModeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    self.serverURL = nil;
    self.accessToken = nil;
    self.authMode = HAAuthModeToken;
    self.refreshToken = nil;
    self.tokenExpiresAt = nil;
    self.selectedDashboardPath = nil;
    self.kioskMode = NO;
    self.demoMode = NO;

    [self.refreshTimer invalidate];
    self.refreshTimer = nil;

    [[NSNotificationCenter defaultCenter] postNotificationName:HAAuthManagerDidUpdateNotification object:self];
}

#pragma mark - URL Helpers

- (NSURL *)restBaseURL {
    if (!self.serverURL) return nil;
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@/api", self.serverURL]];
}

- (NSURL *)webSocketURL {
    if (!self.serverURL) return nil;

    NSString *wsURL = self.serverURL;
    if ([wsURL hasPrefix:@"https://"]) {
        wsURL = [wsURL stringByReplacingCharactersInRange:NSMakeRange(0, 5) withString:@"wss"];
    } else if ([wsURL hasPrefix:@"http://"]) {
        wsURL = [wsURL stringByReplacingCharactersInRange:NSMakeRange(0, 4) withString:@"ws"];
    }

    return [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/websocket", wsURL]];
}

@end
