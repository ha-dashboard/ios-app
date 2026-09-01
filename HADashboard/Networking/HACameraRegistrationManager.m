#import "HACameraRegistrationManager.h"
#import "HAAPIClient.h"
#import "HAAuthManager.h"
#import "HAConnectionManager.h"
#import "HADeviceIntegrationManager.h"
#import "HAStreamingManager.h"
#import "HALog.h"
#import <arpa/inet.h>

NSString *const HACameraRegistrationDidChangeNotification = @"HACameraRegistrationDidChangeNotification";

static NSString *const kHACameraPrimaryEntryIDKey = @"ha_camera_primary_entry_id";
static NSString *const kHACameraSecondaryEntryIDKey = @"ha_camera_secondary_entry_id";
static NSString *const kHACameraPrimaryURLKey = @"ha_camera_primary_stream_url";
static NSString *const kHACameraSecondaryURLKey = @"ha_camera_secondary_stream_url";
static NSString *const kHACameraPrimaryCredentialRevisionKey = @"ha_camera_primary_credential_revision";
static NSString *const kHACameraSecondaryCredentialRevisionKey = @"ha_camera_secondary_credential_revision";
static NSString *const kHACameraPrimaryFramesPerSecondKey = @"ha_camera_primary_frames_per_second";
static NSString *const kHACameraSecondaryFramesPerSecondKey = @"ha_camera_secondary_frames_per_second";
static NSString *const kHALegacyCameraInsecureConsentOriginKey = @"ha_camera_insecure_consent_origin";
static NSString *const HACameraRegistrationErrorDomain = @"HACameraRegistrationErrorDomain";
static NSString *const HACameraRegistrationRetryableKey = @"HACameraRegistrationRetryable";
static const NSTimeInterval HACameraRegistrationRequestTimeout = 75.0;
static const NSTimeInterval HACameraRegistrationResourceTimeout = 120.0;
static const NSTimeInterval HACameraRegistrationInitialRetryDelay = 2.0;
static const NSTimeInterval HACameraRegistrationMaximumRetryDelay = 60.0;

static NSTimeInterval HACameraRegistrationRetryDelay(NSUInteger attempt) {
    // Avoid an unbounded left shift: after 2/4/8/16/32 seconds, retry once a
    // minute for as long as the exact registration context remains current.
    switch (attempt) {
        case 0:
        case 1: return HACameraRegistrationInitialRetryDelay;
        case 2: return 4.0;
        case 3: return 8.0;
        case 4: return 16.0;
        case 5: return 32.0;
        default: return HACameraRegistrationMaximumRetryDelay;
    }
}

typedef HAAPIClient *(^HACameraRegistrationAPIClientFactory)(NSURL *baseURL,
                                                              NSString *token,
                                                              NSTimeInterval requestTimeout,
                                                              NSTimeInterval resourceTimeout);
typedef id (^HACameraRegistrationRetryScheduler)(NSTimeInterval delay,
                                                  dispatch_block_t block);
typedef void (^HACameraRegistrationRetryCanceller)(id token);

@interface HACameraRegistrationRetryToken : NSObject
@property (nonatomic, assign, getter=isCancelled) BOOL cancelled;
@end

@implementation HACameraRegistrationRetryToken
@end

static BOOL HACameraHostIsLocalNetwork(NSString *host) {
    NSString *value = host.lowercaseString;
    if (!value.length) return NO;
    if ([value isEqualToString:@"localhost"] || [value hasSuffix:@".local"]) return YES;

    struct in_addr ipv4;
    if (inet_pton(AF_INET, value.UTF8String, &ipv4) == 1) {
        uint32_t address = ntohl(ipv4.s_addr);
        return (address & 0xFF000000) == 0x0A000000 ||
               (address & 0xFFF00000) == 0xAC100000 ||
               (address & 0xFFFF0000) == 0xC0A80000 ||
               (address & 0xFF000000) == 0x7F000000 ||
               (address & 0xFFFF0000) == 0xA9FE0000;
    }

    struct in6_addr ipv6;
    if (inet_pton(AF_INET6, value.UTF8String, &ipv6) == 1) {
        const uint8_t *bytes = ipv6.s6_addr;
        return IN6_IS_ADDR_LOOPBACK(&ipv6) ||
               (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) ||
               ((bytes[0] & 0xFE) == 0xFC);
    }
    return NO;
}

