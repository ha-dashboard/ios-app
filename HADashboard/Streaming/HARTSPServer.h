#import <Foundation/Foundation.h>

@class HARTSPServer;

@protocol HARTSPServerDelegate <NSObject>
- (void)rtspServerDidChangeClientCount:(HARTSPServer *)server;
- (void)rtspServerNeedsVideoKeyFrame:(HARTSPServer *)server;
- (void)rtspServerNeedsMediaConfiguration:(HARTSPServer *)server;
- (void)rtspServer:(HARTSPServer *)server didFailWithError:(NSError *)error;
@end

/// Local, in-process RTSP server. It exposes H.264/AAC only while a
/// foreground local client is connected; Home Assistant is the client, not a controller.
@interface HARTSPServer : NSObject
@property (nonatomic, weak) id<HARTSPServerDelegate> delegate;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
/// Authenticated clients that have requested this stream's media. This is the
/// capture-demand count; unauthenticated TCP connections are deliberately excluded.
@property (nonatomic, readonly) NSUInteger clientCount;
/// All accepted TCP connections, including clients that have not authenticated.
@property (nonatomic, readonly) NSUInteger connectionCount;
/// Authenticated clients that have completed PLAY and are receiving media.
@property (nonatomic, readonly) NSUInteger playingClientCount;
@property (nonatomic, copy, readonly) NSString *streamURL;
@property (nonatomic, copy, readonly) NSString *authenticationUsername;
- (instancetype)initWithHost:(NSString *)host
                         port:(uint16_t)port
                     username:(NSString *)username
                     password:(NSString *)password NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (BOOL)start:(NSError **)error;
- (void)stop;
- (void)setVideoConfiguration:(NSData *)avcDecoderConfigurationRecord;
- (void)setAudioConfiguration:(NSData *)audioSpecificConfig channels:(NSUInteger)channels sampleRate:(NSUInteger)sampleRate;
- (void)clearMediaConfiguration;
- (void)sendVideoSample:(NSData *)avccNalus keyFrame:(BOOL)keyFrame timestamp:(uint32_t)milliseconds;
- (void)sendAudioSample:(NSData *)aacRaw timestamp:(uint32_t)milliseconds;
@end
