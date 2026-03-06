#import <Foundation/Foundation.h>

/// Convenience methods for building Home Assistant API requests.
@interface NSMutableURLRequest (HAHelpers)

/// Set Bearer token Authorization and application/json Content-Type headers.
- (void)ha_setAuthHeaders:(NSString *)token;

/// Create a default NSURLSessionConfiguration with HA standard timeouts (15s request, 30s resource).
+ (NSURLSessionConfiguration *)ha_defaultSessionConfiguration;

/// Create a POST request with JSON body and Content-Type header.
+ (NSMutableURLRequest *)ha_postRequestWithURL:(NSURL *)url jsonBody:(NSDictionary *)body;

@end

/// Dispatch a two-argument completion block on the main queue.  No-op if block is nil.
static inline void ha_dispatchMainCompletion(void (^block)(id, NSError *), id result, NSError *error) {
    if (!block) return;
    dispatch_async(dispatch_get_main_queue(), ^{ block(result, error); });
}
