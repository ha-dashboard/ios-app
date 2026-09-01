#import <XCTest/XCTest.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreMedia/CoreMedia.h>
#import <arpa/inet.h>
#import <errno.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>
#import "HAStreamingManager.h"
#import "HAAACEncoder.h"
#import "HARTSPServer.h"
#import "HAAPIClient.h"
#import "HACameraRegistrationManager.h"
#import "HAURLSessionRedirectGuard.h"

static const NSTimeInterval HARTSPTestSocketTimeout = 3.0;

static CMSampleBufferRef HAStreamingCreateMonoPCMBuffer(UInt32 frameCount) {
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = 48000;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    format.mBytesPerPacket = sizeof(int16_t);
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = sizeof(int16_t);
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 16;

    CMAudioFormatDescriptionRef formatDescription = NULL;
    if (CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &format, 0, NULL, 0, NULL, NULL,
                                       &formatDescription) != noErr) return NULL;

    size_t byteCount = (size_t)frameCount * format.mBytesPerFrame;
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, NULL, byteCount,
        kCFAllocatorDefault, NULL, 0, byteCount, 0, &blockBuffer);
    if (status == noErr) status = CMBlockBufferFillDataBytes(0, blockBuffer, 0, byteCount);

    CMSampleBufferRef sampleBuffer = NULL;
    if (status == noErr) {
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(kCFAllocatorDefault,
            blockBuffer, formatDescription, frameCount, CMTimeMake(0, 48000), NULL, &sampleBuffer);
    }
    if (blockBuffer) CFRelease(blockBuffer);
    CFRelease(formatDescription);
    return status == noErr ? sampleBuffer : NULL;
}

static uint16_t HARTSPAvailableLoopbackPort(void) {
    int socketDescriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (socketDescriptor < 0) return 0;

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = 0;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(socketDescriptor, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(socketDescriptor);
        return 0;
    }

    socklen_t addressLength = sizeof(address);
    if (getsockname(socketDescriptor, (struct sockaddr *)&address, &addressLength) != 0) {
        close(socketDescriptor);
        return 0;
    }
    uint16_t port = ntohs(address.sin_port);
    close(socketDescriptor);
    return port;
}

