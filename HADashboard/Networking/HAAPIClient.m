#import "HAAPIClient.h"
#import "HAAuthManager.h"
#import "NSMutableURLRequest+HAHelpers.h"

@interface HAAPIClient ()
@property (nonatomic, strong) NSURL *baseURL;
@property (nonatomic, copy)   NSString *token;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign) BOOL isRetrying401;
@end

@implementation HAAPIClient

- (instancetype)initWithBaseURL:(NSURL *)baseURL token:(NSString *)token {
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

        _session = [NSURLSession sessionWithConfiguration:[NSMutableURLRequest ha_defaultSessionConfiguration]];
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
    NSMutableURLRequest *request = [self requestWithURL:url method:@"GET"];

    return [self executeRequestWithTask:request completion:completion];
}

- (void)POST:(NSString *)path body:(NSDictionary *)body completion:(HAAPIResponseBlock)completion {
    NSURL *url = [NSURL URLWithString:path relativeToURL:self.baseURL];
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
    request.HTTPMethod = method;
    [request ha_setAuthHeaders:self.token];
    return request;
}

- (void)executeRequest:(NSURLRequest *)request completion:(HAAPIResponseBlock)completion {
    [self executeRequestWithTask:request completion:completion];
}

- (NSURLSessionDataTask *)executeRequestWithTask:(NSURLRequest *)request completion:(HAAPIResponseBlock)completion {
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
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
                        if (newToken) {
                            self.token = newToken;
                            NSMutableURLRequest *retry = [request mutableCopy];
                            [retry setValue:[NSString stringWithFormat:@"Bearer %@", newToken]
                                forHTTPHeaderField:@"Authorization"];
                            [self executeRequest:retry completion:completion];
                        } else {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if (completion) completion(nil, refreshError);
                            });
                        }
                    }];
                    return;
                }

                NSError *authError = [NSError errorWithDomain:@"HAAPIClient"
                                                         code:401
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Unauthorized — check your access token"}];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(nil, authError);
                });
                return;
            }

            if (statusCode < 200 || statusCode >= 300) {
                NSString *msg = [NSString stringWithFormat:@"HTTP %ld", (long)statusCode];
                NSError *httpError = [NSError errorWithDomain:@"HAAPIClient"
                                                         code:statusCode
                                                     userInfo:@{NSLocalizedDescriptionKey: msg}];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(nil, httpError);
                });
                return;
            }

            id parsed = nil;
            if (data.length > 0) {
                NSError *jsonError = nil;
                parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                if (jsonError) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) completion(nil, jsonError);
                    });
                    return;
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(parsed, nil);
            });
        }];

    [task resume];
    return task;
}

@end
