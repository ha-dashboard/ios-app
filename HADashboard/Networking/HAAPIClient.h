#import <Foundation/Foundation.h>

typedef void (^HAAPIResponseBlock)(id _Nullable response, NSError * _Nullable error);

@interface HAAPIClient : NSObject

- (instancetype)initWithBaseURL:(NSURL *)baseURL token:(NSString *)token;

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

/// GET /api/calendars/<entity_id>?start=<ISO>&end=<ISO>
- (NSURLSessionDataTask *)getCalendarEventsForEntityId:(NSString *)entityId
                                                 start:(NSString *)startISO
                                                   end:(NSString *)endISO
                                            completion:(HAAPIResponseBlock)completion;

@end
