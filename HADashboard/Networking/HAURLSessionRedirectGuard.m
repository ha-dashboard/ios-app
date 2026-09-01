#import "HAURLSessionRedirectGuard.h"

static NSNumber *HAEffectiveURLPort(NSURL *URL) {
    if (URL.port) return URL.port;
    NSString *scheme = URL.scheme.lowercaseString;
    if ([scheme isEqualToString:@"https"]) return @443;
    if ([scheme isEqualToString:@"http"]) return @80;
    return nil;
}

@implementation HAURLSessionRedirectGuard

+ (HAURLSessionRedirectGuard *)sharedGuard {
    static HAURLSessionRedirectGuard *guard;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ guard = [[self alloc] init]; });
    return guard;
}

+ (BOOL)URL:(NSURL *)left sharesOriginWithURL:(NSURL *)right {
    if (!left || !right) return NO;
    NSNumber *leftPort = HAEffectiveURLPort(left);
    NSNumber *rightPort = HAEffectiveURLPort(right);
    return leftPort && rightPort &&
           [left.scheme.lowercaseString isEqualToString:right.scheme.lowercaseString] &&
           [left.host.lowercaseString isEqualToString:right.host.lowercaseString] &&
           [leftPort isEqualToNumber:rightPort];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    (void)session;
    (void)response;
    completionHandler([[self class] URL:task.originalRequest.URL
                          sharesOriginWithURL:request.URL] ? request : nil);
}

@end