static int HARTSPConnectToLoopback(uint16_t port) {
    int socketDescriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (socketDescriptor < 0) return -1;

#ifdef SO_NOSIGPIPE
    int noSignal = 1;
    setsockopt(socketDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
#endif
    struct timeval timeout;
    timeout.tv_sec = (int)HARTSPTestSocketTimeout;
    timeout.tv_usec = 0;
    setsockopt(socketDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(socketDescriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(socketDescriptor, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(socketDescriptor);
        return -1;
    }
    return socketDescriptor;
}

static BOOL HARTSPWriteString(int socketDescriptor, NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;
    while (offset < data.length) {
        ssize_t sent = send(socketDescriptor, bytes + offset, data.length - offset, 0);
        if (sent > 0) {
            offset += (NSUInteger)sent;
            continue;
        }
        if (sent < 0 && errno == EINTR) continue;
        return NO;
    }
    return YES;
}

static NSUInteger HARTSPContentLength(NSString *responseHead) {
    for (NSString *line in [responseHead componentsSeparatedByString:@"\r\n"]) {
        NSRange separator = [line rangeOfString:@":"];
        if (separator.location == NSNotFound) continue;
        NSString *key = [[line substringToIndex:separator.location]
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([key caseInsensitiveCompare:@"Content-Length"] != NSOrderedSame) continue;
        NSString *value = [[line substringFromIndex:separator.location + 1]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        return (NSUInteger)value.longLongValue;
    }
    return 0;
}

static NSString *HARTSPReadResponse(int socketDescriptor) {
    NSMutableData *response = [NSMutableData data];
    NSData *headerTerminator = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger expectedLength = NSNotFound;
    uint8_t buffer[4096];
    while (response.length < 64 * 1024) {
        ssize_t received = recv(socketDescriptor, buffer, sizeof(buffer), 0);
        if (received > 0) {
            [response appendBytes:buffer length:(NSUInteger)received];
            if (expectedLength == NSNotFound) {
                NSRange end = [response rangeOfData:headerTerminator
                                           options:0
                                             range:NSMakeRange(0, response.length)];
                if (end.location != NSNotFound) {
                    NSUInteger headerLength = end.location + end.length;
                    NSData *headData = [response subdataWithRange:NSMakeRange(0, headerLength)];
                    NSString *head = [[NSString alloc] initWithData:headData encoding:NSUTF8StringEncoding];
                    if (!head) return nil;
                    expectedLength = headerLength + HARTSPContentLength(head);
                }
            }
            if (expectedLength != NSNotFound && response.length >= expectedLength) {
                NSData *completeResponse = [response subdataWithRange:NSMakeRange(0, expectedLength)];
                return [[NSString alloc] initWithData:completeResponse encoding:NSUTF8StringEncoding];
            }
            continue;
        }
        if (received < 0 && errno == EINTR) continue;
        return nil;
    }
    return nil;
}

static NSData *HARTSPReadExactBytes(int socketDescriptor, NSUInteger length) {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    uint8_t *bytes = data.mutableBytes;
    NSUInteger offset = 0;
    while (offset < length) {
        ssize_t received = recv(socketDescriptor, bytes + offset, length - offset, 0);
        if (received > 0) {
            offset += (NSUInteger)received;
            continue;
        }
        if (received < 0 && errno == EINTR) continue;
        return nil;
    }
    return data;
}

static NSData *HARTSPReadInterleavedFrame(int socketDescriptor, uint8_t *channelOut) {
    NSData *header = HARTSPReadExactBytes(socketDescriptor, 4);
    if (header.length != 4) return nil;
    const uint8_t *bytes = header.bytes;
    if (bytes[0] != '$') return nil;
    NSUInteger length = ((NSUInteger)bytes[2] << 8) | bytes[3];
    if (channelOut) *channelOut = bytes[1];
    return HARTSPReadExactBytes(socketDescriptor, length);
}

static NSString *HARTSPHeaderValue(NSString *response, NSString *headerName) {
    if (!response.length || !headerName.length) return nil;
    NSRange headEnd = [response rangeOfString:@"\r\n\r\n"];
    NSString *head = headEnd.location == NSNotFound ? response : [response substringToIndex:headEnd.location];
    for (NSString *line in [head componentsSeparatedByString:@"\r\n"]) {
        NSRange separator = [line rangeOfString:@":"];
        if (separator.location == NSNotFound) continue;
        NSString *key = [[line substringToIndex:separator.location]
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([key caseInsensitiveCompare:headerName] != NSOrderedSame) continue;
        return [[line substringFromIndex:separator.location + 1]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    return nil;
}

static NSString *HARTSPQuotedChallengeValue(NSString *challenge, NSString *name) {
    if (!challenge.length || !name.length) return nil;
    NSString *prefix = [NSString stringWithFormat:@"%@=\"", name];
    NSRange start = [challenge rangeOfString:prefix options:NSCaseInsensitiveSearch];
    if (start.location == NSNotFound) return nil;
    NSUInteger valueStart = NSMaxRange(start);
    NSRange end = [challenge rangeOfString:@"\""
                                  options:0
                                    range:NSMakeRange(valueStart, challenge.length - valueStart)];
    if (end.location == NSNotFound) return nil;
    return [challenge substringWithRange:NSMakeRange(valueStart, end.location - valueStart)];
}

static NSString *HARTSPTestMD5Hex(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);
#pragma clang diagnostic pop
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_MD5_DIGEST_LENGTH; index++) {
        [hex appendFormat:@"%02x", digest[index]];
    }
    return hex;
}

static NSString *HARTSPDigestAuthorization(NSString *method,
                                            NSString *URI,
                                            NSString *username,
                                            NSString *password,
                                            NSString *nonce) {
    NSString *realm = @"HA Dashboard";
    NSString *HA1 = HARTSPTestMD5Hex([NSString stringWithFormat:@"%@:%@:%@", username, realm, password]);
    NSString *HA2 = HARTSPTestMD5Hex([NSString stringWithFormat:@"%@:%@", method, URI]);
    NSString *response = HARTSPTestMD5Hex([NSString stringWithFormat:@"%@:%@:%@", HA1, nonce, HA2]);
    return [NSString stringWithFormat:
            @"Digest username=\"%@\", realm=\"%@\", nonce=\"%@\", uri=\"%@\", response=\"%@\", algorithm=MD5",
            username, realm, nonce, URI, response];
}

static BOOL HARTSPStartAuthenticatedVLCPlayback(int socketDescriptor,
                                                NSString *streamURL,
                                                NSString *username,
                                                NSString *password) {
    NSString *request = [NSString stringWithFormat:
        @"DESCRIBE %@ RTSP/1.0\r\nCSeq: 1\r\nAccept: application/sdp\r\n\r\n",
        streamURL];
    if (!HARTSPWriteString(socketDescriptor, request)) return NO;
    NSString *challengeResponse = HARTSPReadResponse(socketDescriptor);
    NSString *challenge = HARTSPHeaderValue(challengeResponse, @"WWW-Authenticate");
    NSString *nonce = HARTSPQuotedChallengeValue(challenge, @"nonce") ?: @"";
    if (!nonce.length) return NO;

    NSString *cachedAuthorization = HARTSPDigestAuthorization(
        @"DESCRIBE", streamURL, username, password, nonce);
    request = [NSString stringWithFormat:
        @"DESCRIBE %@ RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\nAuthorization: %@\r\n\r\n",
        streamURL, cachedAuthorization];
    if (!HARTSPWriteString(socketDescriptor, request) ||
        ![HARTSPReadResponse(socketDescriptor) hasPrefix:@"RTSP/1.0 200 OK"]) return NO;

    NSString *videoURL = [streamURL stringByAppendingString:@"/trackID=0"];
    request = [NSString stringWithFormat:
        @"SETUP %@ RTSP/1.0\r\nCSeq: 3\r\nTransport: RTP/AVP/TCP;unicast;interleaved=0-1\r\nAuthorization: %@\r\n\r\n",
        videoURL, cachedAuthorization];
    if (!HARTSPWriteString(socketDescriptor, request)) return NO;
    NSString *setupResponse = HARTSPReadResponse(socketDescriptor);
    if (![setupResponse hasPrefix:@"RTSP/1.0 200 OK"]) return NO;
    NSString *session = HARTSPHeaderValue(setupResponse, @"Session") ?: @"";
    if (!session.length) return NO;

    NSString *audioURL = [streamURL stringByAppendingString:@"/trackID=1"];
    request = [NSString stringWithFormat:
        @"SETUP %@ RTSP/1.0\r\nCSeq: 4\r\nSession: %@\r\nTransport: RTP/AVP/TCP;unicast;interleaved=2-3\r\nAuthorization: %@\r\n\r\n",
        audioURL, session, cachedAuthorization];
    if (!HARTSPWriteString(socketDescriptor, request) ||
        ![HARTSPReadResponse(socketDescriptor) hasPrefix:@"RTSP/1.0 200 OK"]) return NO;

    request = [NSString stringWithFormat:
        @"PLAY %@ RTSP/1.0\r\nCSeq: 5\r\nSession: %@\r\nAuthorization: %@\r\n\r\n",
        streamURL, session, cachedAuthorization];
    return HARTSPWriteString(socketDescriptor, request) &&
        [HARTSPReadResponse(socketDescriptor) hasPrefix:@"RTSP/1.0 200 OK"];
}

@interface HARTSPServerDelegateSpy : NSObject <HARTSPServerDelegate>
@property (nonatomic, assign) BOOL suppliesMediaConfiguration;
@property (nonatomic, assign) NSUInteger mediaConfigurationRequestCount;
@property (nonatomic, assign) NSUInteger keyFrameRequestCount;
@property (nonatomic, assign) NSUInteger maximumMediaClientCount;
@property (nonatomic, strong) NSError *serverError;
@end

@implementation HARTSPServerDelegateSpy

- (void)rtspServerDidChangeClientCount:(HARTSPServer *)server {
    self.maximumMediaClientCount = MAX(self.maximumMediaClientCount, server.clientCount);
}

- (void)rtspServerNeedsVideoKeyFrame:(HARTSPServer *)server {
    (void)server;
    self.keyFrameRequestCount++;
}

- (void)rtspServerNeedsMediaConfiguration:(HARTSPServer *)server {
    self.mediaConfigurationRequestCount++;
    if (!self.suppliesMediaConfiguration) return;

    const uint8_t avcConfiguration[] = {
        0x01, 0x42, 0x00, 0x1e, 0xff, 0xe1, 0x00, 0x04,
        0x67, 0x42, 0x00, 0x1e, 0x01, 0x00, 0x02, 0x68, 0xce,
    };
    const uint8_t audioConfiguration[] = {0x12, 0x10};
    [server setVideoConfiguration:[NSData dataWithBytes:avcConfiguration
                                                 length:sizeof(avcConfiguration)]];
    [server setAudioConfiguration:[NSData dataWithBytes:audioConfiguration
                                                 length:sizeof(audioConfiguration)]
                          channels:2
                        sampleRate:44100];
}

- (void)rtspServer:(HARTSPServer *)server didFailWithError:(NSError *)error {
    (void)server;
    self.serverError = error;
}

@end

@interface HAStreamingManager (CompatibilityTesting)
+ (BOOL)supportsOperatingSystemVersion:(NSOperatingSystemVersion)version;
+ (BOOL)usesAudioCompatiblePresetForOperatingSystemVersion:(NSOperatingSystemVersion)version;
+ (NSArray<NSString *> *)preferredLegacySessionPresetsForQualityScale:(float)qualityScale;
- (void)encodeAudio:(CMSampleBufferRef)sampleBuffer;
@end

@interface HAStreamingManager (AudioQueueTesting)
@property (nonatomic, strong) dispatch_queue_t audioCaptureQueue;
@property (nonatomic, strong) HAAACEncoder *audioEncoder;
@property (nonatomic, strong) NSData *publishedAudioConfiguration;
- (void)clearMediaState;
@end

@interface HARTSPAudioConfigurationSpy : HARTSPServer
@property (nonatomic, strong) XCTestExpectation *configurationExpectation;
@property (nonatomic, copy) NSData *audioConfiguration;
@property (nonatomic, assign) NSUInteger audioChannels;
@property (nonatomic, assign) NSUInteger audioSampleRate;
@property (nonatomic, assign) NSUInteger audioSampleCount;
@end

@implementation HARTSPAudioConfigurationSpy
- (BOOL)isRunning { return YES; }
- (void)setAudioConfiguration:(NSData *)configuration
                     channels:(NSUInteger)channels
                   sampleRate:(NSUInteger)sampleRate {
    self.audioConfiguration = configuration;
    self.audioChannels = channels;
    self.audioSampleRate = sampleRate;
    [self.configurationExpectation fulfill];
}
- (void)sendAudioSample:(NSData *)aacRaw timestamp:(uint32_t)milliseconds {
    (void)aacRaw;
    (void)milliseconds;
    self.audioSampleCount++;
}
@end

typedef ssize_t (^HARTSPTestSendFunction)(CFSocketNativeHandle socket,
                                          const void *bytes,
                                          size_t length,
                                          int *errorOut);

@interface HARTSPServer (BackpressureTesting)
@property (nonatomic, copy) HARTSPTestSendFunction sendFunctionForTesting;
@property (nonatomic, assign) NSUInteger maximumPendingOutputBytes;
- (NSUInteger)pendingOutputByteCountForTesting;
- (void)flushPendingClientWritesForTesting;
@end

@interface HAUnsupportedStreamingManager : HAStreamingManager
@end

@implementation HAUnsupportedStreamingManager
- (BOOL)supported { return NO; }
@end

@interface HACameraRegistrationManager (RegistrationTesting)
- (NSDictionary *)cameraConfigurationInputForURL:(NSString *)url
                                      optionsFlow:(BOOL)optionsFlow;
- (NSError *)cameraCredentialTransportErrorForURL:(NSURL *)URL;
- (void)processCurrentURL;
- (BOOL)ensureActiveAuthenticationOrCancel;
- (void)updateEntry:(NSString *)entryID forURL:(NSString *)url;
- (void)acceptEntry:(NSString *)entryID forURL:(NSString *)url;
- (void)createEntryForURL:(NSString *)url;
@end

@interface HACameraRegistrationRouteSpy : HACameraRegistrationManager
@property (nonatomic, copy) NSString *updatedEntryID;
@property (nonatomic, copy) NSString *acceptedEntryID;
@property (nonatomic, assign) BOOL createdEntry;
@end

@implementation HACameraRegistrationRouteSpy
- (BOOL)ensureActiveAuthenticationOrCancel { return YES; }
- (void)updateEntry:(NSString *)entryID forURL:(NSString *)url {
    (void)url;
    self.updatedEntryID = entryID;
}
- (void)acceptEntry:(NSString *)entryID forURL:(NSString *)url {
    (void)url;
    self.acceptedEntryID = entryID;
}
- (void)createEntryForURL:(NSString *)url {
    (void)url;
    self.createdEntry = YES;
}
@end

typedef HAAPIClient *(^HACameraRegistrationTestAPIClientFactory)(NSURL *baseURL,
                                                                  NSString *token,
                                                                  NSTimeInterval requestTimeout,
                                                                  NSTimeInterval resourceTimeout);
typedef id (^HACameraRegistrationTestRetryScheduler)(NSTimeInterval delay,
                                                      dispatch_block_t block);
typedef void (^HACameraRegistrationTestRetryCanceller)(id token);

@interface HACameraRegistrationManager (RetryTesting)
- (instancetype)initWithAPIClientFactory:(HACameraRegistrationTestAPIClientFactory)apiClientFactory
                            scheduleRetry:(HACameraRegistrationTestRetryScheduler)retryScheduler
                     cancelScheduledRetry:(HACameraRegistrationTestRetryCanceller)retryCanceller;
- (NSError *)registrationPreflightError;
- (NSString *)currentServerOriginToken;
- (void)beginRegistrationAttempt;
- (void)streamingStateDidChange:(NSNotification *)notification;
@end

@interface HACameraRegistrationRetryTestClient : HAAPIClient
@property (nonatomic, assign, getter=isCancelledForTesting) BOOL cancelledForTesting;
@property (nonatomic, assign) NSUInteger getCount;
@property (nonatomic, assign) NSUInteger postCount;
@property (nonatomic, assign) NSUInteger deleteCount;
@property (nonatomic, copy) NSString *deletedPath;
@end

@implementation HACameraRegistrationRetryTestClient

- (void)getJSONAtPath:(NSString *)path completion:(HAAPIResponseBlock)completion {
    (void)path;
    self.getCount++;
    if (completion) completion(@[], nil);
}

- (void)postJSONAtPath:(NSString *)path body:(NSDictionary *)body completion:(HAAPIResponseBlock)completion {
    (void)body;
    self.postCount++;
    if ([path isEqualToString:@"config/config_entries/flow"]) {
        if (completion) completion(@{@"flow_id": @"test-camera-flow"}, nil);
        return;
    }
    NSError *timeout = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut
        userInfo:@{NSLocalizedDescriptionKey: @"The request timed out."}];
    if (completion) completion(nil, timeout);
}

- (void)deleteJSONAtPath:(NSString *)path completion:(HAAPIResponseBlock)completion {
    self.deleteCount++;
    self.deletedPath = path;
    if (completion) completion(@{}, nil);
}

- (void)cancelAllRequests {
    self.cancelledForTesting = YES;
}

@end


@interface HACameraRegistrationRetryTestManager : HACameraRegistrationManager
@property (nonatomic, assign) BOOL allowRegistrationToContinue;
@property (nonatomic, assign) BOOL streamListenerArmedForTesting;
@end

@implementation HACameraRegistrationRetryTestManager
- (NSError *)registrationPreflightError { return nil; }
- (NSString *)currentServerOriginToken { return @"https|test.home-assistant.invalid|443"; }
- (BOOL)registrationCanContinue {
    return self.isRegistering && self.allowRegistrationToContinue;
}
- (BOOL)ensureActiveAuthenticationOrCancel {
    if ([self registrationCanContinue]) return YES;
    [self cancelRegistration];
    return NO;
}
- (BOOL)streamListenerIsArmedForPendingURLs {
    return self.streamListenerArmedForTesting;
}
@end

@interface HAStreamingTests : XCTestCase
@end

@implementation HAStreamingTests

- (void)testRTSPServerBindsTheAdvertisedAddress {
    HARTSPServer *server = [[HARTSPServer alloc] initWithHost:@"127.0.0.1" port:18554
        username:@"hadashboard" password:@"test-password"];
    XCTAssertNil(server.streamURL);
    NSError *error = nil;
    XCTAssertTrue([server start:&error]);
    XCTAssertNil(error);
    XCTAssertEqualObjects(server.streamURL, @"rtsp://127.0.0.1:18554/live");
    [server stop];
    XCTAssertNil(server.streamURL);
}

- (void)testRTSPServerRejectsAnInvalidAdvertisedAddress {
    HARTSPServer *server = [[HARTSPServer alloc] initWithHost:@"not-an-address" port:18554
        username:@"hadashboard" password:@"test-password"];
    NSError *error = nil;
    XCTAssertFalse([server start:&error]);
    XCTAssertNotNil(error);
}

- (void)testRTSPDigestRejectsMissingAndWrongCredentialsWithoutMediaDemand {
    uint16_t port = HARTSPAvailableLoopbackPort();
    XCTAssertNotEqual(port, (uint16_t)0);
    HARTSPServerDelegateSpy *delegate = [[HARTSPServerDelegateSpy alloc] init];
    HARTSPServer *server = [[HARTSPServer alloc] initWithHost:@"127.0.0.1"
                                                        port:port
                                                    username:@"hadashboard"
                                                    password:@"correct-password"];
    server.delegate = delegate;
    NSError *startError = nil;
    XCTAssertTrue([server start:&startError]);
    XCTAssertNil(startError);

    NSString *streamURL = server.streamURL;
    XCTestExpectation *responsesReceived = [self expectationWithDescription:@"Unauthorized responses received"];
    XCTestExpectation *clientClosed = [self expectationWithDescription:@"Unauthorized client closed"];
    dispatch_semaphore_t closeGate = dispatch_semaphore_create(0);
    __block BOOL connected = NO;
    __block NSString *missingCredentialResponse = nil;
    __block NSString *wrongCredentialResponse = nil;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            int socketDescriptor = HARTSPConnectToLoopback(port);
            NSString *missingResponse = nil;
            NSString *wrongResponse = nil;
            if (socketDescriptor >= 0) {
                NSString *request = [NSString stringWithFormat:
                                     @"DESCRIBE %@ RTSP/1.0\r\nCSeq: 1\r\nAccept: application/sdp\r\n\r\n",
                                     streamURL];
                if (HARTSPWriteString(socketDescriptor, request)) {
                    missingResponse = HARTSPReadResponse(socketDescriptor);
                    NSString *challenge = HARTSPHeaderValue(missingResponse, @"WWW-Authenticate");
                    NSString *nonce = HARTSPQuotedChallengeValue(challenge, @"nonce") ?: @"";
                    NSString *authorization = HARTSPDigestAuthorization(@"DESCRIBE", streamURL,
                                                                         @"hadashboard", @"wrong-password",
                                                                         nonce);
                    request = [NSString stringWithFormat:
                               @"DESCRIBE %@ RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\nAuthorization: %@\r\n\r\n",
                               streamURL, authorization];
                    if (HARTSPWriteString(socketDescriptor, request)) {
                        wrongResponse = HARTSPReadResponse(socketDescriptor);
                    }
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                connected = socketDescriptor >= 0;
                missingCredentialResponse = missingResponse;
                wrongCredentialResponse = wrongResponse;
                [responsesReceived fulfill];
            });
            dispatch_semaphore_wait(closeGate,
                                    dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)));
            if (socketDescriptor >= 0) close(socketDescriptor);
            dispatch_async(dispatch_get_main_queue(), ^{ [clientClosed fulfill]; });
        }
    });

    [self waitForExpectations:@[responsesReceived] timeout:5.0];
    XCTAssertTrue(connected);
    XCTAssertTrue([missingCredentialResponse hasPrefix:@"RTSP/1.0 401 Unauthorized"]);
    NSString *challenge = [HARTSPHeaderValue(missingCredentialResponse, @"WWW-Authenticate") lowercaseString];
    XCTAssertTrue([challenge containsString:@"algorithm=md5"]);
    XCTAssertFalse([challenge containsString:@"qop="]);
    XCTAssertTrue([wrongCredentialResponse hasPrefix:@"RTSP/1.0 401 Unauthorized"]);
    XCTAssertEqual(server.connectionCount, (NSUInteger)1);
    XCTAssertEqual(server.clientCount, (NSUInteger)0);
    XCTAssertEqual(server.playingClientCount, (NSUInteger)0);
    XCTAssertEqual(delegate.maximumMediaClientCount, (NSUInteger)0);
    XCTAssertEqual(delegate.mediaConfigurationRequestCount, (NSUInteger)0);
    XCTAssertEqual(delegate.keyFrameRequestCount, (NSUInteger)0);
    XCTAssertNil(delegate.serverError);

    dispatch_semaphore_signal(closeGate);
    [self waitForExpectations:@[clientClosed] timeout:5.0];
    [server stop];
}