@interface HACameraRegistrationManager ()
@property (nonatomic, assign, readwrite, getter=isRegistering) BOOL registering;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *registeredEntryIDs;
@property (nonatomic, strong, readwrite) NSError *lastError;
@property (nonatomic, assign, readwrite, getter=isRetryScheduled) BOOL retryScheduled;
@property (nonatomic, assign, readwrite) NSUInteger retryAttempt;
@property (nonatomic, assign, readwrite) NSTimeInterval scheduledRetryDelay;
@property (nonatomic, strong) HAAPIClient *apiClient;
@property (nonatomic, copy) NSArray<NSString *> *pendingURLs;
@property (nonatomic, copy) NSArray<NSDictionary *> *existingEntries;
@property (nonatomic, copy) NSString *deviceName;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, copy) NSString *credentialRevision;
@property (nonatomic, assign) NSInteger framesPerSecond;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, strong) NSMutableArray<NSString *> *resultEntryIDs;
@property (nonatomic, copy) void (^completion)(BOOL success, NSError *error);
@property (nonatomic, assign) NSUInteger cancellationGeneration;
@property (nonatomic, assign) NSUInteger activeAuthenticationRevision;
@property (nonatomic, copy) NSString *activeServerOriginToken;
@property (nonatomic, copy) NSString *activeFlowID;
@property (nonatomic, assign) BOOL activeFlowIsOptionsFlow;
@property (nonatomic, copy) HACameraRegistrationAPIClientFactory apiClientFactory;
@property (nonatomic, copy) HACameraRegistrationRetryScheduler retryScheduler;
@property (nonatomic, copy) HACameraRegistrationRetryCanceller retryCanceller;
@property (nonatomic, strong) id scheduledRetryToken;
- (NSDictionary *)cameraConfigurationInputForURL:(NSString *)url
                                      optionsFlow:(BOOL)optionsFlow;
- (NSError *)cameraCredentialTransportErrorForURL:(NSURL *)URL;
@end

@implementation HACameraRegistrationManager

+ (instancetype)sharedManager {
    static HACameraRegistrationManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (instancetype)init {
    return [self initWithAPIClientFactory:nil scheduleRetry:nil cancelScheduledRetry:nil];
}

- (instancetype)initWithAPIClientFactory:(HACameraRegistrationAPIClientFactory)apiClientFactory
                            scheduleRetry:(HACameraRegistrationRetryScheduler)retryScheduler
                     cancelScheduledRetry:(HACameraRegistrationRetryCanceller)retryCanceller {
    self = [super init];
    if (self) {
        _registeredEntryIDs = @[];
        if (apiClientFactory) {
            _apiClientFactory = [apiClientFactory copy];
        } else {
            _apiClientFactory = [^HAAPIClient *(NSURL *baseURL, NSString *token,
                                                NSTimeInterval requestTimeout,
                                                NSTimeInterval resourceTimeout) {
                return [[HAAPIClient alloc] initWithBaseURL:baseURL token:token
                                    requestTimeoutInterval:requestTimeout
                                   resourceTimeoutInterval:resourceTimeout];
            } copy];
        }
        if (retryScheduler) {
            _retryScheduler = [retryScheduler copy];
        } else {
            _retryScheduler = [^id(NSTimeInterval delay, dispatch_block_t block) {
                HACameraRegistrationRetryToken *token = [[HACameraRegistrationRetryToken alloc] init];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (!token.isCancelled && block) block();
                });
                return token;
            } copy];
        }
        if (retryCanceller) {
            _retryCanceller = [retryCanceller copy];
        } else {
            _retryCanceller = [^(id token) {
                if ([token isKindOfClass:[HACameraRegistrationRetryToken class]]) {
                    ((HACameraRegistrationRetryToken *)token).cancelled = YES;
                }
            } copy];
        }
        // Local-network HTTP registration no longer stores a per-origin
        // approval. Remove the obsolete value on upgrade as well as reset.
        [[NSUserDefaults standardUserDefaults]
            removeObjectForKey:kHALegacyCameraInsecureConsentOriginKey];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(authenticationDidChange:)
            name:HAAuthManagerDidUpdateNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(streamingStateDidChange:)
            name:HAStreamingManagerStateDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.scheduledRetryToken) self.retryCanceller(self.scheduledRetryToken);
    [self.apiClient cancelAllRequests];
}

