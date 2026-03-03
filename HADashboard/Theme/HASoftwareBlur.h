#import <UIKit/UIKit.h>

/// Provides vImage-based Gaussian blur for devices where UIVisualEffectView
/// renders opaque (pre-A7 GPUs). Uses Accelerate framework with 4× downsampling
/// for ~1ms blur time even on A5 chips.
@interface HASoftwareBlur : NSObject

/// Blur a UIImage using a 3-pass vImage box blur (approximates Gaussian).
/// @param image Source image
/// @param radius Blur radius in points (20 recommended for frosted-glass)
/// @return Blurred image, or original if blur fails
+ (UIImage *)blurImage:(UIImage *)image radius:(CGFloat)radius;

@end