- (void)testRTSPDigestStartsMediaDemandOnlyAfterAuthenticatedDescribeSetupAndPlay {
    uint16_t port = HARTSPAvailableLoopbackPort();
    XCTAssertNotEqual(port, (uint16_t)0);
    HARTSPServerDelegateSpy *delegate = [[HARTSPServerDelegateSpy alloc] init];
    delegate.suppliesMediaConfiguration = YES;
    NSString *username = @"hadashboard";
    NSString *password = @"correct-password";
    HARTSPServer *server = [[HARTSPServer alloc] initWithHost:@"127.0.0.1"
                                                        port:port
                                                    username:username
                                                    password:password];
    server.delegate = delegate;
    NSError *startError = nil;
    XCTAssertTrue([server start:&startError]);
    XCTAssertNil(startError);

    NSString *streamURL = server.streamURL;
    NSString *videoTrackURL = [streamURL stringByAppendingString:@"/trackID=0"];
    XCTestExpectation *challengeReceived = [self expectationWithDescription:@"Digest challenge received"];
    XCTestExpectation *playing = [self expectationWithDescription:@"Authenticated PLAY completed"];
    XCTestExpectation *clientClosed = [self expectationWithDescription:@"Authenticated client closed"];
    dispatch_semaphore_t authenticationGate = dispatch_semaphore_create(0);
    dispatch_semaphore_t closeGate = dispatch_semaphore_create(0);
    __block BOOL connected = NO;
    __block NSString *challengeResponse = nil;
    __block NSString *describeResponse = nil;
    __block NSString *setupResponse = nil;
    __block NSString *playResponse = nil;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            int socketDescriptor = HARTSPConnectToLoopback(port);
            NSString *localChallengeResponse = nil;
            NSString *nonce = @"";
            if (socketDescriptor >= 0) {
                NSString *request = [NSString stringWithFormat:
                                     @"DESCRIBE %@ RTSP/1.0\r\nCSeq: 1\r\nAccept: application/sdp\r\n\r\n",
                                     streamURL];
                if (HARTSPWriteString(socketDescriptor, request)) {
                    localChallengeResponse = HARTSPReadResponse(socketDescriptor);
                    NSString *challenge = HARTSPHeaderValue(localChallengeResponse, @"WWW-Authenticate");
                    nonce = HARTSPQuotedChallengeValue(challenge, @"nonce") ?: @"";
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                connected = socketDescriptor >= 0;
                challengeResponse = localChallengeResponse;
                [challengeReceived fulfill];
            });

            dispatch_semaphore_wait(authenticationGate,
                                    dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)));
            NSString *localDescribeResponse = nil;
            NSString *localSetupResponse = nil;
            NSString *localPlayResponse = nil;
            if (socketDescriptor >= 0 && nonce.length) {
                NSString *authorization = HARTSPDigestAuthorization(@"DESCRIBE", streamURL,
                                                                     username, password, nonce);
                NSString *request = [NSString stringWithFormat:
                                     @"DESCRIBE %@ RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\nAuthorization: %@\r\n\r\n",
                                     streamURL, authorization];
                if (HARTSPWriteString(socketDescriptor, request)) {
                    localDescribeResponse = HARTSPReadResponse(socketDescriptor);
                }

                authorization = HARTSPDigestAuthorization(@"SETUP", videoTrackURL,
                                                           username, password, nonce);
                request = [NSString stringWithFormat:
                           @"SETUP %@ RTSP/1.0\r\nCSeq: 3\r\nTransport: RTP/AVP/TCP;unicast;interleaved=0-1\r\nAuthorization: %@\r\n\r\n",
                           videoTrackURL, authorization];
                if (HARTSPWriteString(socketDescriptor, request)) {
                    localSetupResponse = HARTSPReadResponse(socketDescriptor);
                }

                NSString *session = HARTSPHeaderValue(localSetupResponse, @"Session") ?: @"";
                authorization = HARTSPDigestAuthorization(@"PLAY", streamURL,
                                                           username, password, nonce);
                request = [NSString stringWithFormat:
                           @"PLAY %@ RTSP/1.0\r\nCSeq: 4\r\nSession: %@\r\nAuthorization: %@\r\n\r\n",
                           streamURL, session, authorization];
                if (HARTSPWriteString(socketDescriptor, request)) {
                    localPlayResponse = HARTSPReadResponse(socketDescriptor);
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                describeResponse = localDescribeResponse;
                setupResponse = localSetupResponse;
                playResponse = localPlayResponse;
                [playing fulfill];
            });

            dispatch_semaphore_wait(closeGate,
                                    dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)));
            if (socketDescriptor >= 0) close(socketDescriptor);
            dispatch_async(dispatch_get_main_queue(), ^{ [clientClosed fulfill]; });
        }
    });

    [self waitForExpectations:@[challengeReceived] timeout:5.0];
    XCTAssertTrue(connected);
    XCTAssertTrue([challengeResponse hasPrefix:@"RTSP/1.0 401 Unauthorized"]);
    NSString *challenge = [HARTSPHeaderValue(challengeResponse, @"WWW-Authenticate") lowercaseString];
    XCTAssertTrue([challenge containsString:@"algorithm=md5"]);
    XCTAssertFalse([challenge containsString:@"qop="]);
    XCTAssertEqual(server.connectionCount, (NSUInteger)1);
    XCTAssertEqual(server.clientCount, (NSUInteger)0);
    XCTAssertEqual(server.playingClientCount, (NSUInteger)0);
    XCTAssertEqual(delegate.maximumMediaClientCount, (NSUInteger)0);
    XCTAssertEqual(delegate.mediaConfigurationRequestCount, (NSUInteger)0);
    XCTAssertEqual(delegate.keyFrameRequestCount, (NSUInteger)0);

    dispatch_semaphore_signal(authenticationGate);
    [self waitForExpectations:@[playing] timeout:5.0];
    XCTAssertTrue([describeResponse hasPrefix:@"RTSP/1.0 200 OK"]);
    XCTAssertTrue([describeResponse containsString:@"m=video 0 RTP/AVP 96"]);
    XCTAssertTrue([describeResponse containsString:@"m=audio 0 RTP/AVP 97"]);
    XCTAssertTrue([setupResponse hasPrefix:@"RTSP/1.0 200 OK"]);
    XCTAssertGreaterThan(HARTSPHeaderValue(setupResponse, @"Session").length, (NSUInteger)0);
    XCTAssertTrue([playResponse hasPrefix:@"RTSP/1.0 200 OK"]);
    XCTAssertEqual(server.clientCount, (NSUInteger)1);
    XCTAssertEqual(server.playingClientCount, (NSUInteger)1);
    XCTAssertEqual(delegate.maximumMediaClientCount, (NSUInteger)1);
    XCTAssertEqual(delegate.mediaConfigurationRequestCount, (NSUInteger)1);
    XCTAssertEqual(delegate.keyFrameRequestCount, (NSUInteger)1);
    XCTAssertNil(delegate.serverError);

    dispatch_semaphore_signal(closeGate);
    [self waitForExpectations:@[clientClosed] timeout:5.0];
    [server stop];
}

