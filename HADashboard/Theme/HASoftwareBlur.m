#import "HASoftwareBlur.h"
#import <Accelerate/Accelerate.h>

@implementation HASoftwareBlur

+ (UIImage *)blurImage:(UIImage *)image radius:(CGFloat)radius {
    if (!image) return nil;

    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return image;

    // Downsample 4× before blurring — blur hides the scaling artifacts
    // and this makes vImage ~16× faster (processing 1/16th the pixels).
    CGFloat scale = 0.25;
    size_t width = (size_t)(CGImageGetWidth(cgImage) * scale);
    size_t height = (size_t)(CGImageGetHeight(cgImage) * scale);
    if (width == 0 || height == 0) return image;

    size_t bytesPerRow = width * 4;
    // Align to 16 bytes for NEON SIMD
    bytesPerRow = (bytesPerRow + 15) & ~15;

    // Create downsampled buffer
    void *srcData = calloc(bytesPerRow * height, 1);
    if (!srcData) return image;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(srcData, width, height, 8, bytesPerRow,
        colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!ctx) { free(srcData); return image; }

    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(ctx);

    // vImage buffers
    vImage_Buffer src = { srcData, height, width, bytesPerRow };
    void *dstData = calloc(bytesPerRow * height, 1);
    if (!dstData) { free(srcData); return image; }
    vImage_Buffer dst = { dstData, height, width, bytesPerRow };

    // Kernel size from radius (adjusted for downscale)
    uint32_t kernelSize = (uint32_t)(radius * scale * 2.0) | 1; // must be odd
    if (kernelSize < 3) kernelSize = 3;

    // 3-pass box blur approximates Gaussian
    vImageBoxConvolve_ARGB8888(&src, &dst, NULL, 0, 0, kernelSize, kernelSize, NULL, kvImageEdgeExtend);
    vImageBoxConvolve_ARGB8888(&dst, &src, NULL, 0, 0, kernelSize, kernelSize, NULL, kvImageEdgeExtend);
    vImageBoxConvolve_ARGB8888(&src, &dst, NULL, 0, 0, kernelSize, kernelSize, NULL, kvImageEdgeExtend);

    // Create output image from blurred buffer
    CGColorSpaceRef outCS = CGColorSpaceCreateDeviceRGB();
    CGContextRef outCtx = CGBitmapContextCreate(dst.data, width, height, 8, bytesPerRow,
        outCS, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(outCS);

    UIImage *result = image;
    if (outCtx) {
        CGImageRef blurredCG = CGBitmapContextCreateImage(outCtx);
        if (blurredCG) {
            result = [UIImage imageWithCGImage:blurredCG];
            CGImageRelease(blurredCG);
        }
        CGContextRelease(outCtx);
    }

    free(srcData);
    free(dstData);
    return result;
}

@end
