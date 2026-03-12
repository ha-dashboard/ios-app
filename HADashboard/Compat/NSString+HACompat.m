#import "NSString+HACompat.h"

@implementation NSString (HACompat)

- (UIFont *)ha_fontFromAttributes:(NSDictionary *)attrs {
    UIFont *font = attrs[NSFontAttributeName];
    return font ?: [UIFont systemFontOfSize:14];
}

- (CGSize)ha_sizeWithAttributes:(NSDictionary *)attrs {
    if ([self respondsToSelector:@selector(sizeWithAttributes:)]) {
        return [self sizeWithAttributes:attrs];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [self sizeWithFont:[self ha_fontFromAttributes:attrs]];
#pragma clang diagnostic pop
}

- (void)ha_drawAtPoint:(CGPoint)point withAttributes:(NSDictionary *)attrs {
    if ([self respondsToSelector:@selector(drawAtPoint:withAttributes:)]) {
        [self drawAtPoint:point withAttributes:attrs];
        return;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIFont *font = [self ha_fontFromAttributes:attrs];
    UIColor *color = attrs[NSForegroundColorAttributeName];
    if (color) [color set];
    [self drawAtPoint:point withFont:font];
#pragma clang diagnostic pop
}

- (void)ha_drawInRect:(CGRect)rect withAttributes:(NSDictionary *)attrs {
    if ([self respondsToSelector:@selector(drawInRect:withAttributes:)]) {
        [self drawInRect:rect withAttributes:attrs];
        return;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIFont *font = [self ha_fontFromAttributes:attrs];
    UIColor *color = attrs[NSForegroundColorAttributeName];
    if (color) [color set];
    [self drawInRect:rect withFont:font lineBreakMode:NSLineBreakByTruncatingTail];
#pragma clang diagnostic pop
}

- (CGRect)ha_boundingRectWithSize:(CGSize)size
                          options:(NSStringDrawingOptions)options
                       attributes:(NSDictionary *)attrs
                          context:(id)context {
    if ([self respondsToSelector:@selector(boundingRectWithSize:options:attributes:context:)]) {
        return [self boundingRectWithSize:size options:options attributes:attrs context:context];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIFont *font = [self ha_fontFromAttributes:attrs];
    CGSize result = [self sizeWithFont:font constrainedToSize:size lineBreakMode:NSLineBreakByWordWrapping];
    return CGRectMake(0, 0, result.width, result.height);
#pragma clang diagnostic pop
}

@end
