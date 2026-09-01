#import "HAAPIClient.h"
#import "HAAuthManager.h"
#import "NSMutableURLRequest+HAHelpers.h"
#import "HAURLSessionRedirectGuard.h"

static NSError *HACrossOriginAPIPathError(void) {
    return [NSError errorWithDomain:@"HAAPIClient" code:-5
                           userInfo:@{NSLocalizedDescriptionKey:
                               @"The API request path resolved outside the configured Home Assistant origin."}];
}

@interface HAAPIClient ()
@property (nonatomic, strong) NSURL *baseURL;
@property (nonatomic, copy)   NSString *token;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign) BOOL isRetrying401;
@property (nonatomic, assign, getter=isCancelled) BOOL cancelled;
@property (nonatomic, assign, readwrite) NSTimeInterval requestTimeoutInterval;
@property (nonatomic, assign, readwrite) NSTimeInterval resourceTimeoutInterval;
@end

@implementation HAAPIClient

- (instancetype)initWithBaseURL:(NSURL *)baseURL token:(NSString *)token {
    return [self initWithBaseURL:baseURL token:token
          requestTimeoutInterval:15.0 resourceTimeoutInterval:30.0];
}

- (instancetype)initWithBaseURL:(NSURL *)baseURL
                          token:(NSString *)token
         requestTimeoutInterval:(NSTimeInterval)requestTimeoutInterval
        resourceTimeoutInterval:(NSTimeInterval)resourceTimeoutInterval {
    self = [super init];
    if (self) {
        // Ensure trailing slash so relative URL resolution works correctly
        // Without it, NSURL treats paths as absolute from the host root
        NSString *urlStr = [baseURL absoluteString];
        if (![urlStr hasSuffix:@"/"]) {
            _baseURL = [NSURL URLWithString:[urlStr stringByAppendingString:@"/"]];
        } else {
            _baseURL = baseURL;
        }
        _token   = [token copy];
        _requestTimeoutInterval = MAX(1.0, requestTimeoutInterval);
        _resourceTimeoutInterval = MAX(_requestTimeoutInterval, resourceTimeoutInterval);

        NSURLSessionConfiguration *configuration = [NSMutableURLRequest ha_defaultSessionConfiguration];
        configuration.timeoutIntervalForRequest = _requestTimeoutInterval;
        configuration.timeoutIntervalForResource = _resourceTimeoutInterval;
        _session = [NSURLSession sessionWithConfiguration:configuration
                                                  delegate:[HAURLSessionRedirectGuard sharedGuard]
                                             delegateQueue:nil];
    }
    return self;
}

#pragma mark - Public API

- (void)checkAPIWithCompletion:(HAAPIResponseBlock)completion {
    [self GET:@"" completion:completion];
}

- (void)getConfigWithCompletion:(HAAPIResponseBlock)completion {
    [self GET:@"config" completion:completion];
}

- (void)getStatesWithCompletion:(HAAPIResponseBlock)completion {
    [self GET:@"states" completion:completion];
}

- (void)getStateForEntityId:(NSString *)entityId completion:(HAAPIResponseBlock)completion {
    NSString *path = [NSString stringWithFormat:@"states/%@", entityId];
    [self GET:path completion:completion];
}

- (void)callService:(NSString *)service
           inDomain:(NSString *)domain
           withData:(NSDictionary *)data
         completion:(HAAPIResponseBlock)completion {
    NSString *path = [NSString stringWithFormat:@"services/%@/%@", domain, service];
    [self POST:path body:data completion:completion];
}

- (void)renderTemplate:(NSString *)templateString completion:(HAAPIResponseBlock)completion {
    if (templateString.length == 0) {
        ha_dispatchMainCompletion(completion, @"", nil);
        return;
    }
    NSURL *url = [NSURL URLWithString:@"template" relativeToURL:self.baseURL];
    NSMutableURLRequest *request = [self requestWithURL:url method:@"POST"];
    NSError *jsonError = nil;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"template": templateString}
                                                        options:0
                                                          error:&jsonError];
    if (jsonError) {
        ha_dispatchMainCompletion(completion, nil, jsonError);
        return;
    }
    [self executePlainTextRequest:request completion:completion];
}

