#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Stateless NSURLSession delegate that permits redirects only when scheme,
/// host, and effective port match the task's original request URL.
@interface HAURLSessionRedirectGuard : NSObject <NSURLSessionTaskDelegate>

@property (class, nonatomic, readonly) HAURLSessionRedirectGuard *sharedGuard;

/// Returns YES when both URLs have the same scheme, host, and effective port.
+ (BOOL)URL:(NSURL *)left sharesOriginWithURL:(NSURL *)right;

@end

NS_ASSUME_NONNULL_END
