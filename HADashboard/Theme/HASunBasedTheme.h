#import <Foundation/Foundation.h>

/// On iOS 9-12 (no system dark mode), watches the Home Assistant `sun.sun`
/// entity to switch between light and dark appearance automatically.
/// Uses next_rising / next_setting attributes — no location permission needed.
///
/// Does nothing on iOS 13+ (system handles appearance) or when theme is not Auto.
@interface HASunBasedTheme : NSObject

+ (instancetype)sharedInstance;

/// Call after connection is established and entities are loaded.
/// Evaluates the current sun state and schedules the next transition.
- (void)start;

/// Call when disconnecting or when the user changes away from Auto mode.
- (void)stop;

/// Returns YES when the sun entity says it's below the horizon (night time).
/// Falls back to NO (light) if the entity is unavailable.
@property (nonatomic, readonly) BOOL isSunBelowHorizon;

@end
