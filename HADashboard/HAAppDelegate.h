#import <UIKit/UIKit.h>

@interface HAAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

/// Used by the iOS 13+/Catalyst scene delegate. iOS 9–12 continue to create
/// the same window directly from application:didFinishLaunchingWithOptions:.
- (void)configureInitialInterfaceInWindow:(UIWindow *)window;

/// Scene-based apps do not deliver their foreground transition through the
/// application delegate. Both lifecycle entry points use this shared method.
- (void)resumeForegroundServices;
- (void)suspendForegroundServices;

@end