- (void)getJSONAtPath:(NSString *)path completion:(HAAPIResponseBlock)completion {
    [self GET:path completion:completion];
}

- (void)postJSONAtPath:(NSString *)path body:(NSDictionary *)body completion:(HAAPIResponseBlock)completion {
    [self POST:path body:body completion:completion];
}

- (void)deleteJSONAtPath:(NSString *)path completion:(HAAPIResponseBlock)completion {
    NSURL *url = [NSURL URLWithString:path relativeToURL:self.baseURL];
    if (![HAURLSessionRedirectGuard URL:self.baseURL sharesOriginWithURL:url]) {
        ha_dispatchMainCompletion(completion, nil, HACrossOriginAPIPathError());
        return;
    }
    NSMutableURLRequest *request = [self requestWithURL:url method:@"DELETE"];
    [self executeRequest:request completion:completion];
}

- (void)cancelAllRequests {
    self.cancelled = YES;
    [self.session invalidateAndCancel];
}

- (NSURLSessionDataTask *)getCalendarEventsForEntityId:(NSString *)entityId
                                                 start:(NSString *)startISO
                                                   end:(NSString *)endISO
                                            completion:(HAAPIResponseBlock)completion {
    // Calendar events use /api/calendars/<entity_id> (not /api/states)
    // The baseURL ends with /api/ so we build relative to the host root
    NSString *encodedStart = [startISO stringByAddingPercentEncodingWithAllowedCharacters:
                              [NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *encodedEnd = [endISO stringByAddingPercentEncodingWithAllowedCharacters:
                            [NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *path = [NSString stringWithFormat:@"calendars/%@?start=%@&end=%@",
                      entityId, encodedStart, encodedEnd];
    return [self GETWithTask:path completion:completion];
}

#pragma mark - HTTP Methods

- (void)GET:(NSString *)path completion:(HAAPIResponseBlock)completion {
    [self GETWithTask:path completion:completion];
}

- (NSURLSessionDataTask *)GETWithTask:(NSString *)path completion:(HAAPIResponseBlock)completion {
    NSURL *url = [NSURL URLWithString:path relativeToURL:self.baseURL];
    if (![HAURLSessionRedirectGuard URL:self.baseURL sharesOriginWithURL:url]) {
        ha_dispatchMainCompletion(completion, nil, HACrossOriginAPIPathError());
        return nil;
    }
    NSMutableURLRequest *request = [self requestWithURL:url method:@"GET"];

    return [self executeRequestWithTask:request completion:completion];
}

- (void)POST:(NSString *)path body:(NSDictionary *)body completion:(HAAPIResponseBlock)completion {
    NSURL *url = [NSURL URLWithString:path relativeToURL:self.baseURL];
    if (![HAURLSessionRedirectGuard URL:self.baseURL sharesOriginWithURL:url]) {
        ha_dispatchMainCompletion(completion, nil, HACrossOriginAPIPathError());
        return;
    }
    NSMutableURLRequest *request = [self requestWithURL:url method:@"POST"];

    if (body) {
        NSError *jsonError = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
        if (jsonError) {
            if (completion) {
                completion(nil, jsonError);
            }
            return;
        }
        request.HTTPBody = jsonData;
    }

    [self executeRequest:request completion:completion];
}

#pragma mark - Request Building

- (NSMutableURLRequest *)requestWithURL:(NSURL *)url method:(NSString *)method {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = self.requestTimeoutInterval;
    request.HTTPMethod = method;
    [request ha_setAuthHeaders:self.token];
    return request;
}

- (void)executeRequest:(NSURLRequest *)request completion:(HAAPIResponseBlock)completion {
    [self executeRequestWithTask:request completion:completion];
}

- (NSURLSessionDataTask *)executeRequestWithTask:(NSURLRequest *)request completion:(HAAPIResponseBlock)completion {
    if (self.isCancelled) {
        ha_dispatchMainCompletion(completion, nil,
            [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
        return nil;
    }
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (self.isCancelled) return;
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(nil, error);
                });
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSInteger statusCode = httpResponse.statusCode;

            if (statusCode == 401) {
                if (!self.isRetrying401) {
                    self.isRetrying401 = YES;
                    [[HAAuthManager sharedManager] handleAuthFailureWithCompletion:^(NSString *newToken, NSError *refreshError) {
                        self.isRetrying401 = NO;
                        if (self.isCancelled) return;
                        if (newToken) {
                            self.token = newToken;
                            NSMutableURLRequest *retry = [request mutableCopy];
                            [retry setValue:[NSString stringWithFormat:@"Bearer %@", newToken]
                                forHTTPHeaderField:@"Authorization"];
                            [self executeRequest:retry completion:completion];
                        } else {
                            ha_dispatchMainCompletion(completion, nil, refreshError);
                        }
                    }];
                    return;
                }

                NSError *authError = [NSError errorWithDomain:@"HAAPIClient"
                                                         code:401
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Unauthorized — check your access token"}];
                ha_dispatchMainCompletion(completion, nil, authError);
                return;
            }

            if (statusCode < 200 || statusCode >= 300) {
                NSString *msg = [NSString stringWithFormat:@"HTTP %ld", (long)statusCode];
                NSError *httpError = [NSError errorWithDomain:@"HAAPIClient"
                                                         code:statusCode
                                                     userInfo:@{NSLocalizedDescriptionKey: msg}];
                ha_dispatchMainCompletion(completion, nil, httpError);
                return;
            }

            id parsed = nil;
            if (data.length > 0) {
                NSError *jsonError = nil;
                parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                if (jsonError) {
                    ha_dispatchMainCompletion(completion, nil, jsonError);
                    return;
                }
            }

            ha_dispatchMainCompletion(completion, parsed, nil);
        }];

    [task resume];
    return task;
}

/// /api/template returns UTF-8 text, unlike the JSON documents served by the
/// other API endpoints. Keep its decoding isolated so existing callers retain
/// their JSON response contract.
- (void)executePlainTextRequest:(NSURLRequest *)request completion:(HAAPIResponseBlock)completion {
    if (self.isCancelled) {
        ha_dispatchMainCompletion(completion, nil,
            [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
        return;
    }
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (self.isCancelled) return;
            if (error) {
                ha_dispatchMainCompletion(completion, nil, error);
                return;
            }

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSInteger statusCode = httpResponse.statusCode;
            if (statusCode == 401 && !self.isRetrying401) {
                self.isRetrying401 = YES;
                [[HAAuthManager sharedManager] handleAuthFailureWithCompletion:^(NSString *newToken, NSError *refreshError) {
                    self.isRetrying401 = NO;
                    if (self.isCancelled) return;
                    if (newToken) {
                        self.token = newToken;
                        NSMutableURLRequest *retry = [request mutableCopy];
                        [retry setValue:[NSString stringWithFormat:@"Bearer %@", newToken]
                            forHTTPHeaderField:@"Authorization"];
                        [self executePlainTextRequest:retry completion:completion];
                    } else {
                        ha_dispatchMainCompletion(completion, nil, refreshError);
                    }
                }];
                return;
            }
            if (statusCode < 200 || statusCode >= 300) {
                NSString *message = statusCode == 401 ? @"Unauthorized — check your access token"
                    : [NSString stringWithFormat:@"HTTP %ld", (long)statusCode];
                NSError *httpError = [NSError errorWithDomain:@"HAAPIClient"
                                                         code:statusCode
                                                     userInfo:@{NSLocalizedDescriptionKey: message}];
                ha_dispatchMainCompletion(completion, nil, httpError);
                return;
            }

            NSString *rendered = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!rendered) {
                NSError *decodeError = [NSError errorWithDomain:@"HAAPIClient" code:-4
                    userInfo:@{NSLocalizedDescriptionKey: @"Template response was not UTF-8 text"}];
                ha_dispatchMainCompletion(completion, nil, decodeError);
                return;
            }
            ha_dispatchMainCompletion(completion, rendered, nil);
        }];
    [task resume];
}

@end
