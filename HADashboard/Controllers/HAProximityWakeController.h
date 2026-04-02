#import <UIKit/UIKit.h>

/// Posted by HAThemeAwareWindow on every UITouchPhaseBegan event.
/// HAProximityWakeController observes this to reset the idle timer.
extern NSString *const HAWindowUserDidInteractNotification;

/// Implements fake-sleep/wake for kiosk mode.
///
/// When started, a 60-second idle timer runs. If no touch occurs before it
/// fires, the screen is dimmed to black (brightness → 0 + opaque overlay).
/// Any subsequent touch instantly restores brightness and removes the overlay.
/// Stops cleanly on app resign-active and restores state on become-active.
@interface HAProximityWakeController : NSObject

- (instancetype)initWithWindow:(UIWindow *)window NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Starts the idle timer. Call when kiosk + proximity wake are both enabled.
- (void)start;

/// Stops the idle timer and immediately restores the screen if sleeping.
- (void)stop;

@end