- (void)testRTSPDigestAcceptsVLCCachedDescribeAuthorizationOnSameConnection {
    uint16_t port = HARTSPAvailableLoopbackPort();
    XCTAssertNotEqual(port, (uint16_t)0);
    HARTSPServerDelegateSpy *delegate = [[HARTSPServerDelegateSpy alloc] init];
    delegate.suppliesMediaConfiguration = YES;
    NSString *username = @"hadashboard";
    NSString *password = @"correct-password";
    HARTSPServer *server = [[HARTSPServer alloc] initWithHost:@"127.0.0.1"
                                                        port:port
                                                    username:username
                                                    password:password];
    server.delegate = delegate;
    NSError *startError = nil;
    XCTAssertTrue([server start:&startError]);
    XCTAssertNil(startError);

    NSString *streamURL = server.streamURL;
    NSString *videoTrackURL = [streamURL stringByAppendingString:@"/trackID=0"];
    NSString *audioTrackURL = [streamURL stringByAppendingString:@"/trackID=1"];
    XCTestExpectation *requestsCompleted = [self expectationWithDescription:
        @"VLC-style cached Digest requests completed"];
    XCTestExpectation *clientClosed = [self expectationWithDescription:
        @"VLC-style client closed"];
    dispatch_semaphore_t closeGate = dispatch_semaphore_create(0);
    __block BOOL connected = NO;
    __block NSString *challengeResponse = nil;
    __block NSString *describeResponse = nil;
    __block NSString *videoSetupResponse = nil;
    __block NSString *audioSetupResponse = nil;
    __block NSString *wrongSessionPlayResponse = nil;
    __block NSString *playResponse = nil;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            int socketDescriptor = HARTSPConnectToLoopback(port);
            NSString *localChallengeResponse = nil;
            NSString *localDescribeResponse = nil;
            NSString *localVideoSetupResponse = nil;
            NSString *localAudioSetupResponse = nil;
            NSString *localWrongSessionPlayResponse = nil;
            NSString *localPlayResponse = nil;
            if (socketDescriptor >= 0) {
                NSString *request = [NSString stringWithFormat:
                    @"DESCRIBE %@ RTSP/1.0\r\nCSeq: 1\r\nAccept: application/sdp\r\n\r\n",
                    streamURL];
                if (HARTSPWriteString(socketDescriptor, request)) {
                    localChallengeResponse = HARTSPReadResponse(socketDescriptor);
                }

                NSString *challenge = HARTSPHeaderValue(localChallengeResponse,
                                                         @"WWW-Authenticate");
                NSString *nonce = HARTSPQuotedChallengeValue(challenge, @"nonce") ?: @"";
                NSString *cachedDescribeAuthorization = HARTSPDigestAuthorization(
                    @"DESCRIBE", streamURL, username, password, nonce);

                request = [NSString stringWithFormat:
                    @"DESCRIBE %@ RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\nAuthorization: %@\r\n\r\n",
                    streamURL, cachedDescribeAuthorization];
                if (HARTSPWriteString(socketDescriptor, request)) {
                    localDescribeResponse = HARTSPReadResponse(socketDescriptor);
                }

                // VLC 3.0.21 sends this exact DESCRIBE digest again: its URI and
                // response are not recomputed for either SETUP track or PLAY.
                request = [NSString stringWithFormat:
                    @"SETUP %@ RTSP/1.0\r\nCSeq: 3\r\nTransport: RTP/AVP/TCP;unicast;interleaved=0-1\r\nAuthorization: %@\r\n\r\n",
                    videoTrackURL, cachedDescribeAuthorization];
                if (HARTSPWriteString(socketDescriptor, request)) {
                    localVideoSetupResponse = HARTSPReadResponse(socketDescriptor);
                }

                NSString *session = HARTSPHeaderValue(localVideoSetupResponse, @"Session") ?: @"";
                request = [NSString stringWithFormat:
                    @"SETUP %@ RTSP/1.0\r\nCSeq: 4\r\nSession: %@\r\nTransport: RTP/AVP/TCP;unicast;interleaved=2-3\r\nAuthorization: %@\r\n\r\n",
                    audioTrackURL, session, cachedDescribeAuthorization];
                if (HARTSPWriteString(socketDescriptor, request)) {
                    localAudioSetupResponse = HARTSPReadResponse(socketDescriptor);
                }

                request = [NSString stringWithFormat:
                    @"PLAY %@ RTSP/1.0\r\nCSeq: 5\r\nSession: %@\r\nAuthorization: %@\r\n\r\n",
                    streamURL, @"not-the-negotiated-session", cachedDescribeAuthorization];
                if (HARTSPWriteString(socketDescriptor, request)) {
                    localWrongSessionPlayResponse = HARTSPReadResponse(socketDescriptor);
                }

                request = [NSString stringWithFormat:
                    @"PLAY %@ RTSP/1.0\r\nCSeq: 6\r\nSession: %@\r\nAuthorization: %@\r\n\r\n",
                    streamURL, session, cachedDescribeAuthorization];
                if (HARTSPWriteString(socketDescriptor, request)) {
                    localPlayResponse = HARTSPReadResponse(socketDescriptor);
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                connected = socketDescriptor >= 0;
                challengeResponse = localChallengeResponse;
                describeResponse = localDescribeResponse;
                videoSetupResponse = localVideoSetupResponse;
                audioSetupResponse = localAudioSetupResponse;
                wrongSessionPlayResponse = localWrongSessionPlayResponse;
                playResponse = localPlayResponse;
                [requestsCompleted fulfill];
            });

            dispatch_semaphore_wait(closeGate,
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)));
            if (socketDescriptor >= 0) close(socketDescriptor);
            dispatch_async(dispatch_get_main_queue(), ^{ [clientClosed fulfill]; });
        }
    });

    [self waitForExpectations:@[requestsCompleted] timeout:8.0];
    XCTAssertTrue(connected);
    XCTAssertTrue([challengeResponse hasPrefix:@"RTSP/1.0 401 Unauthorized"]);
    XCTAssertTrue([describeResponse hasPrefix:@"RTSP/1.0 200 OK"]);
    XCTAssertTrue([videoSetupResponse hasPrefix:@"RTSP/1.0 200 OK"]);
    XCTAssertGreaterThan(HARTSPHeaderValue(videoSetupResponse, @"Session").length,
                         (NSUInteger)0);
    XCTAssertTrue([audioSetupResponse hasPrefix:@"RTSP/1.0 200 OK"]);
    XCTAssertTrue([wrongSessionPlayResponse hasPrefix:@"RTSP/1.0 454 Session Not Found"]);
    XCTAssertTrue([playResponse hasPrefix:@"RTSP/1.0 200 OK"]);
    XCTAssertEqual(server.connectionCount, (NSUInteger)1);
    XCTAssertEqual(server.clientCount, (NSUInteger)1);
    XCTAssertEqual(server.playingClientCount, (NSUInteger)1);
    XCTAssertEqual(delegate.mediaConfigurationRequestCount, (NSUInteger)1);
    XCTAssertEqual(delegate.keyFrameRequestCount, (NSUInteger)1);
    XCTAssertNil(delegate.serverError);

    dispatch_semaphore_signal(closeGate);
    [self waitForExpectations:@[clientClosed] timeout:5.0];
    [server stop];
}

- (void)testRTSPTransientWriteBackpressureBuffersAndFlushesRTPInOrder {
    uint16_t port = HARTSPAvailableLoopbackPort();
    XCTAssertNotEqual(port, (uint16_t)0);
    HARTSPServerDelegateSpy *delegate = [[HARTSPServerDelegateSpy alloc] init];
    delegate.suppliesMediaConfiguration = YES;
    HARTSPServer *server = [[HARTSPServer alloc] initWithHost:@"127.0.0.1"
                                                        port:port
                                                    username:@"hadashboard"
                                                    password:@"correct-password"];
    server.delegate = delegate;
    NSError *startError = nil;
    XCTAssertTrue([server start:&startError]);
    XCTAssertNil(startError);

    XCTestExpectation *playbackReady = [self expectationWithDescription:@"Slow VLC playback ready"];
    XCTestExpectation *framesRead = [self expectationWithDescription:@"Buffered RTP frames read"];
    XCTestExpectation *clientClosed = [self expectationWithDescription:@"Slow VLC client closed"];
    dispatch_semaphore_t readGate = dispatch_semaphore_create(0);
    dispatch_semaphore_t closeGate = dispatch_semaphore_create(0);
    __block BOOL playbackStarted = NO;
    __block NSArray<NSData *> *receivedFrames = nil;
    __block NSArray<NSNumber *> *receivedChannels = nil;
    NSString *streamURL = server.streamURL;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            int socketDescriptor = HARTSPConnectToLoopback(port);
            BOOL started = socketDescriptor >= 0 && HARTSPStartAuthenticatedVLCPlayback(
                socketDescriptor, streamURL, @"hadashboard", @"correct-password");
            dispatch_async(dispatch_get_main_queue(), ^{
                playbackStarted = started;
                [playbackReady fulfill];
            });

            dispatch_semaphore_wait(readGate,
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)));
            NSMutableArray<NSData *> *frames = [NSMutableArray array];
            NSMutableArray<NSNumber *> *channels = [NSMutableArray array];
            if (started) {
                for (NSUInteger index = 0; index < 3; index++) {
                    uint8_t channel = UINT8_MAX;
                    NSData *frame = HARTSPReadInterleavedFrame(socketDescriptor, &channel);
                    if (!frame) break;
                    [frames addObject:frame];
                    [channels addObject:@(channel)];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                receivedFrames = [frames copy];
                receivedChannels = [channels copy];
                [framesRead fulfill];
            });

            dispatch_semaphore_wait(closeGate,
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)));
            if (socketDescriptor >= 0) close(socketDescriptor);
            dispatch_async(dispatch_get_main_queue(), ^{ [clientClosed fulfill]; });
        }
    });

    [self waitForExpectations:@[playbackReady] timeout:8.0];
    XCTAssertTrue(playbackStarted);
    XCTAssertEqual(server.connectionCount, (NSUInteger)1);
    XCTAssertEqual(server.playingClientCount, (NSUInteger)1);

    __block BOOL blockWrites = YES;
    __block BOOL partialWriteCompleted = NO;
    server.sendFunctionForTesting = ^ssize_t(CFSocketNativeHandle socket,
                                              const void *bytes,
                                              size_t length,
                                              int *errorOut) {
        if (errorOut) *errorOut = 0;
        if (blockWrites) {
            if (!partialWriteCompleted) {
                partialWriteCompleted = YES;
                ssize_t sent = send(socket, bytes, MIN((size_t)7, length), 0);
                if (sent < 0 && errorOut) *errorOut = errno;
                return sent;
            }
            if (errorOut) *errorOut = EAGAIN;
            return -1;
        }
        ssize_t sent = send(socket, bytes, length, 0);
        if (sent < 0 && errorOut) *errorOut = errno;
        return sent;
    };

    const uint8_t firstVideoBytes[] = {0, 0, 0, 3, 0x41, 0x11, 0x12};
    const uint8_t audioBytes[] = {0x31, 0x32, 0x33};
    const uint8_t secondVideoBytes[] = {0, 0, 0, 3, 0x41, 0x21, 0x22};
    NSData *firstVideo = [NSData dataWithBytes:firstVideoBytes length:sizeof(firstVideoBytes)];
    NSData *audio = [NSData dataWithBytes:audioBytes length:sizeof(audioBytes)];
    NSData *secondVideo = [NSData dataWithBytes:secondVideoBytes length:sizeof(secondVideoBytes)];
    [server sendVideoSample:firstVideo keyFrame:NO timestamp:0];
    [server sendAudioSample:audio timestamp:0];
    [server sendVideoSample:secondVideo keyFrame:NO timestamp:33];

    XCTAssertTrue(partialWriteCompleted);
    XCTAssertGreaterThan([server pendingOutputByteCountForTesting], (NSUInteger)0);
    XCTAssertEqual(server.connectionCount, (NSUInteger)1);
    XCTAssertEqual(server.clientCount, (NSUInteger)1);
    XCTAssertEqual(server.playingClientCount, (NSUInteger)1);

    blockWrites = NO;
    [server flushPendingClientWritesForTesting];
    XCTAssertEqual([server pendingOutputByteCountForTesting], (NSUInteger)0);
    dispatch_semaphore_signal(readGate);
    [self waitForExpectations:@[framesRead] timeout:5.0];

    XCTAssertEqualObjects(receivedChannels, (@[@0, @2, @0]));
    XCTAssertEqual(receivedFrames.count, (NSUInteger)3);
    if (receivedFrames.count == 3) {
        NSData *firstPayload = [receivedFrames[0] subdataWithRange:
            NSMakeRange(12, receivedFrames[0].length - 12)];
        NSData *audioPayload = [receivedFrames[1] subdataWithRange:
            NSMakeRange(16, receivedFrames[1].length - 16)];
        NSData *secondPayload = [receivedFrames[2] subdataWithRange:
            NSMakeRange(12, receivedFrames[2].length - 12)];
        XCTAssertEqualObjects(firstPayload,
            [NSData dataWithBytes:firstVideoBytes + 4 length:sizeof(firstVideoBytes) - 4]);
        XCTAssertEqualObjects(audioPayload, audio);
        XCTAssertEqualObjects(secondPayload,
            [NSData dataWithBytes:secondVideoBytes + 4 length:sizeof(secondVideoBytes) - 4]);
        const uint8_t *firstRTP = receivedFrames[0].bytes;
        const uint8_t *secondRTP = receivedFrames[2].bytes;
        uint16_t firstSequence = ((uint16_t)firstRTP[2] << 8) | firstRTP[3];
        uint16_t secondSequence = ((uint16_t)secondRTP[2] << 8) | secondRTP[3];
        XCTAssertEqual(secondSequence, (uint16_t)(firstSequence + 1));
    }

    server.sendFunctionForTesting = nil;
    dispatch_semaphore_signal(closeGate);
    [self waitForExpectations:@[clientClosed] timeout:5.0];
    [server stop];
}

