#import "HAOAuthClient.h"
#import "HAAuthManager.h"

static NSString *const kClientId = @"https://hadashboard.local/";
static NSString *const kRedirectURI = @"https://hadashboard.local/";

@interface HAOAuthClient ()
@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation HAOAuthClient

- (instancetype)initWithServerURL:(NSString *)serverURL {
    self = [super init];
    if (self) {
        _serverURL = [[HAAuthManager normalizedURL:serverURL] copy];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 15.0;
        config.timeoutIntervalForResource = 30.0;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

#pragma mark - Login Flow

- (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
               completion:(void (^)(NSString *authCode, NSError *error))completion {
    // Step 1: Initiate login flow
    NSURL *flowURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/auth/login_flow", self.serverURL]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:flowURL];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"client_id": kClientId,
        @"handler": @[@"homeassistant", [NSNull null]],
        @"redirect_uri": kRedirectURI,
    };
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
                return;
            }

            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            NSDictionary *result = [self parseJSONData:data];

            if (httpResp.statusCode != 200 || !result) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [self errorWithMessage:@"Failed to start login flow" code:httpResp.statusCode]);
                });
                return;
            }

            NSString *flowId = result[@"flow_id"];
            if (!flowId) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [self errorWithMessage:@"No flow_id in response" code:0]);
                });
                return;
            }

            // Step 2: Submit credentials
            [weakSelf submitCredentials:username password:password flowId:flowId completion:completion];
        }];
    [task resume];
}

- (void)submitCredentials:(NSString *)username
                 password:(NSString *)password
                   flowId:(NSString *)flowId
               completion:(void (^)(NSString *authCode, NSError *error))completion {
    NSURL *submitURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/auth/login_flow/%@", self.serverURL, flowId]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:submitURL];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"username": username,
        @"password": password,
        @"client_id": kClientId,
    };
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
                return;
            }

            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            NSDictionary *result = [self parseJSONData:data];

            if (httpResp.statusCode != 200 || !result) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [self errorWithMessage:@"Login failed — check username/password" code:httpResp.statusCode]);
                });
                return;
            }

            // Check for errors in the flow response
            NSString *stepType = result[@"type"];
            if ([stepType isEqualToString:@"form"]) {
                // Still on a form step — means credentials were wrong
                NSArray *errors = result[@"errors"];
                NSString *errMsg = @"Invalid username or password";
                if ([errors isKindOfClass:[NSDictionary class]]) {
                    NSString *baseErr = ((NSDictionary *)errors)[@"base"];
                    if (baseErr) errMsg = baseErr;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [self errorWithMessage:errMsg code:401]);
                });
                return;
            }

            if ([stepType isEqualToString:@"create_entry"]) {
                // Success — extract the auth code from the result
                NSString *authCode = result[@"result"];
                if (authCode) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(authCode, nil);
                    });
                    return;
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [self errorWithMessage:@"Unexpected login response" code:0]);
            });
        }];
    [task resume];
}

#pragma mark - Token Exchange

- (void)exchangeAuthCode:(NSString *)authCode
               completion:(void (^)(NSDictionary *tokenResponse, NSError *error))completion {
    [self postTokenEndpointWithBody:[NSString stringWithFormat:
        @"grant_type=authorization_code&code=%@&client_id=%@",
        [self urlEncode:authCode], [self urlEncode:kClientId]]
                        completion:completion];
}

- (void)refreshWithToken:(NSString *)refreshToken
              completion:(void (^)(NSDictionary *tokenResponse, NSError *error))completion {
    [self postTokenEndpointWithBody:[NSString stringWithFormat:
        @"grant_type=refresh_token&refresh_token=%@&client_id=%@",
        [self urlEncode:refreshToken], [self urlEncode:kClientId]]
                        completion:completion];
}

#pragma mark - Auth Providers

- (void)fetchAuthProviders:(void (^)(NSArray *providers, NSError *error))completion {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/auth/providers", self.serverURL]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
                return;
            }

            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (httpResp.statusCode != 200 || !data) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [self errorWithMessage:@"Failed to fetch auth providers" code:httpResp.statusCode]);
                });
                return;
            }

            id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            // Response is {"providers": [...], ...} — extract the array
            NSArray *providers = nil;
            if ([parsed isKindOfClass:[NSDictionary class]]) {
                providers = parsed[@"providers"];
            } else if ([parsed isKindOfClass:[NSArray class]]) {
                providers = parsed;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(providers, providers ? nil : [self errorWithMessage:@"Invalid providers response" code:0]);
            });
        }];
    [task resume];
}

#pragma mark - Trusted Network Login

- (void)loginWithTrustedNetworkUser:(NSString *)userId
                             flowId:(NSString *)flowId
                         completion:(void (^)(NSString *authCode,
                                              NSDictionary *usersOrNil,
                                              NSString *flowIdOrNil,
                                              NSError *error))completion {
    if (flowId && userId) {
        // Step 2: Complete the flow with the selected user
        [self submitTrustedNetworkUser:userId flowId:flowId completion:completion];
    } else {
        // Step 1: Start the login flow to discover available users
        [self startTrustedNetworkFlowWithCompletion:completion];
    }
}

