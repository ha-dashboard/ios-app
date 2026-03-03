#import "HADeviceRegistration.h"
#import "HAAuthManager.h"
#import "HAKeychainHelper.h"
#import "NSMutableURLRequest+HAHelpers.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>

NSString *const HADeviceRegistrationDidCompleteNotification  = @"HADeviceRegistrationDidComplete";
NSString *const HADeviceRegistrationDidInvalidateNotification = @"HADeviceRegistrationDidInvalidate";

static NSString *const kKeychainWebhookId   = @"ha_webhook_id";
static NSString *const kKeychainCloudhookURL = @"ha_cloudhook_url";
static NSString *const kKeychainRemoteUIURL  = @"ha_remote_ui_url";
static NSString *const kKeychainDeviceId     = @"ha_device_id";

/// NSUserDefaults key for user-overridden device name (from Settings UI).
static NSString *const kDeviceNameOverride   = @"ha_device_name_override";

@interface HADeviceRegistration ()
@property (nonatomic, copy) NSString *webhookId;
@property (nonatomic, copy) NSString *cloudhookURL;
@property (nonatomic, copy) NSString *remoteUIURL;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation HADeviceRegistration

+ (instancetype)sharedManager {
    static HADeviceRegistration *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HADeviceRegistration alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _session = [NSURLSession sessionWithConfiguration:[NSMutableURLRequest ha_defaultSessionConfiguration]];
        // Restore from Keychain
        _webhookId    = [HAKeychainHelper stringForKey:kKeychainWebhookId];
        _cloudhookURL = [HAKeychainHelper stringForKey:kKeychainCloudhookURL];
        _remoteUIURL  = [HAKeychainHelper stringForKey:kKeychainRemoteUIURL];
    }
    return self;
}

#pragma mark - Properties

- (BOOL)isRegistered {
    return self.webhookId.length > 0;
}

- (NSString *)deviceName {
    // Fix 5: Read user override from NSUserDefaults first
    NSString *override = [[NSUserDefaults standardUserDefaults] stringForKey:kDeviceNameOverride];
    if (override.length > 0) return override;
    return [UIDevice currentDevice].name;
}

#pragma mark - Registration

- (void)registerWithCompletion:(void (^)(BOOL, NSError *))completion {
    HAAuthManager *auth = [HAAuthManager sharedManager];

    // Guard: demo mode has isConfigured=YES but no real server URL
    if (!auth.isConfigured || auth.isDemoMode || !auth.serverURL.length || !auth.accessToken.length) {
        NSString *reason = auth.isDemoMode ? @"Cannot register in demo mode" : @"Not configured — no server URL or token";
        NSError *err = [NSError errorWithDomain:@"HADeviceRegistration" code:-1
                                       userInfo:@{NSLocalizedDescriptionKey: reason}];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, err); });
        return;
    }

    NSDictionary *body = [self registrationBody];
    NSURL *url = [[auth restBaseURL] URLByAppendingPathComponent:@"mobile_app/registrations"];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request ha_setAuthHeaders:auth.accessToken];

    NSError *jsonError = nil;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (jsonError) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, jsonError); });
        return;
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, error); });
                return;
            }

            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            if (http.statusCode < 200 || http.statusCode >= 300) {
                NSString *msg = [NSString stringWithFormat:@"Registration failed: HTTP %ld", (long)http.statusCode];
                NSError *httpErr = [NSError errorWithDomain:@"HADeviceRegistration" code:http.statusCode
                                                  userInfo:@{NSLocalizedDescriptionKey: msg}];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, httpErr); });
                return;
            }

            NSDictionary *resp = nil;
            if (data.length > 0) {
                resp = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            }
            if (![resp isKindOfClass:[NSDictionary class]] || !resp[@"webhook_id"]) {
                NSError *parseErr = [NSError errorWithDomain:@"HADeviceRegistration" code:-2
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Invalid registration response"}];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(NO, parseErr); });
                return;
            }

            // Store credentials — guard against NSNull from JSON null values
            id wid = resp[@"webhook_id"];
            id ch  = resp[@"cloudhook_url"];
            id rui = resp[@"remote_ui_url"];
            self.webhookId    = ([wid isKindOfClass:[NSString class]] ? wid : nil);
            self.cloudhookURL = ([ch isKindOfClass:[NSString class]] ? ch : nil);
            self.remoteUIURL  = ([rui isKindOfClass:[NSString class]] ? rui : nil);

            [HAKeychainHelper setString:self.webhookId forKey:kKeychainWebhookId];
            if (self.cloudhookURL) [HAKeychainHelper setString:self.cloudhookURL forKey:kKeychainCloudhookURL];
            if (self.remoteUIURL)  [HAKeychainHelper setString:self.remoteUIURL forKey:kKeychainRemoteUIURL];

            NSLog(@"[HADeviceRegistration] Registered with webhook_id: %@", self.webhookId);

            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:HADeviceRegistrationDidCompleteNotification
                                                                    object:self
                                                                  userInfo:@{@"webhookId": self.webhookId}];
                if (completion) completion(YES, nil);
            });
        }];
    [task resume];
}

