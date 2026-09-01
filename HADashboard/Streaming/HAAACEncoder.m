#import "HAAACEncoder.h"
#import <AudioToolbox/AudioToolbox.h>
#include <math.h>

static NSString *const HAAACEncoderErrorDomain = @"HAAACEncoderErrorDomain";
// AudioConverter treats zero packets plus noErr as permanent end-of-stream.
// Live capture is only temporarily out of input at the end of each callback,
// so return a private status instead and keep the converter reusable.
static const OSStatus HAAACEncoderNoInputAvailable = -77701;

@interface HAAACEncoder ()
@property (nonatomic, assign) AudioConverterRef converter;
@property (nonatomic, assign) UInt32 maximumOutputPacketSize;
@property (nonatomic, assign) AudioBufferList *inputBufferList;
@property (nonatomic, assign) UInt32 inputPacketCount;
@property (nonatomic, assign) BOOL consumedInput;
@property (nonatomic, assign) UInt32 inputBytesPerFrame;
@property (nonatomic, assign) UInt32 inputFramesPerPacket;
@property (nonatomic, assign) UInt32 framesPerAACPacket;
@property (nonatomic, strong) NSMutableData *pendingPCM;
@property (nonatomic, copy, readwrite) NSData *audioSpecificConfig;
@property (nonatomic, assign, readwrite) NSUInteger channelCount;
@end

static OSStatus HAAACEncoderInputProc(AudioConverterRef inAudioConverter,
                                      UInt32 *ioNumberDataPackets,
                                      AudioBufferList *ioData,
                                      AudioStreamPacketDescription **outDataPacketDescription,
                                      void *inUserData) {
    (void)inAudioConverter;
    HAAACEncoder *encoder = (__bridge HAAACEncoder *)inUserData;
    if (encoder.consumedInput || !encoder.inputBufferList) {
        *ioNumberDataPackets = 0;
        if (ioData) {
            for (UInt32 index = 0; index < ioData->mNumberBuffers; index++) {
                ioData->mBuffers[index].mData = NULL;
                ioData->mBuffers[index].mDataByteSize = 0;
            }
        }
        return HAAACEncoderNoInputAvailable;
    }
    *ioNumberDataPackets = encoder.inputPacketCount;
    *ioData = *encoder.inputBufferList;
    if (outDataPacketDescription) *outDataPacketDescription = NULL;
    encoder.consumedInput = YES;
    return noErr;
}

@implementation HAAACEncoder

- (instancetype)initWithInputFormat:(CMAudioFormatDescriptionRef)inputFormat error:(NSError **)error {
    const AudioStreamBasicDescription *input = CMAudioFormatDescriptionGetStreamBasicDescription(inputFormat);
    if (!input || input->mFormatID != kAudioFormatLinearPCM || input->mChannelsPerFrame == 0 || input->mChannelsPerFrame > 2) {
        if (error) *error = [self errorWithDescription:@"The microphone format cannot be encoded as AAC-LC."];
        return nil;
    }
    self = [super init];
    if (self) {
        AudioStreamBasicDescription output = {0};
        output.mSampleRate = input->mSampleRate;
        output.mFormatID = kAudioFormatMPEG4AAC;
        output.mChannelsPerFrame = input->mChannelsPerFrame;
        UInt32 outputSize = sizeof(output);
        OSStatus formatStatus = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &outputSize, &output);
        OSStatus converterStatus = formatStatus == noErr ? AudioConverterNew(input, &output, &_converter) : formatStatus;
        if (converterStatus != noErr || !_converter) {
            if (error) *error = [self errorWithDescription:@"The device could not create an AAC-LC microphone encoder."];
            return nil;
        }
        if (input->mBytesPerFrame == 0 || input->mFramesPerPacket == 0 || output.mFramesPerPacket == 0) {
            AudioConverterDispose(_converter);
            _converter = NULL;
            if (error) *error = [self errorWithDescription:@"The microphone packet format is unsupported by the AAC publisher."];
            return nil;
        }
        UInt32 packetSizeLength = sizeof(_maximumOutputPacketSize);
        AudioConverterGetProperty(_converter, kAudioConverterPropertyMaximumOutputPacketSize, &packetSizeLength, &_maximumOutputPacketSize);
        if (_maximumOutputPacketSize == 0) _maximumOutputPacketSize = 8192;
        NSInteger frequencyIndex = [self frequencyIndexForSampleRate:output.mSampleRate];
        if (frequencyIndex < 0) {
            AudioConverterDispose(_converter);
            _converter = NULL;
            if (error) *error = [self errorWithDescription:@"The microphone sample rate is unsupported by the AAC publisher."];
            return nil;
        }
        _channelCount = output.mChannelsPerFrame;
        _inputBytesPerFrame = input->mBytesPerFrame;
        _inputFramesPerPacket = input->mFramesPerPacket;
        _framesPerAACPacket = output.mFramesPerPacket;
        _pendingPCM = [NSMutableData data];
        uint16_t asc = (uint16_t)((2 << 11) | (frequencyIndex << 7) | (_channelCount << 3));
        uint8_t ascBytes[2] = { (uint8_t)(asc >> 8), (uint8_t)asc };
        _audioSpecificConfig = [NSData dataWithBytes:ascBytes length:sizeof(ascBytes)];
    }
    return self;
}