- (NSString *)currentServerOriginToken {
    NSURL *URL = [HAAuthManager sharedManager].restBaseURL;
    NSString *scheme = URL.scheme.lowercaseString;
    NSString *host = URL.host.lowercaseString;
    if (!scheme.length || !host.length) return nil;
    NSNumber *port = URL.port;
    if (!port) port = [scheme isEqualToString:@"https"] ? @443 : @80;
    return [NSString stringWithFormat:@"%@|%@|%@", scheme, host, port];
}

- (NSError *)cameraCredentialTransportErrorForURL:(NSURL *)URL {
    NSString *scheme = URL.scheme.lowercaseString;
    if ([scheme isEqualToString:@"https"]) return nil;
    if ([scheme isEqualToString:@"http"] && HACameraHostIsLocalNetwork(URL.host)) return nil;
    return [self error:@"Camera registration blocked: this Home Assistant address must use HTTPS."];
}

- (NSError *)cameraCredentialTransportError {
    return [self cameraCredentialTransportErrorForURL:[HAAuthManager sharedManager].restBaseURL];
}

- (BOOL)automaticRegistrationTransportAllowed {
    return [self cameraCredentialTransportError] == nil;
}

- (BOOL)activeAuthenticationIsCurrent {
    if (!self.activeServerOriginToken.length) return NO;
    HAAuthManager *auth = [HAAuthManager sharedManager];
    return !auth.isDemoMode &&
           auth.authenticationRevision == self.activeAuthenticationRevision &&
           [[self currentServerOriginToken] isEqualToString:self.activeServerOriginToken];
}

- (BOOL)streamListenerIsArmedForPendingURLs {
    HAStreamingManager *stream = [HAStreamingManager sharedManager];
    return stream.streaming && self.pendingURLs.count > 0 &&
           [stream.streamURLs isEqualToArray:self.pendingURLs];
}

- (BOOL)registrationCanContinue {
    return self.isRegistering &&
           [HADeviceIntegrationManager sharedManager].enabled &&
           [self activeAuthenticationIsCurrent] &&
           [self streamListenerIsArmedForPendingURLs];
}

- (BOOL)requestClientIsCurrent:(HAAPIClient *)requestClient {
    return self.apiClient == requestClient && [self registrationCanContinue];
}

- (BOOL)ensureActiveAuthenticationOrCancel {
    if ([self activeAuthenticationIsCurrent]) return YES;
    [self cancelRegistration];
    return NO;
}

- (void)authenticationDidChange:(NSNotification *)notification {
    (void)notification;
    if (self.isRegistering && ![self activeAuthenticationIsCurrent]) {
        [self cancelRegistration];
    }
}

- (void)streamingStateDidChange:(NSNotification *)notification {
    (void)notification;
    if (self.isRegistering && ![self streamListenerIsArmedForPendingURLs]) {
        [self cancelRegistration];
    }
}

- (void)failBeforeRegistration:(NSError *)error
                     completion:(void (^)(BOOL success, NSError *error))completion {
    self.retryScheduled = NO;
    self.retryAttempt = 0;
    self.scheduledRetryDelay = 0;
    self.lastError = error;
    [self postChange];
    if (completion) completion(NO, error);
}

- (NSError *)registrationPreflightError {
    if (![HADeviceIntegrationManager sharedManager].enabled) {
        return [self error:@"Enable Register with Home Assistant before adding protected camera entries."];
    }
    HAAuthManager *auth = [HAAuthManager sharedManager];
    if (!auth.isConfigured || auth.isDemoMode || !auth.accessToken.length) {
        return [self error:@"Sign in to Home Assistant before registering camera streams."];
    }
    return [self cameraCredentialTransportError];
}

- (BOOL)activeRegistrationMatchesURLs:(NSArray<NSString *> *)streamURLs
                            deviceName:(NSString *)deviceName
                              username:(NSString *)username
                              password:(NSString *)password
                    credentialRevision:(NSString *)credentialRevision
                       framesPerSecond:(NSInteger)framesPerSecond {
    return [self.pendingURLs isEqualToArray:streamURLs] &&
           [self.deviceName isEqualToString:deviceName] &&
           [self.username isEqualToString:username] &&
           [self.password isEqualToString:password] &&
           [self.credentialRevision isEqualToString:credentialRevision] &&
           self.framesPerSecond == framesPerSecond;
}

- (void)coalesceCompletion:(void (^)(BOOL success, NSError *error))completion {
    if (!completion) return;
    void (^existingCompletion)(BOOL, NSError *) = self.completion;
    if (!existingCompletion) {
        self.completion = completion;
        return;
    }
    if (existingCompletion == completion) return;
    self.completion = ^(BOOL success, NSError *error) {
        existingCompletion(success, error);
        completion(success, error);
    };
}