- (void)unregister {
    self.webhookId    = nil;
    self.cloudhookURL = nil;
    self.remoteUIURL  = nil;
    [HAKeychainHelper removeItemForKey:kKeychainWebhookId];
    [HAKeychainHelper removeItemForKey:kKeychainCloudhookURL];
    [HAKeychainHelper removeItemForKey:kKeychainRemoteUIURL];
    NSLog(@"[HADeviceRegistration] Unregistered (local credentials cleared)");
}

#pragma mark - Webhook

- (NSURL *)resolvedWebhookURL {
    if (!self.webhookId) return nil;

    // Priority: cloudhook > remote_ui > local
    if (self.cloudhookURL.length > 0) {
        return [NSURL URLWithString:self.cloudhookURL];
    }

    // Fix 2: Trim trailing slashes before appending path to avoid double-slash
    if (self.remoteUIURL.length > 0) {
        NSString *base = [self.remoteUIURL stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
        NSString *url = [NSString stringWithFormat:@"%@/api/webhook/%@", base, self.webhookId];
        return [NSURL URLWithString:url];
    }

    NSString *serverURL = [[HAAuthManager sharedManager] serverURL];
    if (!serverURL) return nil;
    NSString *base = [serverURL stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    NSString *url = [NSString stringWithFormat:@"%@/api/webhook/%@", base, self.webhookId];
    return [NSURL URLWithString:url];
}

- (void)sendWebhookWithType:(NSString *)type
                       data:(id)data
                 completion:(void (^)(id, NSError *))completion {
    NSURL *webhookURL = [self resolvedWebhookURL];
    if (!webhookURL) {
        NSError *err = [NSError errorWithDomain:@"HADeviceRegistration" code:-3
                                       userInfo:@{NSLocalizedDescriptionKey: @"Not registered — no webhook URL"}];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, err); });
        return;
    }

    NSDictionary *payload = @{@"type": type, @"data": data ?: @{}};

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:webhookURL];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    // Webhook requests are NOT authenticated with Bearer token — the webhook_id IS the auth

    NSError *jsonError = nil;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (jsonError) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, jsonError); });
        return;
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *responseData, NSURLResponse *response, NSError *error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, error); });
                return;
            }

            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;

            // Fix 3: 410 Gone means webhook is invalid — clear registration
            if (http.statusCode == 410) {
                NSLog(@"[HADeviceRegistration] 410 Gone — webhook invalidated, clearing registration");
                [self unregister];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:HADeviceRegistrationDidInvalidateNotification
                                                                        object:self userInfo:nil];
                    NSError *goneErr = [NSError errorWithDomain:@"HADeviceRegistration" code:410
                                                      userInfo:@{NSLocalizedDescriptionKey: @"Webhook invalidated (410 Gone) — re-register required"}];
                    if (completion) completion(nil, goneErr);
                });
                return;
            }

            if (http.statusCode < 200 || http.statusCode >= 300) {
                NSString *msg = [NSString stringWithFormat:@"Webhook failed: HTTP %ld", (long)http.statusCode];
                NSError *httpErr = [NSError errorWithDomain:@"HADeviceRegistration" code:http.statusCode
                                                  userInfo:@{NSLocalizedDescriptionKey: msg}];
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, httpErr); });
                return;
            }

            id parsed = nil;
            if (responseData.length > 0) {
                parsed = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(parsed, nil); });
        }];
    [task resume];
}

#pragma mark - Private

- (NSDictionary *)registrationBody {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *appVersion = info[@"CFBundleShortVersionString"] ?: @"0.0.0";

    return @{
        @"device_id":            [self persistentDeviceId],
        @"app_id":               @"io.hadashboard.app",
        @"app_name":             @"HA Dashboard",
        @"app_version":          appVersion,
        @"device_name":          self.deviceName,
        @"manufacturer":         @"Apple",
        @"model":                [self machineModel],
        @"os_name":              @"iOS",
        @"os_version":           [UIDevice currentDevice].systemVersion,
        @"supports_encryption":  @NO,
    };
}

/// Fix 1: Stable device ID persisted in Keychain. Falls back to identifierForVendor,
/// then random UUID. Once generated, always reused from Keychain.
- (NSString *)persistentDeviceId {
    NSString *stored = [HAKeychainHelper stringForKey:kKeychainDeviceId];
    if (stored.length > 0) return stored;

    NSString *deviceId = [UIDevice currentDevice].identifierForVendor.UUIDString;
    if (!deviceId) {
        deviceId = [[NSUUID UUID] UUIDString];
    }
    [HAKeychainHelper setString:deviceId forKey:kKeychainDeviceId];
    return deviceId;
}

- (NSString *)machineModel {
#if TARGET_OS_SIMULATOR
    return @"Simulator";
#else
    struct utsname systemInfo;
    if (uname(&systemInfo) == 0) {
        return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    }
    return @"Unknown";
#endif
}

@end