- (void)testRTSPSlowClientClosesOnlyAfterPendingOutputLimit {
    uint16_t port = HARTSPAvailableLoopbackPort();
    XCTAssertNotEqual(port, (uint16_t)0);
    HARTSPServerDelegateSpy *delegate = [[HARTSPServerDelegateSpy alloc] init];
    delegate.suppliesMediaConfiguration = YES;
    HARTSPServer *server = [[HARTSPServer alloc] initWithHost:@"127.0.0.1"
                                                        port:port
                                                    username:@"hadashboard"
                                                    password:@"correct-password"];
    server.delegate = delegate;
    NSError *startError = nil;
    XCTAssertTrue([server start:&startError]);
    XCTAssertNil(startError);

    XCTestExpectation *playbackReady = [self expectationWithDescription:@"Bounded client ready"];
    XCTestExpectation *workerClosed = [self expectationWithDescription:@"Bounded client worker closed"];
    dispatch_semaphore_t closeGate = dispatch_semaphore_create(0);
    __block BOOL playbackStarted = NO;
    NSString *streamURL = server.streamURL;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            int socketDescriptor = HARTSPConnectToLoopback(port);
            BOOL started = socketDescriptor >= 0 && HARTSPStartAuthenticatedVLCPlayback(
                socketDescriptor, streamURL, @"hadashboard", @"correct-password");
            dispatch_async(dispatch_get_main_queue(), ^{
                playbackStarted = started;
                [playbackReady fulfill];
            });
            dispatch_semaphore_wait(closeGate,
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)));
            if (socketDescriptor >= 0) close(socketDescriptor);
            dispatch_async(dispatch_get_main_queue(), ^{ [workerClosed fulfill]; });
        }
    });

    [self waitForExpectations:@[playbackReady] timeout:8.0];
    XCTAssertTrue(playbackStarted);
    server.maximumPendingOutputBytes = 40;
    server.sendFunctionForTesting = ^ssize_t(CFSocketNativeHandle socket,
                                              const void *bytes,
                                              size_t length,
                                              int *errorOut) {
        (void)socket; (void)bytes; (void)length;
        if (errorOut) *errorOut = EAGAIN;
        return -1;
    };

    const uint8_t videoBytes[] = {0, 0, 0, 3, 0x41, 0x01, 0x02};
    const uint8_t audioBytes[] = {0x03, 0x04, 0x05};
    [server sendVideoSample:[NSData dataWithBytes:videoBytes length:sizeof(videoBytes)]
                   keyFrame:NO timestamp:0];
    XCTAssertGreaterThan([server pendingOutputByteCountForTesting], (NSUInteger)0);
    XCTAssertEqual(server.connectionCount, (NSUInteger)1);
    [server sendAudioSample:[NSData dataWithBytes:audioBytes length:sizeof(audioBytes)]
                   timestamp:0];

    XCTAssertEqual(server.connectionCount, (NSUInteger)0);
    XCTAssertEqual(server.clientCount, (NSUInteger)0);
    XCTAssertEqual(server.playingClientCount, (NSUInteger)0);
    XCTAssertEqual([server pendingOutputByteCountForTesting], (NSUInteger)0);
    XCTAssertTrue(server.running);

    server.sendFunctionForTesting = nil;
    dispatch_semaphore_signal(closeGate);
    [self waitForExpectations:@[workerClosed] timeout:5.0];
    [server stop];
}

- (void)testRTSPReconnectWithVerifiedStaleNonceReceivesFreshChallenge {
    uint16_t port = HARTSPAvailableLoopbackPort();
    XCTAssertNotEqual(port, (uint16_t)0);
    HARTSPServerDelegateSpy *delegate = [[HARTSPServerDelegateSpy alloc] init];
    delegate.suppliesMediaConfiguration = YES;
    NSString *username = @"hadashboard";
    NSString *password = @"correct-password";
    HARTSPServer *server = [[HARTSPServer alloc] initWithHost:@"127.0.0.1"
                                                        port:port
                                                    username:username
                                                    password:password];
    server.delegate = delegate;
    NSError *startError = nil;
    XCTAssertTrue([server start:&startError]);
    XCTAssertNil(startError);

    NSString *streamURL = server.streamURL;
    XCTestExpectation *staleChallengeReceived = [self expectationWithDescription:@"Fresh nonce challenge received"];
    XCTestExpectation *retryAuthenticated = [self expectationWithDescription:@"Fresh nonce retry authenticated"];
    XCTestExpectation *clientClosed = [self expectationWithDescription:@"Reconnect client closed"];
    dispatch_semaphore_t retryGate = dispatch_semaphore_create(0);
    dispatch_semaphore_t closeGate = dispatch_semaphore_create(0);
    __block BOOL firstConnectionAuthenticated = NO;
    __block NSString *staleResponse = nil;
    __block NSString *firstNonce = nil;
    __block NSString *freshNonce = nil;
    __block NSString *retryResponse = nil;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            int firstSocket = HARTSPConnectToLoopback(port);
            NSString *request = [NSString stringWithFormat:
                @"DESCRIBE %@ RTSP/1.0\r\nCSeq: 1\r\nAccept: application/sdp\r\n\r\n", streamURL];
            NSString *challengeResponse = nil;
            NSString *authenticatedResponse = nil;
            if (firstSocket >= 0 && HARTSPWriteString(firstSocket, request)) {
                challengeResponse = HARTSPReadResponse(firstSocket);
                NSString *challenge = HARTSPHeaderValue(challengeResponse, @"WWW-Authenticate");
                firstNonce = HARTSPQuotedChallengeValue(challenge, @"nonce");
                NSString *authorization = HARTSPDigestAuthorization(
                    @"DESCRIBE", streamURL, username, password, firstNonce ?: @"");
                request = [NSString stringWithFormat:
                    @"DESCRIBE %@ RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\nAuthorization: %@\r\n\r\n",
                    streamURL, authorization];
                if (HARTSPWriteString(firstSocket, request)) {
                    authenticatedResponse = HARTSPReadResponse(firstSocket);
                }
            }
            firstConnectionAuthenticated = [authenticatedResponse hasPrefix:@"RTSP/1.0 200 OK"];
            if (firstSocket >= 0) close(firstSocket);

            int reconnectSocket = HARTSPConnectToLoopback(port);
            NSString *cachedAuthorization = HARTSPDigestAuthorization(
                @"DESCRIBE", streamURL, username, password, firstNonce ?: @"");
            request = [NSString stringWithFormat:
                @"DESCRIBE %@ RTSP/1.0\r\nCSeq: 1\r\nAccept: application/sdp\r\nAuthorization: %@\r\n\r\n",
                streamURL, cachedAuthorization];
            NSString *localStaleResponse = nil;
            if (reconnectSocket >= 0 && HARTSPWriteString(reconnectSocket, request)) {
                localStaleResponse = HARTSPReadResponse(reconnectSocket);
            }
            NSString *freshChallenge = HARTSPHeaderValue(localStaleResponse, @"WWW-Authenticate");
            NSString *localFreshNonce = HARTSPQuotedChallengeValue(freshChallenge, @"nonce");
            dispatch_async(dispatch_get_main_queue(), ^{
                staleResponse = localStaleResponse;
                freshNonce = localFreshNonce;
                [staleChallengeReceived fulfill];
            });

            dispatch_semaphore_wait(retryGate,
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)));
            NSString *localRetryResponse = nil;
            if (reconnectSocket >= 0 && localFreshNonce.length) {
                NSString *freshAuthorization = HARTSPDigestAuthorization(
                    @"DESCRIBE", streamURL, username, password, localFreshNonce);
                request = [NSString stringWithFormat:
                    @"DESCRIBE %@ RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\nAuthorization: %@\r\n\r\n",
                    streamURL, freshAuthorization];
                if (HARTSPWriteString(reconnectSocket, request)) {
                    localRetryResponse = HARTSPReadResponse(reconnectSocket);
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                retryResponse = localRetryResponse;
                [retryAuthenticated fulfill];
            });

            dispatch_semaphore_wait(closeGate,
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)));
            if (reconnectSocket >= 0) close(reconnectSocket);
            dispatch_async(dispatch_get_main_queue(), ^{ [clientClosed fulfill]; });
        }
    });

    [self waitForExpectations:@[staleChallengeReceived] timeout:8.0];
    XCTAssertTrue(firstConnectionAuthenticated);
    XCTAssertTrue([staleResponse hasPrefix:@"RTSP/1.0 401 Unauthorized"]);
    NSString *challenge = [HARTSPHeaderValue(staleResponse, @"WWW-Authenticate") lowercaseString];
    XCTAssertTrue([challenge containsString:@"stale=true"]);
    XCTAssertGreaterThan(freshNonce.length, (NSUInteger)0);
    XCTAssertNotEqualObjects(freshNonce, firstNonce);
    XCTAssertEqual(server.clientCount, (NSUInteger)0);
    XCTAssertEqual(delegate.mediaConfigurationRequestCount, (NSUInteger)1);

    dispatch_semaphore_signal(retryGate);
    [self waitForExpectations:@[retryAuthenticated] timeout:5.0];
    XCTAssertTrue([retryResponse hasPrefix:@"RTSP/1.0 200 OK"]);
    XCTAssertEqual(server.clientCount, (NSUInteger)1);
    XCTAssertEqual(delegate.mediaConfigurationRequestCount, (NSUInteger)1);

    dispatch_semaphore_signal(closeGate);
    [self waitForExpectations:@[clientClosed] timeout:5.0];
    [server stop];
}

