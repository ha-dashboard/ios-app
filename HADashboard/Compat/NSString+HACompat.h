#import <UIKit/UIKit.h>

/// iOS 5-safe text measurement and drawing.
/// iOS 7+ uses attributed string APIs (sizeWithAttributes:, drawAtPoint:withAttributes:).
/// iOS 5-6 uses the deprecated font-based APIs (sizeWithFont:, drawAtPoint:withFont:).
@interface NSString (HACompat)

/// Equivalent to sizeWithAttributes: (iOS 7+), falls back to sizeWithFont: (iOS 5-6).
- (CGSize)ha_sizeWithAttributes:(NSDictionary *)attrs;

/// Equivalent to drawAtPoint:withAttributes: (iOS 7+), falls back to drawAtPoint:withFont:.
- (void)ha_drawAtPoint:(CGPoint)point withAttributes:(NSDictionary *)attrs;

/// Equivalent to drawInRect:withAttributes: (iOS 7+), falls back to drawInRect:withFont:lineBreakMode:.
- (void)ha_drawInRect:(CGRect)rect withAttributes:(NSDictionary *)attrs;

/// Equivalent to boundingRectWithSize:options:attributes:context: (iOS 7+),
/// falls back to sizeWithFont:constrainedToSize:lineBreakMode:.
- (CGRect)ha_boundingRectWithSize:(CGSize)size
                          options:(NSStringDrawingOptions)options
                       attributes:(NSDictionary *)attrs
                          context:(id)context;

@end
