#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

/// In-tree linear-PCM-to-AAC-LC encoder. AVCaptureAudioDataOutput provides
/// PCM on iOS, so this avoids depending on an unavailable capture-output
/// compression setting or a Swift publisher library.
@interface HAAACEncoder : NSObject

@property (nonatomic, copy, readonly) NSData *audioSpecificConfig;
@property (nonatomic, readonly) NSUInteger channelCount;

- (instancetype)initWithInputFormat:(CMAudioFormatDescriptionRef)inputFormat error:(NSError **)error;
- (NSData *)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer error:(NSError **)error;

@end