- (void)testRTSPMalformedAndOversizedRequestsFailClosedWithoutMediaDemand {
    uint16_t port = HARTSPAvailableLoopbackPort();
    XCTAssertNotEqual(port, (uint16_t)0);
    HARTSPServerDelegateSpy *delegate = [[HARTSPServerDelegateSpy alloc] init];
    HARTSPServer *server = [[HARTSPServer alloc] initWithHost:@"127.0.0.1"
                                                        port:port
                                                    username:@"hadashboard"
                                                    password:@"correct-password"];
    server.delegate = delegate;
    NSError *startError = nil;
    XCTAssertTrue([server start:&startError]);
    XCTAssertNil(startError);

    NSString *streamURL = server.streamURL;
    XCTestExpectation *responsesReceived = [self expectationWithDescription:@"Rejected request responses received"];
    __block BOOL malformedClientConnected = NO;
    __block BOOL oversizedClientConnected = NO;
    __block NSString *malformedResponse = nil;
    __block NSString *oversizedResponse = nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            int malformedSocket = HARTSPConnectToLoopback(port);
            NSString *localMalformedResponse = nil;
            if (malformedSocket >= 0) {
                NSString *request = [NSString stringWithFormat:
                                     @"DESCRIBE %@ RTSP/1.0\r\nAccept: application/sdp\r\n\r\n", streamURL];
                if (HARTSPWriteString(malformedSocket, request)) {
                    localMalformedResponse = HARTSPReadResponse(malformedSocket);
                }
                close(malformedSocket);
            }

            int oversizedSocket = HARTSPConnectToLoopback(port);
            NSString *localOversizedResponse = nil;
            if (oversizedSocket >= 0) {
                NSMutableString *request = [NSMutableString stringWithFormat:
                                            @"DESCRIBE %@ RTSP/1.0\r\nCSeq: 1\r\nX-Fill: ", streamURL];
                [request appendString:[@"x" stringByPaddingToLength:(17 * 1024)
                                                           withString:@"x"
                                                      startingAtIndex:0]];
                [request appendString:@"\r\n\r\n"];
                HARTSPWriteString(oversizedSocket, request);
                localOversizedResponse = HARTSPReadResponse(oversizedSocket);
                close(oversizedSocket);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                malformedClientConnected = malformedSocket >= 0;
                oversizedClientConnected = oversizedSocket >= 0;
                malformedResponse = localMalformedResponse;
                oversizedResponse = localOversizedResponse;
                [responsesReceived fulfill];
            });
        }
    });

    [self waitForExpectations:@[responsesReceived] timeout:8.0];
    XCTAssertTrue(malformedClientConnected);
    XCTAssertTrue(oversizedClientConnected);
    XCTAssertTrue([malformedResponse hasPrefix:@"RTSP/1.0 400 Bad Request"]);
    XCTAssertTrue([oversizedResponse hasPrefix:@"RTSP/1.0 413 Request Entity Too Large"]);
    XCTAssertEqual(server.clientCount, (NSUInteger)0);
    XCTAssertEqual(server.playingClientCount, (NSUInteger)0);
    XCTAssertEqual(delegate.maximumMediaClientCount, (NSUInteger)0);
    XCTAssertEqual(delegate.mediaConfigurationRequestCount, (NSUInteger)0);
    XCTAssertEqual(delegate.keyFrameRequestCount, (NSUInteger)0);
    XCTAssertNil(delegate.serverError);
    [server stop];
}

- (void)testUnauthenticatedOptionsCannotExtendAuthenticationDeadline {
    uint16_t port = HARTSPAvailableLoopbackPort();
    XCTAssertNotEqual(port, (uint16_t)0);
    HARTSPServerDelegateSpy *delegate = [[HARTSPServerDelegateSpy alloc] init];
    HARTSPServer *server = [[HARTSPServer alloc] initWithHost:@"127.0.0.1"
                                                        port:port
                                                    username:@"hadashboard"
                                                    password:@"correct-password"];
    server.delegate = delegate;
    NSError *startError = nil;
    XCTAssertTrue([server start:&startError]);
    XCTAssertNil(startError);

    NSString *streamURL = server.streamURL;
    XCTestExpectation *deadlineReached = [self expectationWithDescription:
        @"Unauthenticated connection closed despite OPTIONS activity"];
    __block NSUInteger successfulOptions = 0;
    __block BOOL connectionClosed = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            int socketDescriptor = HARTSPConnectToLoopback(port);
            if (socketDescriptor >= 0) {
                for (NSUInteger index = 1; index <= 8; index++) {
                    NSString *request = [NSString stringWithFormat:
                        @"OPTIONS %@ RTSP/1.0\r\nCSeq: %lu\r\n\r\n",
                        streamURL, (unsigned long)index];
                    if (!HARTSPWriteString(socketDescriptor, request)) {
                        connectionClosed = YES;
                        break;
                    }
                    NSString *response = HARTSPReadResponse(socketDescriptor);
                    if (![response hasPrefix:@"RTSP/1.0 200 OK"]) {
                        connectionClosed = YES;
                        break;
                    }
                    successfulOptions++;
                    [NSThread sleepForTimeInterval:1.0];
                }
                close(socketDescriptor);
            }
            dispatch_async(dispatch_get_main_queue(), ^{ [deadlineReached fulfill]; });
        }
    });

    [self waitForExpectations:@[deadlineReached] timeout:10.0];
    XCTAssertTrue(connectionClosed);
    XCTAssertGreaterThanOrEqual(successfulOptions, (NSUInteger)3);
    XCTAssertLessThan(successfulOptions, (NSUInteger)8);
    XCTAssertEqual(server.clientCount, (NSUInteger)0);
    XCTAssertEqual(delegate.maximumMediaClientCount, (NSUInteger)0);
    [server stop];
}

- (void)testEveryLifecycleTriggerStops {
    for (NSInteger trigger = HAStreamingStopTriggerUser;
         trigger <= HAStreamingStopTriggerCaptureInterrupted;
         trigger++) {
        XCTAssertTrue([HAStreamingManager shouldStopForTrigger:(HAStreamingStopTrigger)trigger]);
    }
}

- (void)testAudioConfigurationIsPublishedBeforeEnoughPCMExistsForAnAACPacket {
    HAStreamingManager *manager = [[HAStreamingManager alloc] init];
    HARTSPAudioConfigurationSpy *server = [[HARTSPAudioConfigurationSpy alloc]
        initWithHost:@"127.0.0.1" port:18554 username:@"hadashboard" password:@"test-password"];
    server.configurationExpectation = [self expectationWithDescription:
        @"AAC configuration published before first encoded packet"];
    [manager setValue:@YES forKey:@"streaming"];
    [manager setValue:server forKey:@"primaryRTSPServer"];

    CMSampleBufferRef sampleBuffer = HAStreamingCreateMonoPCMBuffer(1);
    XCTAssertNotEqual(sampleBuffer, NULL);
    if (sampleBuffer) {
        [manager encodeAudio:sampleBuffer];
        CFRelease(sampleBuffer);
    }

    [self waitForExpectations:@[server.configurationExpectation] timeout:2.0];
    const uint8_t expectedConfiguration[] = {0x11, 0x88};
    XCTAssertEqualObjects(server.audioConfiguration,
        [NSData dataWithBytes:expectedConfiguration length:sizeof(expectedConfiguration)]);
    XCTAssertEqual(server.audioChannels, (NSUInteger)1);
    XCTAssertEqual(server.audioSampleRate, (NSUInteger)48000);
    XCTAssertEqual(server.audioSampleCount, (NSUInteger)0);

    [manager setValue:@NO forKey:@"streaming"];
    [manager setValue:nil forKey:@"primaryRTSPServer"];
}

- (void)testAACEncoderAccumulatesSubpacketPCMUntilOnePacketIsReady {
    CMSampleBufferRef sampleBuffer = HAStreamingCreateMonoPCMBuffer(256);
    XCTAssertNotEqual(sampleBuffer, NULL);
    if (!sampleBuffer) return;

    NSError *initializationError = nil;
    HAAACEncoder *encoder = [[HAAACEncoder alloc]
        initWithInputFormat:(CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer)
        error:&initializationError];
    XCTAssertNotNil(encoder);
    XCTAssertNil(initializationError);

    NSData *encodedPacket = nil;
    for (NSUInteger index = 0; index < 4; index++) {
        NSError *encodingError = nil;
        encodedPacket = [encoder encodeSampleBuffer:sampleBuffer error:&encodingError];
        XCTAssertNil(encodingError);
        if (index < 3) XCTAssertNil(encodedPacket);
    }
    XCTAssertGreaterThan(encodedPacket.length, (NSUInteger)0);
    CFRelease(sampleBuffer);
}

- (void)testAACEncoderContinuesAfterTemporaryLiveInputExhaustion {
    CMSampleBufferRef sampleBuffer = HAStreamingCreateMonoPCMBuffer(1024);
    XCTAssertNotEqual(sampleBuffer, NULL);
    if (!sampleBuffer) return;

    NSError *initializationError = nil;
    HAAACEncoder *encoder = [[HAAACEncoder alloc]
        initWithInputFormat:(CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer)
        error:&initializationError];
    XCTAssertNotNil(encoder);
    XCTAssertNil(initializationError);

    NSUInteger encodedPacketCount = 0;
    for (NSUInteger index = 0; index < 6; index++) {
        NSError *encodingError = nil;
        NSData *packet = [encoder encodeSampleBuffer:sampleBuffer error:&encodingError];
        XCTAssertNil(encodingError);
        if (packet.length > 0) encodedPacketCount++;
    }
    // Returning 0/noErr from the input callback permanently finalized the
    // converter after its first packet on iOS 10. Live exhaustion must leave
    // it capable of producing subsequent AAC packets.
    XCTAssertGreaterThan(encodedPacketCount, (NSUInteger)1);
    CFRelease(sampleBuffer);
}

- (void)testStoppingDrainsAnInFlightAudioCallbackBeforeClearingAACState {
    HAStreamingManager *manager = [[HAStreamingManager alloc] init];
    dispatch_semaphore_t callbackStarted = dispatch_semaphore_create(0);
    dispatch_semaphore_t allowCallbackToFinish = dispatch_semaphore_create(0);
    dispatch_semaphore_t clearStarted = dispatch_semaphore_create(0);
    dispatch_semaphore_t clearFinished = dispatch_semaphore_create(0);

    dispatch_async(manager.audioCaptureQueue, ^{
        dispatch_semaphore_signal(callbackStarted);
        dispatch_semaphore_wait(allowCallbackToFinish, DISPATCH_TIME_FOREVER);
        manager.audioEncoder = (HAAACEncoder *)[[NSObject alloc] init];
        manager.publishedAudioConfiguration = [NSData dataWithBytes:"\x12\x10" length:2];
    });
    XCTAssertEqual(dispatch_semaphore_wait(callbackStarted,
        dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0L);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dispatch_semaphore_signal(clearStarted);
        [manager clearMediaState];
        dispatch_semaphore_signal(clearFinished);
    });
    XCTAssertEqual(dispatch_semaphore_wait(clearStarted,
        dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0L);
    XCTAssertNotEqual(dispatch_semaphore_wait(clearFinished, DISPATCH_TIME_NOW), 0L,
                      @"Clear must wait for the callback that already passed the capture guard");

    dispatch_semaphore_signal(allowCallbackToFinish);
    XCTAssertEqual(dispatch_semaphore_wait(clearFinished,
        dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0L);
    XCTAssertNil(manager.audioEncoder);
    XCTAssertNil(manager.publishedAudioConfiguration);
}

- (void)testAuthenticatedHTTPRedirectOriginComparisonIsStrict {
    NSURL *implicitHTTPS = [NSURL URLWithString:@"https://ha.example/api/config"];
    NSURL *explicitHTTPS = [NSURL URLWithString:@"https://HA.EXAMPLE:443/other"];
    NSURL *differentScheme = [NSURL URLWithString:@"http://ha.example/api/config"];
    NSURL *differentHost = [NSURL URLWithString:@"https://other.example/api/config"];
    NSURL *differentPort = [NSURL URLWithString:@"https://ha.example:8443/api/config"];

    XCTAssertTrue([HAURLSessionRedirectGuard URL:implicitHTTPS
                             sharesOriginWithURL:explicitHTTPS]);
    XCTAssertFalse([HAURLSessionRedirectGuard URL:implicitHTTPS
                              sharesOriginWithURL:differentScheme]);
    XCTAssertFalse([HAURLSessionRedirectGuard URL:implicitHTTPS
                              sharesOriginWithURL:differentHost]);
    XCTAssertFalse([HAURLSessionRedirectGuard URL:implicitHTTPS
                              sharesOriginWithURL:differentPort]);
}

- (void)testAPIClientRejectsAnInitialCrossOriginPathWithoutSendingIt {
    HAAPIClient *client = [[HAAPIClient alloc]
        initWithBaseURL:[NSURL URLWithString:@"https://ha.example/api"] token:@"test-token"];
    XCTestExpectation *rejected = [self expectationWithDescription:@"Cross-origin path rejected"];
    [client getJSONAtPath:@"https://other.example/credential-target"
               completion:^(id response, NSError *error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, (NSInteger)-5);
        [rejected fulfill];
    }];
    [self waitForExpectations:@[rejected] timeout:1.0];
    [client cancelAllRequests];
}