- (void)dealloc {
    if (_converter) AudioConverterDispose(_converter);
}

- (NSData *)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer error:(NSError **)error {
    if (!_converter || !sampleBuffer) return nil;
    size_t listSize = 0;
    OSStatus sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, &listSize, NULL, 0,
        kCFAllocatorDefault, kCFAllocatorDefault, 0, NULL);
    if (sizeStatus != noErr || listSize == 0) {
        if (error) *error = [self errorWithDescription:@"The microphone audio buffer could not be read."];
        return nil;
    }
    AudioBufferList *list = malloc(listSize);
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus listStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, &listSize, list, listSize,
        kCFAllocatorDefault, kCFAllocatorDefault, 0, &blockBuffer);
    if (listStatus != noErr) {
        free(list);
        if (error) *error = [self errorWithDescription:@"The microphone audio buffer could not be prepared."];
        return nil;
    }
    if (list->mNumberBuffers != 1 || !list->mBuffers[0].mData || list->mBuffers[0].mDataByteSize == 0) {
        if (blockBuffer) CFRelease(blockBuffer);
        free(list);
        if (error) *error = [self errorWithDescription:@"The microphone format cannot be packetized as AAC-LC."];
        return nil;
    }
    [self.pendingPCM appendBytes:list->mBuffers[0].mData length:list->mBuffers[0].mDataByteSize];
    if (blockBuffer) CFRelease(blockBuffer);
    free(list);

    UInt32 requiredBytes = self.framesPerAACPacket * self.inputBytesPerFrame;
    if (requiredBytes == 0 || self.pendingPCM.length < requiredBytes) return nil;

    AudioBufferList input = {0};
    input.mNumberBuffers = 1;
    input.mBuffers[0].mNumberChannels = (UInt32)self.channelCount;
    input.mBuffers[0].mDataByteSize = requiredBytes;
    input.mBuffers[0].mData = (void *)self.pendingPCM.bytes;
    self.inputBufferList = &input;
    self.inputPacketCount = self.framesPerAACPacket / self.inputFramesPerPacket;
    self.consumedInput = NO;

    uint8_t *outputBytes = malloc(self.maximumOutputPacketSize);
    AudioBufferList output = {0};
    output.mNumberBuffers = 1;
    output.mBuffers[0].mNumberChannels = (UInt32)self.channelCount;
    output.mBuffers[0].mDataByteSize = self.maximumOutputPacketSize;
    output.mBuffers[0].mData = outputBytes;
    UInt32 outputPackets = 1;
    AudioStreamPacketDescription packetDescription = {0};
    OSStatus encodeStatus = AudioConverterFillComplexBuffer(self.converter, HAAACEncoderInputProc, (__bridge void *)self,
        &outputPackets, &output, &packetDescription);

    self.inputBufferList = NULL;
    if (self.consumedInput) [self.pendingPCM replaceBytesInRange:NSMakeRange(0, requiredBytes) withBytes:NULL length:0];
    if (encodeStatus == HAAACEncoderNoInputAvailable &&
        packetDescription.mDataByteSize == 0) {
        outputPackets = 0;
        output.mBuffers[0].mDataByteSize = 0;
    } else if (encodeStatus != noErr && encodeStatus != HAAACEncoderNoInputAvailable) {
        free(outputBytes);
        if (error) *error = [self errorWithDescription:@"The AAC microphone encoder failed."];
        return nil;
    }
    UInt32 offset = outputPackets > 0 ? packetDescription.mStartOffset : 0;
    UInt32 length = outputPackets > 0 ? packetDescription.mDataByteSize : 0;
    if (length == 0 && outputPackets > 0) length = output.mBuffers[0].mDataByteSize;
    if (offset > output.mBuffers[0].mDataByteSize || length > output.mBuffers[0].mDataByteSize - offset) {
        free(outputBytes);
        if (error) *error = [self errorWithDescription:@"The AAC microphone encoder produced an invalid packet."];
        return nil;
    }
    NSData *encoded = outputPackets > 0 && length > 0
        ? [NSData dataWithBytes:outputBytes + offset length:length] : nil;
    free(outputBytes);
    return encoded;
}

- (NSInteger)frequencyIndexForSampleRate:(Float64)sampleRate {
    static const NSInteger frequencies[] = { 96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000 };
    for (NSInteger index = 0; index < 12; index++) {
        if (fabs(sampleRate - frequencies[index]) < 1.0) return index;
    }
    return -1;
}

- (NSError *)errorWithDescription:(NSString *)description {
    return [NSError errorWithDomain:HAAACEncoderErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: description}];
}

@end
