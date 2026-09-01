#import <UIKit/UIKit.h>

/// iOS 13+/Catalyst scene owner. The class is absent from the iOS 9–12 launch
/// path and delegates root-controller construction to HAAppDelegate.
API_AVAILABLE(ios(13.0))
@interface HAAppSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
