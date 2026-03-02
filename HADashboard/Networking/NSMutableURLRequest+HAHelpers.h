#import <Foundation/Foundation.h>

/// Convenience methods for building Home Assistant API requests.
@interface NSMutableURLRequest (HAHelpers)

/// Set Bearer token Authorization and application/json Content-Type headers.
- (void)ha_setAuthHeaders:(NSString *)token;

/// Create a default NSURLSessionConfiguration with HA standard timeouts (15s request, 30s resource).
+ (NSURLSessionConfiguration *)ha_defaultSessionConfiguration;

@end