- (void)ensureCameraEntriesForStreamURLs:(NSArray<NSString *> *)streamURLs
                              deviceName:(NSString *)deviceName
                                username:(NSString *)username
                                password:(NSString *)password
                      credentialRevision:(NSString *)credentialRevision
                         framesPerSecond:(NSInteger)framesPerSecond
                              completion:(void (^)(BOOL, NSError *))completion {
    if (streamURLs.count == 0) {
        [self failBeforeRegistration:[self error:@"No local RTSP stream is armed."]
                           completion:completion];
        return;
    }
    if (!username.length || !password.length || !credentialRevision.length) {
        [self failBeforeRegistration:[self error:@"Protected stream credentials are unavailable."]
                           completion:completion];
        return;
    }
    if (framesPerSecond <= 0) {
        [self failBeforeRegistration:[self error:@"The local camera stream frame rate is invalid."]
                           completion:completion];
        return;
    }
    NSError *preflightError = [self registrationPreflightError];
    if (preflightError) {
        [self failBeforeRegistration:preflightError completion:completion];
        return;
    }
    HAAuthManager *auth = [HAAuthManager sharedManager];
    NSString *normalizedDeviceName = deviceName.length ? [deviceName copy] : @"HA Dashboard";
    if (self.registering) {
        if ([self activeRegistrationMatchesURLs:streamURLs
                                      deviceName:normalizedDeviceName
                                        username:username
                                        password:password
                              credentialRevision:credentialRevision
                                 framesPerSecond:framesPerSecond]) {
            // Duplicate lifecycle notifications share the active result; they
            // do not queue another full run behind an indefinitely retrying one.
            [self coalesceCompletion:completion];
            return;
        }

        // Password rotation, address/camera changes, frame-rate changes, and
        // device renames must supersede a retry immediately. Cancellation bumps
        // the generation so even an already-delivered old timer cannot resume.
        [self cancelRegistration];
    }

    self.registering = YES;
    self.lastError = nil;
    self.pendingURLs = [streamURLs copy];
    self.deviceName = normalizedDeviceName;
    self.username = [username copy];
    self.password = [password copy];
    self.credentialRevision = [credentialRevision copy];
    self.framesPerSecond = framesPerSecond;
    self.currentIndex = 0;
    self.resultEntryIDs = [NSMutableArray array];
    self.completion = completion;
    self.retryAttempt = 0;
    self.retryScheduled = NO;
    self.scheduledRetryDelay = 0;
    self.activeAuthenticationRevision = auth.authenticationRevision;
    self.activeServerOriginToken = [self currentServerOriginToken];
    if (!self.activeServerOriginToken.length) {
        [self finish:NO error:[self error:@"The Home Assistant server origin is invalid."]];
        return;
    }
    [self postChange];
    [self beginRegistrationAttempt];
}

- (void)beginRegistrationAttempt {
    if (![self registrationCanContinue]) {
        [self cancelRegistration];
        return;
    }

    if (self.scheduledRetryToken) {
        self.retryCanceller(self.scheduledRetryToken);
        self.scheduledRetryToken = nil;
    }
    self.retryScheduled = NO;
    self.scheduledRetryDelay = 0;
    [self.apiClient cancelAllRequests];
    self.apiClient = nil;
    self.activeFlowID = nil;
    self.activeFlowIsOptionsFlow = NO;
    self.currentIndex = 0;
    self.resultEntryIDs = [NSMutableArray array];

    HAAuthManager *auth = [HAAuthManager sharedManager];
    self.apiClient = self.apiClientFactory(auth.restBaseURL, auth.accessToken,
        HACameraRegistrationRequestTimeout, HACameraRegistrationResourceTimeout);
    if (!self.apiClient) {
        [self finish:NO error:[self error:@"Could not create a Home Assistant camera-registration client."]];
        return;
    }
    [self postChange];

    __weak typeof(self) weakSelf = self;
    HAAPIClient *requestClient = self.apiClient;
    [requestClient getJSONAtPath:@"config/config_entries/entry?domain=generic" completion:^(id response, NSError *error) {
        if (![weakSelf requestClientIsCurrent:requestClient]) return;
        if (error) {
            [weakSelf handleRegistrationError:[weakSelf cameraPermissionError:error]
                                requestClient:requestClient];
            return;
        }
        weakSelf.existingEntries = [response isKindOfClass:[NSArray class]] ? response : @[];
        [weakSelf processCurrentURL];
    }];
}