- (void)startTrustedNetworkFlowWithCompletion:(void (^)(NSString *, NSDictionary *, NSString *, NSError *))completion {
    NSURL *flowURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/auth/login_flow", self.serverURL]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:flowURL];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"client_id": kClientId,
        @"handler": @[@"trusted_networks", [NSNull null]],
        @"redirect_uri": kRedirectURI,
    };
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, nil, error); });
                return;
            }

            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            NSDictionary *result = [self parseJSONData:data];

            if (httpResp.statusCode != 200 || !result) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, nil, nil,
                        [self errorWithMessage:@"Failed to start trusted network login" code:httpResp.statusCode]);
                });
                return;
            }

            NSString *stepType = result[@"type"];
            NSString *resultFlowId = result[@"flow_id"];

            // If the flow immediately completes (single user + bypass), we get create_entry
            if ([stepType isEqualToString:@"create_entry"]) {
                NSString *authCode = result[@"result"];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(authCode, nil, nil, authCode ? nil :
                        [self errorWithMessage:@"No auth code in response" code:0]);
                });
                return;
            }

            // Otherwise we get a form asking to select a user
            if ([stepType isEqualToString:@"form"]) {
                NSDictionary *users = [self extractUsersFromFlowResult:result];
                if (users.count == 0) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, nil, nil,
                            [self errorWithMessage:@"No users available for trusted network login" code:0]);
                    });
                    return;
                }

                // Single user: auto-select
                if (users.count == 1) {
                    NSString *onlyUserId = users.allKeys.firstObject;
                    [self submitTrustedNetworkUser:onlyUserId flowId:resultFlowId completion:completion];
                    return;
                }

                // Multiple users: return the list for the UI to present
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, users, resultFlowId, nil);
                });
                return;
            }

            if ([stepType isEqualToString:@"abort"]) {
                NSString *reason = [result[@"reason"] isKindOfClass:[NSString class]] ? result[@"reason"] : @"Login aborted";
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, nil, nil, [self errorWithMessage:reason code:403]);
                });
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, nil, nil, [self errorWithMessage:@"Unexpected login response" code:0]);
            });
        }];
    [task resume];
}

- (void)submitTrustedNetworkUser:(NSString *)userId
                          flowId:(NSString *)flowId
                      completion:(void (^)(NSString *, NSDictionary *, NSString *, NSError *))completion {
    NSURL *submitURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/auth/login_flow/%@", self.serverURL, flowId]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:submitURL];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *body = @{
        @"user": userId,
        @"client_id": kClientId,
    };
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, nil, error); });
                return;
            }

            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            NSDictionary *result = [self parseJSONData:data];

            if (httpResp.statusCode != 200 || !result) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, nil, nil,
                        [self errorWithMessage:@"Failed to complete trusted network login" code:httpResp.statusCode]);
                });
                return;
            }

            NSString *stepType = result[@"type"];
            if ([stepType isEqualToString:@"create_entry"]) {
                NSString *authCode = result[@"result"];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(authCode, nil, nil, authCode ? nil :
                        [self errorWithMessage:@"No auth code in response" code:0]);
                });
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, nil, nil, [self errorWithMessage:@"Unexpected response after user selection" code:0]);
            });
        }];
    [task resume];
}

/// Extract user ID → display name mapping from the login flow form response.
/// The data_schema contains a vol.In() constraint with the allowed user values.
- (NSDictionary *)extractUsersFromFlowResult:(NSDictionary *)result {
    NSMutableDictionary *users = [NSMutableDictionary dictionary];

    // The HA login flow returns data_schema as an array of field descriptors.
    // For trusted_networks, there's a single "user" field.
    // The allowed values are in the field's options/enum.
    NSArray *schema = result[@"data_schema"];
    if (![schema isKindOfClass:[NSArray class]]) return users;

    for (NSDictionary *field in schema) {
        if (![field isKindOfClass:[NSDictionary class]]) continue;
        if (![field[@"name"] isKindOfClass:[NSString class]] || ![field[@"name"] isEqualToString:@"user"]) continue;

        // HA returns the allowed values as an array of [value, label] pairs
        // in the "options" key, or as a flat list in "values"
        NSArray *options = field[@"options"];
        if ([options isKindOfClass:[NSArray class]]) {
            for (NSArray *option in options) {
                if ([option isKindOfClass:[NSArray class]] && option.count >= 2) {
                    users[option[0]] = option[1]; // [user_id, display_name]
                }
            }
        }

        // Some HA versions may use a different format
        if (users.count == 0) {
            NSDictionary *valuesDict = field[@"values"];
            if ([valuesDict isKindOfClass:[NSDictionary class]]) {
                [users addEntriesFromDictionary:valuesDict];
            }
        }

        break;
    }

    return users;
}

#pragma mark - Internal

- (void)postTokenEndpointWithBody:(NSString *)formBody
                       completion:(void (^)(NSDictionary *tokenResponse, NSError *error))completion {
    NSURL *tokenURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/auth/token", self.serverURL]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:tokenURL];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [formBody dataUsingEncoding:NSUTF8StringEncoding];

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error);
                });
                return;
            }

            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            NSDictionary *result = [self parseJSONData:data];

            if (httpResp.statusCode != 200 || !result) {
                NSString *errMsg = [result[@"error_description"] isKindOfClass:[NSString class]] ? result[@"error_description"] : @"Token exchange failed";
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, [self errorWithMessage:errMsg code:httpResp.statusCode]);
                });
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                completion(result, nil);
            });
        }];
    [task resume];
}

- (NSDictionary *)parseJSONData:(NSData *)data {
    if (!data || data.length == 0) return nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [parsed isKindOfClass:[NSDictionary class]] ? parsed : nil;
}

- (NSString *)urlEncode:(NSString *)string {
    return [string stringByAddingPercentEncodingWithAllowedCharacters:
        [NSCharacterSet URLQueryAllowedCharacterSet]];
}

- (NSError *)errorWithMessage:(NSString *)message code:(NSInteger)code {
    return [NSError errorWithDomain:@"HAOAuthClient"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end