- (void)testCameraRegistrationUsesLongerTimeoutsAndContinuousCappedRetriesWithoutSleeping {
    HAAPIClient *standardClient = [[HAAPIClient alloc]
        initWithBaseURL:[NSURL URLWithString:@"https://ha.example/api"] token:@"test-token"];
    XCTAssertEqualWithAccuracy(standardClient.requestTimeoutInterval, 15.0, 0.001);
    XCTAssertEqualWithAccuracy(standardClient.resourceTimeoutInterval, 30.0, 0.001);
    [standardClient cancelAllRequests];

    NSMutableArray<HACameraRegistrationRetryTestClient *> *clients = [NSMutableArray array];
    NSMutableArray<NSNumber *> *requestTimeouts = [NSMutableArray array];
    NSMutableArray<NSNumber *> *resourceTimeouts = [NSMutableArray array];
    NSMutableArray<NSNumber *> *retryDelays = [NSMutableArray array];
    NSMutableArray *scheduledBlocks = [NSMutableArray array];
    __block NSUInteger cancelledTokenCount = 0;

    HACameraRegistrationTestAPIClientFactory factory =
        ^HAAPIClient *(NSURL *baseURL, NSString *token,
                       NSTimeInterval requestTimeout, NSTimeInterval resourceTimeout) {
        (void)baseURL;
        (void)token;
        [requestTimeouts addObject:@(requestTimeout)];
        [resourceTimeouts addObject:@(resourceTimeout)];
        HACameraRegistrationRetryTestClient *client = [[HACameraRegistrationRetryTestClient alloc] init];
        [clients addObject:client];
        return client;
    };
    HACameraRegistrationTestRetryScheduler scheduler =
        ^id(NSTimeInterval delay, dispatch_block_t block) {
        NSObject *token = [[NSObject alloc] init];
        [retryDelays addObject:@(delay)];
        [scheduledBlocks addObject:[block copy]];
        return token;
    };
    HACameraRegistrationTestRetryCanceller canceller = ^(id token) {
        if (token) cancelledTokenCount++;
    };

    HACameraRegistrationRetryTestManager *manager =
        [[HACameraRegistrationRetryTestManager alloc] initWithAPIClientFactory:factory
                                                                 scheduleRetry:scheduler
                                                          cancelScheduledRetry:canceller];
    manager.allowRegistrationToContinue = YES;
    [manager setValue:@YES forKey:@"registering"];
    [manager setValue:@[@"rtsp://192.0.2.10:8554/live"] forKey:@"pendingURLs"];
    [manager setValue:@"hadashboard" forKey:@"username"];
    [manager setValue:@"test-password" forKey:@"password"];
    [manager setValue:@"test-revision" forKey:@"credentialRevision"];
    [manager setValue:@30 forKey:@"framesPerSecond"];

    [manager beginRegistrationAttempt];
    XCTAssertTrue(manager.isRegistering);
    XCTAssertTrue(manager.isRetryScheduled);
    XCTAssertEqual(manager.retryAttempt, (NSUInteger)1);
    XCTAssertEqualObjects(retryDelays, (@[@2.0]));
    XCTAssertEqual(clients.count, (NSUInteger)1);
    XCTAssertEqual(clients.firstObject.deleteCount, (NSUInteger)1);
    XCTAssertEqualObjects(clients.firstObject.deletedPath,
                          @"config/config_entries/flow/test-camera-flow");

    for (NSUInteger index = 0; index < 6; index++) {
        dispatch_block_t scheduled = scheduledBlocks[index];
        scheduled();
    }

    XCTAssertTrue(manager.isRegistering);
    XCTAssertTrue(manager.isRetryScheduled);
    XCTAssertEqual(manager.retryAttempt, (NSUInteger)7);
    XCTAssertEqualObjects(retryDelays, (@[@2.0, @4.0, @8.0, @16.0, @32.0, @60.0, @60.0]));
    XCTAssertEqual(clients.count, (NSUInteger)7);

    // An effectively indefinite retry sequence saturates its display counter
    // and delay instead of overflowing an exponential shift.
    [manager setValue:@(NSUIntegerMax) forKey:@"retryAttempt"];
    dispatch_block_t saturatedRetry = scheduledBlocks[6];
    saturatedRetry();
    XCTAssertEqual(manager.retryAttempt, NSUIntegerMax);
    XCTAssertEqualObjects(retryDelays.lastObject, @60.0);
    XCTAssertEqual(clients.count, (NSUInteger)8);
    XCTAssertEqualObjects(requestTimeouts, (@[@75.0, @75.0, @75.0, @75.0, @75.0, @75.0, @75.0, @75.0]));
    XCTAssertEqualObjects(resourceTimeouts, (@[@120.0, @120.0, @120.0, @120.0, @120.0, @120.0, @120.0, @120.0]));
    XCTAssertEqualObjects(manager.lastError.domain, NSURLErrorDomain);
    XCTAssertEqual(manager.lastError.code, (NSInteger)NSURLErrorTimedOut);

    [manager cancelRegistration];
    XCTAssertFalse(manager.isRegistering);
    XCTAssertFalse(manager.isRetryScheduled);
    XCTAssertEqual(manager.retryAttempt, (NSUInteger)0);
    XCTAssertEqual(cancelledTokenCount, (NSUInteger)1);
    for (HACameraRegistrationRetryTestClient *client in clients) {
        XCTAssertTrue(client.isCancelledForTesting);
        XCTAssertEqual(client.getCount, (NSUInteger)1);
        XCTAssertEqual(client.postCount, (NSUInteger)2);
        XCTAssertEqual(client.deleteCount, (NSUInteger)1);
    }
}

- (void)testChangedCredentialRevisionSupersedesScheduledRetryAndInvalidatesOldTimer {
    NSMutableArray<HACameraRegistrationRetryTestClient *> *clients = [NSMutableArray array];
    NSMutableArray *scheduledBlocks = [NSMutableArray array];
    NSMutableArray *scheduledTokens = [NSMutableArray array];
    NSMutableSet *cancelledTokens = [NSMutableSet set];
    HACameraRegistrationTestAPIClientFactory factory =
        ^HAAPIClient *(NSURL *baseURL, NSString *token,
                       NSTimeInterval requestTimeout, NSTimeInterval resourceTimeout) {
        (void)baseURL; (void)token; (void)requestTimeout; (void)resourceTimeout;
        HACameraRegistrationRetryTestClient *client = [[HACameraRegistrationRetryTestClient alloc] init];
        [clients addObject:client];
        return client;
    };
    HACameraRegistrationRetryTestManager *manager =
        [[HACameraRegistrationRetryTestManager alloc] initWithAPIClientFactory:factory
        scheduleRetry:^id(NSTimeInterval delay, dispatch_block_t block) {
            (void)delay;
            NSObject *token = [[NSObject alloc] init];
            [scheduledBlocks addObject:[block copy]];
            [scheduledTokens addObject:token];
            return token;
        } cancelScheduledRetry:^(id token) {
            if (token) [cancelledTokens addObject:token];
        }];
    manager.allowRegistrationToContinue = YES;
    manager.streamListenerArmedForTesting = YES;
    NSArray<NSString *> *URLs = @[@"rtsp://192.0.2.10:8554/live"];

    [manager ensureCameraEntriesForStreamURLs:URLs
                                   deviceName:@"Test Device"
                                     username:@"hadashboard"
                                     password:@"test-password"
                           credentialRevision:@"old-revision"
                              framesPerSecond:30
                                   completion:nil];
    XCTAssertEqual(clients.count, (NSUInteger)1);
    XCTAssertTrue(manager.isRetryScheduled);
    dispatch_block_t oldRetry = scheduledBlocks[0];
    id oldToken = scheduledTokens[0];

    // An identical lifecycle request coalesces with the active work.
    [manager ensureCameraEntriesForStreamURLs:URLs
                                   deviceName:@"Test Device"
                                     username:@"hadashboard"
                                     password:@"test-password"
                           credentialRevision:@"old-revision"
                              framesPerSecond:30
                                   completion:nil];
    XCTAssertEqual(clients.count, (NSUInteger)1);

    // Password rotation changes the revision and must replace the active
    // generation immediately instead of sitting behind its infinite retry.
    [manager ensureCameraEntriesForStreamURLs:URLs
                                   deviceName:@"Test Device"
                                     username:@"hadashboard"
                                     password:@"new-test-password"
                           credentialRevision:@"new-revision"
                              framesPerSecond:30
                                   completion:nil];
    XCTAssertEqual(clients.count, (NSUInteger)2);
    XCTAssertTrue(clients[0].isCancelledForTesting);
    XCTAssertTrue([cancelledTokens containsObject:oldToken]);
    XCTAssertEqualObjects([manager valueForKey:@"credentialRevision"], @"new-revision");
    XCTAssertEqual(manager.retryAttempt, (NSUInteger)1);
    dispatch_block_t newRetry = scheduledBlocks[1];

    oldRetry();
    XCTAssertEqual(clients.count, (NSUInteger)2);
    XCTAssertEqualObjects([manager valueForKey:@"credentialRevision"], @"new-revision");

    newRetry();
    XCTAssertEqual(clients.count, (NSUInteger)3);
    XCTAssertEqualObjects([manager valueForKey:@"credentialRevision"], @"new-revision");
    [manager cancelRegistration];
}

- (void)testStoppingTheStreamCancelsAndInvalidatesAScheduledCameraRegistrationRetry {
    __block NSUInteger clientCount = 0;
    __block dispatch_block_t scheduledBlock = nil;
    __block id scheduledToken = nil;
    __block id cancelledToken = nil;
    HACameraRegistrationRetryTestClient *firstClient = [[HACameraRegistrationRetryTestClient alloc] init];
    HACameraRegistrationTestAPIClientFactory factory =
        ^HAAPIClient *(NSURL *baseURL, NSString *token,
                       NSTimeInterval requestTimeout, NSTimeInterval resourceTimeout) {
        (void)baseURL; (void)token; (void)requestTimeout; (void)resourceTimeout;
        clientCount++;
        return firstClient;
    };
    HACameraRegistrationRetryTestManager *manager =
        [[HACameraRegistrationRetryTestManager alloc] initWithAPIClientFactory:factory
        scheduleRetry:^id(NSTimeInterval delay, dispatch_block_t block) {
            XCTAssertEqualWithAccuracy(delay, 2.0, 0.001);
            scheduledBlock = [block copy];
            scheduledToken = [[NSObject alloc] init];
            return scheduledToken;
        } cancelScheduledRetry:^(id token) {
            cancelledToken = token;
        }];
    manager.allowRegistrationToContinue = YES;
    manager.streamListenerArmedForTesting = YES;
    [manager setValue:@YES forKey:@"registering"];
    [manager setValue:@[@"rtsp://192.0.2.10:8554/live"] forKey:@"pendingURLs"];
    [manager setValue:@"hadashboard" forKey:@"username"];
    [manager setValue:@"test-password" forKey:@"password"];
    [manager setValue:@"test-revision" forKey:@"credentialRevision"];
    [manager setValue:@30 forKey:@"framesPerSecond"];

    [manager beginRegistrationAttempt];
    XCTAssertTrue(manager.isRetryScheduled);
    XCTAssertNotNil(scheduledBlock);
    manager.streamListenerArmedForTesting = NO;
    [manager streamingStateDidChange:nil];
    XCTAssertEqual(cancelledToken, scheduledToken);
    XCTAssertTrue(firstClient.isCancelledForTesting);
    XCTAssertFalse(manager.isRegistering);
    XCTAssertFalse(manager.isRetryScheduled);

    scheduledBlock();
    XCTAssertEqual(clientCount, (NSUInteger)1);
    XCTAssertFalse(manager.isRegistering);
}