- (void)processCurrentURL {
    if (![self ensureActiveAuthenticationOrCancel]) return;
    if (self.currentIndex >= self.pendingURLs.count) {
        self.registeredEntryIDs = [self.resultEntryIDs copy];
        [self finish:YES error:nil];
        return;
    }

    NSString *url = self.pendingURLs[self.currentIndex];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *entryKey = self.currentIndex == 0 ? kHACameraPrimaryEntryIDKey : kHACameraSecondaryEntryIDKey;
    NSString *urlKey = self.currentIndex == 0 ? kHACameraPrimaryURLKey : kHACameraSecondaryURLKey;
    NSString *revisionKey = self.currentIndex == 0
        ? kHACameraPrimaryCredentialRevisionKey : kHACameraSecondaryCredentialRevisionKey;
    NSString *frameRateKey = self.currentIndex == 0
        ? kHACameraPrimaryFramesPerSecondKey : kHACameraSecondaryFramesPerSecondKey;
    NSString *storedEntryID = [defaults stringForKey:entryKey];
    NSString *storedURL = [defaults stringForKey:urlKey];
    NSString *storedRevision = [defaults stringForKey:revisionKey];
    NSNumber *storedFramesPerSecond = [defaults objectForKey:frameRateKey];
    NSDictionary *storedEntry = [self entryWithID:storedEntryID];

    if (storedEntry && [storedURL isEqualToString:url] &&
        [storedRevision isEqualToString:self.credentialRevision] &&
        storedFramesPerSecond.integerValue == self.framesPerSecond) {
        [self acceptEntry:storedEntry[@"entry_id"] forURL:url];
        return;
    }
    if (storedEntry) {
        [self updateEntry:storedEntry[@"entry_id"] forURL:url];
        return;
    }

    // Only reuse an entry whose ID this app previously stored. Generic Camera
    // list responses do not expose enough source options to prove that a title
    // or host belongs to this stream; guessing could rename an unrelated entry.
    [self createEntryForURL:url];
}

- (NSDictionary *)entryWithID:(NSString *)entryID {
    if (!entryID.length) return nil;
    for (NSDictionary *entry in self.existingEntries) {
        if ([entry[@"entry_id"] isEqualToString:entryID]) return entry;
    }
    return nil;
}

- (void)createEntryForURL:(NSString *)url {
    if (![self ensureActiveAuthenticationOrCancel]) return;
    __weak typeof(self) weakSelf = self;
    HAAPIClient *requestClient = self.apiClient;
    [requestClient postJSONAtPath:@"config/config_entries/flow"
                              body:@{@"handler": @"generic", @"show_advanced_options": @YES}
                        completion:^(id response, NSError *error) {
        if (![weakSelf requestClientIsCurrent:requestClient]) return;
        if (error) {
            [weakSelf handleRegistrationError:[weakSelf cameraPermissionError:error]
                                requestClient:requestClient];
            return;
        }
        NSString *flowID = [response isKindOfClass:[NSDictionary class]] ? response[@"flow_id"] : nil;
        if (!flowID.length) {
            [weakSelf handleRegistrationError:[weakSelf flowError:response]
                                requestClient:requestClient];
            return;
        }
        weakSelf.activeFlowID = flowID;
        weakSelf.activeFlowIsOptionsFlow = NO;
        [weakSelf submitURL:url toFlow:flowID optionsFlow:NO existingEntryID:nil];
    }];
}

- (void)updateEntry:(NSString *)entryID forURL:(NSString *)url {
    if (![self ensureActiveAuthenticationOrCancel]) return;
    __weak typeof(self) weakSelf = self;
    HAAPIClient *requestClient = self.apiClient;
    [requestClient postJSONAtPath:@"config/config_entries/options/flow"
                              body:@{@"handler": entryID}
                        completion:^(id response, NSError *error) {
        if (![weakSelf requestClientIsCurrent:requestClient]) return;
        if (error) {
            [weakSelf handleRegistrationError:[weakSelf cameraPermissionError:error]
                                requestClient:requestClient];
            return;
        }
        NSString *flowID = [response isKindOfClass:[NSDictionary class]] ? response[@"flow_id"] : nil;
        if (!flowID.length) {
            [weakSelf handleRegistrationError:[weakSelf flowError:response]
                                requestClient:requestClient];
            return;
        }
        weakSelf.activeFlowID = flowID;
        weakSelf.activeFlowIsOptionsFlow = YES;
        [weakSelf submitURL:url toFlow:flowID optionsFlow:YES existingEntryID:entryID];
    }];
}

