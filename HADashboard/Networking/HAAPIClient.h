#import <Foundation/Foundation.h>

typedef void (^HAAPIResponseBlock)(id _Nullable response, NSError * _Nullable error);

@interface HAAPIClient : NSObject

- (instancetype)initWithBaseURL:(NSURL *)baseURL token:(NSString *)token;

/// Creates an isolated client with endpoint-specific timeouts. The standard
/// initializer retains the app-wide 15s request / 30s resource limits; slow
/// Home Assistant config flows can opt into longer bounds without delaying
/// dashboard, state, or service requests.
- (instancetype)initWithBaseURL:(NSURL *)baseURL
                          token:(NSString *)token
         requestTimeoutInterval:(NSTimeInterval)requestTimeoutInterval
        resourceTimeoutInterval:(NSTimeInterval)resourceTimeoutInterval;

@property (nonatomic, readonly) NSTimeInterval requestTimeoutInterval;
@property (nonatomic, readonly) NSTimeInterval resourceTimeoutInterval;

/// GET /api/ — check API availability
- (void)checkAPIWithCompletion:(HAAPIResponseBlock)completion;

/// GET /api/config
- (void)getConfigWithCompletion:(HAAPIResponseBlock)completion;

/// GET /api/states — all entity states
- (void)getStatesWithCompletion:(HAAPIResponseBlock)completion;

/// GET /api/states/<entity_id>
- (void)getStateForEntityId:(NSString *)entityId completion:(HAAPIResponseBlock)completion;

/// POST /api/services/<domain>/<service>
- (void)callService:(NSString *)service
           inDomain:(NSString *)domain
           withData:(NSDictionary *)data
         completion:(HAAPIResponseBlock)completion;

/// POST /api/template — render a Home Assistant Jinja template on the server.
/// The completion response is the rendered plain-text result.
- (void)renderTemplate:(NSString *)templateString completion:(HAAPIResponseBlock)completion;

/// Authenticated JSON requests used by Home Assistant config-entry flows.
- (void)getJSONAtPath:(NSString *)path completion:(HAAPIResponseBlock)completion;
- (void)postJSONAtPath:(NSString *)path body:(NSDictionary *)body completion:(HAAPIResponseBlock)completion;
- (void)deleteJSONAtPath:(NSString *)path completion:(HAAPIResponseBlock)completion;

/// Cancels in-flight requests and invalidates this client's session. The
/// instance must not be reused afterward.
- (void)cancelAllRequests;

/// GET /api/calendars/<entity_id>?start=<ISO>&end=<ISO>
- (NSURLSessionDataTask *)getCalendarEventsForEntityId:(NSString *)entityId
                                                 start:(NSString *)startISO
                                                   end:(NSString *)endISO
                                            completion:(HAAPIResponseBlock)completion;

@end