- (void)testCameraRegistrationPayloadUsesTheSelectedStreamFrameRate {
    HACameraRegistrationManager *manager = [[HACameraRegistrationManager alloc] init];
    [manager setValue:@"hadashboard" forKey:@"username"];
    [manager setValue:@"test-stream-password" forKey:@"password"];
    [manager setValue:@30 forKey:@"framesPerSecond"];

    NSString *streamURL = @"rtsp://192.0.2.10:8554/live";
    NSDictionary *input = [manager cameraConfigurationInputForURL:streamURL optionsFlow:YES];
    NSDictionary *advanced = input[@"advanced"];

    XCTAssertEqualObjects(input[@"stream_source"], streamURL);
    XCTAssertEqualObjects(input[@"username"], @"hadashboard");
    XCTAssertEqualObjects(input[@"password"], @"test-stream-password");
    XCTAssertEqualObjects(advanced[@"authentication"], @"digest");
    XCTAssertEqualObjects(advanced[@"rtsp_transport"], @"tcp");
    XCTAssertEqualObjects(advanced[@"framerate"], @30);
    XCTAssertEqualObjects(advanced[@"limit_refetch_to_url_change"], @NO);
    XCTAssertEqualObjects(advanced[@"use_wallclock_as_timestamps"], @NO);
}

- (void)testCameraRegistrationAllowsLocalHTTPWithoutConsentState {
    NSString *legacyConsentKey = @"ha_camera_insecure_consent_origin";
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id previousValue = [defaults objectForKey:legacyConsentKey];
    [defaults setObject:@"http|different.local|8123" forKey:legacyConsentKey];

    @try {
        HACameraRegistrationManager *manager = [[HACameraRegistrationManager alloc] init];
        XCTAssertNil([defaults objectForKey:legacyConsentKey]);
        NSArray<NSString *> *allowedURLs = @[
            @"http://localhost:8123/api",
            @"http://ha.local:8123/api",
            @"http://127.0.0.1:8123/api",
            @"http://10.20.30.40:8123/api",
            @"http://172.16.0.1:8123/api",
            @"http://172.31.255.254:8123/api",
            @"http://192.168.1.2:8123/api",
            @"http://169.254.10.20:8123/api",
            @"http://[::1]:8123/api",
            @"http://[fe80::1234]:8123/api",
            @"http://[fd12:3456::1]:8123/api",
        ];
        for (NSString *URLString in allowedURLs) {
            XCTAssertNil([manager cameraCredentialTransportErrorForURL:
                [NSURL URLWithString:URLString]], @"Expected local HTTP to be allowed: %@", URLString);
        }
        XCTAssertNil([defaults objectForKey:legacyConsentKey]);
    } @finally {
        if (previousValue) [defaults setObject:previousValue forKey:legacyConsentKey];
        else [defaults removeObjectForKey:legacyConsentKey];
    }
}

- (void)testCameraRegistrationRefusesNonLocalHTTP {
    HACameraRegistrationManager *manager = [[HACameraRegistrationManager alloc] init];
    NSArray<NSString *> *blockedURLs = @[
        @"http://example.com:8123/api",
        @"http://8.8.8.8:8123/api",
        @"http://172.15.255.255:8123/api",
        @"http://172.32.0.1:8123/api",
        @"http://192.0.2.10:8123/api",
        @"http://[2001:db8::1]:8123/api",
    ];
    for (NSString *URLString in blockedURLs) {
        NSError *error = [manager cameraCredentialTransportErrorForURL:
            [NSURL URLWithString:URLString]];
        XCTAssertNotNil(error, @"Expected non-local HTTP to be refused: %@", URLString);
        XCTAssertTrue([error.localizedDescription containsString:@"must use HTTPS"]);
    }
}

- (void)testCameraRegistrationAllowsHTTPSWithoutHostRestriction {
    HACameraRegistrationManager *manager = [[HACameraRegistrationManager alloc] init];
    XCTAssertNil([manager cameraCredentialTransportErrorForURL:
        [NSURL URLWithString:@"https://ha.example:8123/api"]]);
    XCTAssertNil([manager cameraCredentialTransportErrorForURL:
        [NSURL URLWithString:@"https://203.0.113.10:8123/api"]]);
}

- (void)testAppOwnedCameraMissingRevisionOrFrameRateUsesOptionsFlow {
    NSString *entryKey = @"ha_camera_primary_entry_id";
    NSString *urlKey = @"ha_camera_primary_stream_url";
    NSString *revisionKey = @"ha_camera_primary_credential_revision";
    NSString *frameRateKey = @"ha_camera_primary_frames_per_second";
    NSArray<NSString *> *keys = @[entryKey, urlKey, revisionKey, frameRateKey];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *previousValues = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        id value = [defaults objectForKey:key];
        if (value) previousValues[key] = value;
    }

    @try {
        NSString *entryID = @"app-owned-camera-entry";
        NSString *streamURL = @"rtsp://192.0.2.10:8554/live";
        NSString *revision = @"current-credential-revision";
        HACameraRegistrationRouteSpy *manager = [[HACameraRegistrationRouteSpy alloc] init];
        [manager setValue:@[streamURL] forKey:@"pendingURLs"];
        [manager setValue:@[@{@"entry_id": entryID}] forKey:@"existingEntries"];
        [manager setValue:@0 forKey:@"currentIndex"];
        [manager setValue:revision forKey:@"credentialRevision"];
        [manager setValue:@30 forKey:@"framesPerSecond"];

        [defaults setObject:entryID forKey:entryKey];
        [defaults setObject:streamURL forKey:urlKey];
        [defaults removeObjectForKey:revisionKey];
        [defaults setInteger:30 forKey:frameRateKey];
        [manager processCurrentURL];
        XCTAssertEqualObjects(manager.updatedEntryID, entryID);
        XCTAssertNil(manager.acceptedEntryID);
        XCTAssertFalse(manager.createdEntry);

        manager.updatedEntryID = nil;
        [defaults setObject:revision forKey:revisionKey];
        [defaults removeObjectForKey:frameRateKey];
        [manager processCurrentURL];
        XCTAssertEqualObjects(manager.updatedEntryID, entryID);
        XCTAssertNil(manager.acceptedEntryID);
        XCTAssertFalse(manager.createdEntry);
    } @finally {
        for (NSString *key in keys) {
            id previousValue = previousValues[key];
            if (previousValue) [defaults setObject:previousValue forKey:key];
            else [defaults removeObjectForKey:key];
        }
        [defaults synchronize];
    }
}

- (void)testCameraRegistrationRejectsANonPositiveFrameRate {
    HACameraRegistrationManager *manager = [[HACameraRegistrationManager alloc] init];
    __block BOOL completed = NO;
    [manager ensureCameraEntriesForStreamURLs:@[@"rtsp://192.0.2.10:8554/live"]
                                   deviceName:@"Test Device"
                                     username:@"hadashboard"
                                     password:@"test-stream-password"
                           credentialRevision:@"test-revision"
                              framesPerSecond:0
                                   completion:^(BOOL success, NSError *error) {
        completed = YES;
        XCTAssertFalse(success);
        XCTAssertTrue([error.localizedDescription containsString:@"frame rate"]);
    }];
    XCTAssertTrue(completed);
}

- (void)testStreamingCompatibilityBoundaryIsExact {
    NSOperatingSystemVersion iOS933 = {9, 3, 3};
    NSOperatingSystemVersion iOS1032 = {10, 3, 2};
    NSOperatingSystemVersion iOS1033 = {10, 3, 3};
    NSOperatingSystemVersion iOS11 = {11, 0, 0};
    XCTAssertFalse([HAStreamingManager supportsOperatingSystemVersion:iOS933]);
    XCTAssertFalse([HAStreamingManager supportsOperatingSystemVersion:iOS1032]);
    XCTAssertTrue([HAStreamingManager supportsOperatingSystemVersion:iOS1033]);
    XCTAssertTrue([HAStreamingManager supportsOperatingSystemVersion:iOS11]);
}

- (void)testIOS10UsesAudioCompatibleVideoPresetsInsteadOfManualActiveFormat {
    NSOperatingSystemVersion iOS1033 = {10, 3, 3};
    NSOperatingSystemVersion iOS11 = {11, 0, 0};
    XCTAssertTrue([HAStreamingManager usesAudioCompatiblePresetForOperatingSystemVersion:iOS1033]);
    XCTAssertFalse([HAStreamingManager usesAudioCompatiblePresetForOperatingSystemVersion:iOS11]);
    XCTAssertEqualObjects(
        [HAStreamingManager preferredLegacySessionPresetsForQualityScale:0.0f].firstObject,
        AVCaptureSessionPreset640x480);
    XCTAssertEqualObjects(
        [HAStreamingManager preferredLegacySessionPresetsForQualityScale:0.5f].firstObject,
        AVCaptureSessionPreset1280x720);
    XCTAssertEqualObjects(
        [HAStreamingManager preferredLegacySessionPresetsForQualityScale:1.0f].firstObject,
        AVCaptureSessionPreset1920x1080);
}

- (void)testUnsupportedPlatformCannotRestoreOrArmStreaming {
    NSString *enabledKey = @"ha_local_camera_stream_enabled";
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id previousValue = [defaults objectForKey:enabledKey];
    [defaults setBool:YES forKey:enabledKey];

    HAUnsupportedStreamingManager *manager = [[HAUnsupportedStreamingManager alloc] init];
    XCTAssertFalse(manager.featureEnabled);
    XCTAssertFalse([defaults boolForKey:enabledKey]);

    __block BOOL completed = NO;
    [manager armLocalStreamWithCompletion:^(BOOL success, NSError *error) {
        completed = YES;
        XCTAssertFalse(success);
        XCTAssertNotNil(error);
    }];
    XCTAssertTrue(completed);
    XCTAssertFalse(manager.streaming);

    if (previousValue) [defaults setObject:previousValue forKey:enabledKey];
    else [defaults removeObjectForKey:enabledKey];
}

- (void)testLocalFeatureCanBeDisabledWithoutRelayConfiguration {
    HAStreamingManager *manager = HAStreamingManager.sharedManager;
    BOOL wasEnabled = manager.featureEnabled;
    NSError *error = nil;
    XCTAssertTrue([manager setFeatureEnabled:NO error:&error]);
    XCTAssertNil(error);
    XCTAssertFalse(manager.featureEnabled);
    XCTAssertTrue(manager.configured);
    if (wasEnabled) XCTAssertTrue([manager setFeatureEnabled:YES error:&error]);
}

@end