- (void)submitURL:(NSString *)url
            toFlow:(NSString *)flowID
       optionsFlow:(BOOL)optionsFlow
   existingEntryID:(NSString *)existingEntryID {
    if (![self ensureActiveAuthenticationOrCancel]) return;
    NSDictionary *input = [self cameraConfigurationInputForURL:url
                                                   optionsFlow:optionsFlow];
    NSString *path = [NSString stringWithFormat:@"config/config_entries/%@/flow/%@",
        optionsFlow ? @"options" : @"", flowID];
    if (!optionsFlow) path = [NSString stringWithFormat:@"config/config_entries/flow/%@", flowID];

    __weak typeof(self) weakSelf = self;
    HAAPIClient *requestClient = self.apiClient;
    [requestClient postJSONAtPath:path body:input completion:^(id response, NSError *error) {
        if (![weakSelf requestClientIsCurrent:requestClient]) return;
        if (error) {
            [weakSelf handleRegistrationError:[weakSelf cameraPermissionError:error]
                                requestClient:requestClient];
            return;
        }
        if ([response[@"type"] isEqualToString:@"create_entry"]) {
            weakSelf.activeFlowID = nil;
            NSString *entryID = existingEntryID ?: response[@"result"][@"entry_id"];
            [weakSelf acceptEntry:entryID forURL:url];
            return;
        }
        if ([response[@"step_id"] isEqualToString:@"user_confirm"] && [response[@"flow_id"] length]) {
            [weakSelf confirmFlow:response[@"flow_id"] optionsFlow:optionsFlow
                   existingEntryID:existingEntryID url:url];
            return;
        }
        [weakSelf handleRegistrationError:[weakSelf flowError:response]
                            requestClient:requestClient];
    }];
}

- (NSDictionary *)cameraConfigurationInputForURL:(NSString *)url
                                      optionsFlow:(BOOL)optionsFlow {
    NSMutableDictionary *advanced = [@{
        @"authentication": @"digest",
        @"framerate": @(self.framesPerSecond),
        @"verify_ssl": @YES,
        @"rtsp_transport": @"tcp",
    } mutableCopy];
    if (optionsFlow) {
        advanced[@"limit_refetch_to_url_change"] = @NO;
        advanced[@"use_wallclock_as_timestamps"] = @NO;
    }
    NSDictionary *input = @{
        @"stream_source": url,
        @"still_image_url": @"",
        @"username": self.username,
        @"password": self.password,
        @"advanced": advanced,
    };
    return input;
}

- (void)confirmFlow:(NSString *)flowID
         optionsFlow:(BOOL)optionsFlow
     existingEntryID:(NSString *)existingEntryID
                 url:(NSString *)url {
    if (![self ensureActiveAuthenticationOrCancel]) return;
    NSString *path = optionsFlow
        ? [NSString stringWithFormat:@"config/config_entries/options/flow/%@", flowID]
        : [NSString stringWithFormat:@"config/config_entries/flow/%@", flowID];
    __weak typeof(self) weakSelf = self;
    HAAPIClient *requestClient = self.apiClient;
    [requestClient postJSONAtPath:path body:@{@"confirmed_ok": @YES} completion:^(id response, NSError *error) {
        if (![weakSelf requestClientIsCurrent:requestClient]) return;
        if (error) {
            [weakSelf handleRegistrationError:[weakSelf cameraPermissionError:error]
                                requestClient:requestClient];
            return;
        }
        if (![response[@"type"] isEqualToString:@"create_entry"]) {
            [weakSelf handleRegistrationError:[weakSelf flowError:response]
                                requestClient:requestClient];
            return;
        }
        weakSelf.activeFlowID = nil;
        NSString *entryID = existingEntryID ?: response[@"result"][@"entry_id"];
        [weakSelf acceptEntry:entryID forURL:url];
    }];
}

- (void)acceptEntry:(NSString *)entryID forURL:(NSString *)url {
    if (![self ensureActiveAuthenticationOrCancel]) return;
    if (!entryID.length) {
        [self finish:NO error:[self error:@"Home Assistant did not return a camera config-entry ID."]];
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *entryKey = self.currentIndex == 0 ? kHACameraPrimaryEntryIDKey : kHACameraSecondaryEntryIDKey;
    NSString *urlKey = self.currentIndex == 0 ? kHACameraPrimaryURLKey : kHACameraSecondaryURLKey;
    NSString *revisionKey = self.currentIndex == 0
        ? kHACameraPrimaryCredentialRevisionKey : kHACameraSecondaryCredentialRevisionKey;
    NSString *frameRateKey = self.currentIndex == 0
        ? kHACameraPrimaryFramesPerSecondKey : kHACameraSecondaryFramesPerSecondKey;
    [defaults setObject:entryID forKey:entryKey];
    [defaults setObject:url forKey:urlKey];
    [defaults setObject:self.credentialRevision forKey:revisionKey];
    [defaults setInteger:self.framesPerSecond forKey:frameRateKey];
    [defaults synchronize];
    [self.resultEntryIDs addObject:entryID];

    NSString *role = self.pendingURLs.count > 1
        ? (self.currentIndex == 0 ? @"Front Camera" : @"Rear Camera")
        : @"Camera";
    [self renameEntry:entryID role:role];

    HALogI(@"localstream", @"Home Assistant protected camera entry is ready");
    self.currentIndex++;
    [self processCurrentURL];
}

- (void)renameEntry:(NSString *)entryID role:(NSString *)role {
    NSString *name = self.deviceName.length ? self.deviceName : @"HA Dashboard";
    NSString *title = [NSString stringWithFormat:@"%@ %@", name, role];
    [[HAConnectionManager sharedManager] sendCommand:@{
        @"type": @"config_entries/update", @"entry_id": entryID, @"title": title
    } completion:^(id result, NSError *error) {
        if (error) HALogW(@"localstream", @"Camera entry created but could not be renamed: %@", error.localizedDescription);
    }];
}

- (NSError *)flowError:(id)response {
    NSString *message = @"Home Assistant rejected the camera config flow.";
    BOOL retryable = NO;
    if ([response isKindOfClass:[NSDictionary class]]) {
        id errors = response[@"errors"];
        if (errors) {
            message = [NSString stringWithFormat:@"%@ %@", message, errors];
            NSString *lowercaseErrors = [[errors description] lowercaseString];
            retryable = [lowercaseErrors containsString:@"cannot_connect"] ||
                        [lowercaseErrors containsString:@"timed_out"] ||
                        [lowercaseErrors containsString:@"timeout"] ||
                        [lowercaseErrors containsString:@"temporarily_unavailable"];
        }
    }
    return [self error:message retryable:retryable];
}

- (NSError *)cameraPermissionError:(NSError *)error {
    if (error.code == 401 || error.code == 403) {
        return [self error:@"Camera registration requires a Home Assistant administrator token."];
    }
    return error;
}

- (BOOL)isRetryableRegistrationError:(NSError *)error {
    if (!error) return NO;
    if ([error.userInfo[HACameraRegistrationRetryableKey] boolValue]) return YES;
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case NSURLErrorTimedOut:
            case NSURLErrorCannotFindHost:
            case NSURLErrorCannotConnectToHost:
            case NSURLErrorNetworkConnectionLost:
            case NSURLErrorDNSLookupFailed:
            case NSURLErrorResourceUnavailable:
            case NSURLErrorNotConnectedToInternet:
            case NSURLErrorInternationalRoamingOff:
            case NSURLErrorCallIsActive:
            case NSURLErrorDataNotAllowed:
            case NSURLErrorRequestBodyStreamExhausted:
            case NSURLErrorCannotLoadFromNetwork:
                return YES;
            default:
                break;
        }
    }
    if ([error.domain isEqualToString:@"HAAPIClient"] &&
        (error.code == 408 || error.code == 429 || error.code >= 500)) {
        return YES;
    }
    NSError *underlyingError = error.userInfo[NSUnderlyingErrorKey];
    return underlyingError && underlyingError != error &&
           [self isRetryableRegistrationError:underlyingError];
}

- (void)discardActiveFlowUsingClient:(HAAPIClient *)requestClient {
    NSString *flowID = self.activeFlowID;
    BOOL optionsFlow = self.activeFlowIsOptionsFlow;
    self.activeFlowID = nil;
    self.activeFlowIsOptionsFlow = NO;
    if (!flowID.length || !requestClient) return;

    NSString *path = optionsFlow
        ? [NSString stringWithFormat:@"config/config_entries/options/flow/%@", flowID]
        : [NSString stringWithFormat:@"config/config_entries/flow/%@", flowID];
    [requestClient deleteJSONAtPath:path completion:^(id response, NSError *cleanupError) {
        (void)response;
        if (cleanupError && cleanupError.code != NSURLErrorCancelled && cleanupError.code != 404) {
            HALogW(@"localstream", @"Could not discard a failed Home Assistant camera config flow: %@",
                   cleanupError.localizedDescription);
        }
    }];
}

- (void)handleRegistrationError:(NSError *)error requestClient:(HAAPIClient *)requestClient {
    if (![self requestClientIsCurrent:requestClient]) return;
    NSError *registrationError = error ?: [self error:@"Home Assistant camera registration failed."];
    [self discardActiveFlowUsingClient:requestClient];
    if (![self isRetryableRegistrationError:registrationError]) {
        [self finish:NO error:registrationError];
        return;
    }

    if (self.retryAttempt < NSUIntegerMax) self.retryAttempt++;
    self.scheduledRetryDelay = HACameraRegistrationRetryDelay(self.retryAttempt);
    self.retryScheduled = YES;
    self.lastError = registrationError;
    self.existingEntries = nil;
    NSUInteger generation = self.cancellationGeneration;
    HALogW(@"localstream", @"Home Assistant camera registration will retry %lu in %.0f seconds: %@",
           (unsigned long)self.retryAttempt,
           self.scheduledRetryDelay, registrationError.localizedDescription);
    [self postChange];

    __weak typeof(self) weakSelf = self;
    self.scheduledRetryToken = self.retryScheduler(self.scheduledRetryDelay, ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.cancellationGeneration != generation) return;
        strongSelf.scheduledRetryToken = nil;
        if (![strongSelf registrationCanContinue]) {
            [strongSelf cancelRegistration];
            return;
        }
        [strongSelf beginRegistrationAttempt];
    });
}

- (NSError *)error:(NSString *)description {
    return [self error:description retryable:NO];
}

- (NSError *)error:(NSString *)description retryable:(BOOL)retryable {
    NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey: description} mutableCopy];
    if (retryable) userInfo[HACameraRegistrationRetryableKey] = @YES;
    return [NSError errorWithDomain:HACameraRegistrationErrorDomain code:1 userInfo:userInfo];
}

- (void)finish:(BOOL)success error:(NSError *)error {
    self.lastError = error;
    self.registering = NO;
    if (self.scheduledRetryToken) {
        self.retryCanceller(self.scheduledRetryToken);
        self.scheduledRetryToken = nil;
    }
    self.retryScheduled = NO;
    self.scheduledRetryDelay = 0;
    if (success) self.retryAttempt = 0;
    HAAPIClient *finishedClient = self.apiClient;
    self.apiClient = nil;
    self.pendingURLs = nil;
    self.existingEntries = nil;
    self.username = nil;
    self.password = nil;
    self.credentialRevision = nil;
    self.framesPerSecond = 0;
    self.activeAuthenticationRevision = 0;
    self.activeServerOriginToken = nil;
    self.activeFlowID = nil;
    self.activeFlowIsOptionsFlow = NO;
    void (^completion)(BOOL, NSError *) = self.completion;
    self.completion = nil;
    [finishedClient cancelAllRequests];
    [self postChange];
    if (completion) completion(success, error);
}

- (void)cancelRegistration {
    self.cancellationGeneration++;
    if (self.scheduledRetryToken) {
        self.retryCanceller(self.scheduledRetryToken);
        self.scheduledRetryToken = nil;
    }
    HAAPIClient *cancelledClient = self.apiClient;
    self.apiClient = nil;
    self.registering = NO;
    self.pendingURLs = nil;
    self.existingEntries = nil;
    self.deviceName = nil;
    self.username = nil;
    self.password = nil;
    self.credentialRevision = nil;
    self.framesPerSecond = 0;
    self.activeAuthenticationRevision = 0;
    self.activeServerOriginToken = nil;
    self.activeFlowID = nil;
    self.activeFlowIsOptionsFlow = NO;
    self.retryScheduled = NO;
    self.retryAttempt = 0;
    self.scheduledRetryDelay = 0;
    self.currentIndex = 0;
    self.resultEntryIDs = nil;
    self.completion = nil;
    [cancelledClient cancelAllRequests];
    [self postChange];
}

- (void)resetLocalRegistrationState {
    [self cancelRegistration];
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:kHALegacyCameraInsecureConsentOriginKey];
    self.registeredEntryIDs = @[];
    self.lastError = nil;
    [self postChange];
}

- (void)postChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:HACameraRegistrationDidChangeNotification object:self];
}

@end
