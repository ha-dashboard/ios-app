#import "HARTSPServer.h"
#import "HALog.h"
#import <CFNetwork/CFNetwork.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <arpa/inet.h>
#import <errno.h>
#import <fcntl.h>
#import <limits.h>
#import <netinet/tcp.h>
#import <sys/socket.h>

static NSString *const HARTSPServerErrorDomain = @"HARTSPServerErrorDomain";
static NSString *const HARTSPAuthenticationRealm = @"HA Dashboard";
static const NSUInteger kHARTSPMaxRTPPayload = 1200;
static const NSUInteger kHARTSPMaxInputBytes = 16 * 1024;
static const NSUInteger kHARTSPMaxConnections = 8;
static const NSUInteger kHARTSPMaxAuthenticationFailures = 3;
static const NSUInteger kHARTSPMaxPendingOutputBytes = 1024 * 1024;
static const NSTimeInterval kHARTSPAuthenticationTimeout = 5.0;
static const NSTimeInterval kHARTSPClientIdleTimeout = 10.0;
static const NSTimeInterval kHARTSPOutputBackpressureTimeout = 2.0;

typedef ssize_t (^HARTSPSendFunction)(CFSocketNativeHandle socket,
                                      const void *bytes,
                                      size_t length,
                                      int *errorOut);

static NSString *HARTSPRandomNonce(void) {
    uint8_t bytes[16];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) return nil;
    NSMutableString *nonce = [NSMutableString stringWithCapacity:sizeof(bytes) * 2];
    for (NSUInteger index = 0; index < sizeof(bytes); index++) {
        [nonce appendFormat:@"%02x", bytes[index]];
    }
    return nonce;
}

static NSString *HARTSPMD5Hex(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data || data.length > UINT32_MAX) return nil;
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

static BOOL HARTSPConstantTimeEqualHex(NSString *left, NSString *right) {
    NSData *leftData = [[left lowercaseString] dataUsingEncoding:NSASCIIStringEncoding];
    NSData *rightData = [[right lowercaseString] dataUsingEncoding:NSASCIIStringEncoding];
    if (!leftData || !rightData || leftData.length != rightData.length) return NO;
    const uint8_t *leftBytes = leftData.bytes;
    const uint8_t *rightBytes = rightData.bytes;
    uint8_t difference = 0;
    for (NSUInteger index = 0; index < leftData.length; index++) {
        difference |= leftBytes[index] ^ rightBytes[index];
    }
    return difference == 0;
}

static NSDictionary<NSString *, NSString *> *HARTSPDigestParameters(NSString *authorization) {
    if (!authorization.length ||
        [authorization rangeOfString:@"Digest " options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location == NSNotFound) {
        return nil;
    }
    NSString *parameters = [authorization substringFromIndex:7];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSUInteger index = 0;
    while (index < parameters.length) {
        while (index < parameters.length &&
               ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[parameters characterAtIndex:index]] ||
                [parameters characterAtIndex:index] == ',')) index++;
        NSUInteger keyStart = index;
        while (index < parameters.length && [parameters characterAtIndex:index] != '=' &&
               [parameters characterAtIndex:index] != ',') index++;
        if (index >= parameters.length || [parameters characterAtIndex:index] != '=') return nil;
        NSString *key = [[[parameters substringWithRange:NSMakeRange(keyStart, index - keyStart)]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
        index++;
        while (index < parameters.length &&
               [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[parameters characterAtIndex:index]]) index++;
        NSMutableString *value = [NSMutableString string];
        if (index < parameters.length && [parameters characterAtIndex:index] == '"') {
            index++;
            BOOL closedQuote = NO;
            while (index < parameters.length) {
                unichar character = [parameters characterAtIndex:index++];
                if (character == '"') { closedQuote = YES; break; }
                if (character == '\\' && index < parameters.length) {
                    character = [parameters characterAtIndex:index++];
                }
                [value appendFormat:@"%C", character];
            }
            if (!closedQuote) return nil;
        } else {
            NSUInteger valueStart = index;
            while (index < parameters.length && [parameters characterAtIndex:index] != ',') index++;
            [value appendString:[[parameters substringWithRange:NSMakeRange(valueStart, index - valueStart)]
                                 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        }
        if (!key.length || !value.length || result[key]) return nil;
        result[key] = value;
        while (index < parameters.length && [parameters characterAtIndex:index] != ',') {
            if (![[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[parameters characterAtIndex:index]]) return nil;
            index++;
        }
    }
    return result;
}

static NSString *HARTSPResourcePath(NSString *uri) {
    if (!uri.length) return nil;
    NSURL *URL = [NSURL URLWithString:uri];
    if (!URL.scheme.length) return uri;
    NSString *path = URL.path.length ? URL.path : @"/";
    return URL.query.length ? [path stringByAppendingFormat:@"?%@", URL.query] : path;
}

static BOOL HARTSPURIMatchesRequest(NSString *digestURI, NSString *requestURI) {
    if ([digestURI isEqualToString:requestURI]) return YES;
    NSString *digestPath = HARTSPResourcePath(digestURI);
    NSString *requestPath = HARTSPResourcePath(requestURI);
    return digestPath.length && [digestPath isEqualToString:requestPath];
}

static BOOL HARTSPValidCSeq(NSString *cseq) {
    if (!cseq.length || cseq.length > 10) return NO;
    for (NSUInteger index = 0; index < cseq.length; index++) {
        unichar character = [cseq characterAtIndex:index];
        if (character < '0' || character > '9') return NO;
    }
    return YES;
}

static BOOL HARTSPParseUnsigned(NSString *value, NSUInteger maximum, NSUInteger *result) {
    if (!value.length || value.length > 20) return NO;
    unsigned long long parsed = 0;
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        if (character < '0' || character > '9') return NO;
        unsigned digit = (unsigned)(character - '0');
        if (parsed > (ULLONG_MAX - digit) / 10) return NO;
        parsed = parsed * 10 + digit;
    }
    if (parsed > maximum) return NO;
    if (result) *result = (NSUInteger)parsed;
    return YES;
}

@interface HARTSPClient : NSObject
@property (nonatomic, weak) HARTSPServer *server;
@property (nonatomic, strong) NSMutableData *inputBuffer;
@property (nonatomic, strong) NSMutableData *outputBuffer;
@property (nonatomic, assign) NSUInteger outputOffset;
@property (nonatomic, assign) CFAbsoluteTime outputBacklogStartedAt;
@property (nonatomic, assign) BOOL closeAfterOutputDrains;
@property (nonatomic, assign) CFSocketNativeHandle nativeSocket;
@property (nonatomic, assign) CFSocketRef socket;
@property (nonatomic, assign) CFRunLoopSourceRef socketSource;
@property (nonatomic, assign) BOOL closed;
@property (nonatomic, copy) NSString *sessionID;
@property (nonatomic, assign) BOOL videoSetup;
@property (nonatomic, assign) BOOL audioSetup;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, assign) uint8_t videoChannel;
@property (nonatomic, assign) uint8_t audioChannel;
@property (nonatomic, assign) uint16_t videoSequence;
@property (nonatomic, assign) uint16_t audioSequence;
@property (nonatomic, assign) uint32_t videoSSRC;
@property (nonatomic, assign) uint32_t audioSSRC;
@property (nonatomic, assign) BOOL loggedVideoPacket;
@property (nonatomic, assign) BOOL loggedAudioPacket;
@property (nonatomic, assign) BOOL needsVideoParameterSets;
@property (nonatomic, copy) NSString *pendingDescribeCSeq;
@property (nonatomic, assign, getter=isAuthenticated) BOOL authenticated;
@property (nonatomic, assign) BOOL mediaDemand;
@property (nonatomic, assign) NSUInteger authenticationFailures;
@property (nonatomic, copy) NSString *authenticationNonce;
@property (nonatomic, assign) CFAbsoluteTime connectedAt;
@property (nonatomic, assign) CFAbsoluteTime lastActivity;
@property (nonatomic, strong) NSTimer *idleTimer;
- (instancetype)initWithNativeSocket:(CFSocketNativeHandle)socket server:(HARTSPServer *)server;
- (void)close;
- (void)queue:(NSData *)data;
- (void)flushOutput;
- (void)closeAfterFlushingOutput;
- (NSUInteger)pendingOutputLength;
- (void)sendPendingDescriptionIfReady;
- (void)readAvailable;
- (void)parse;
- (void)respond:(NSString *)request;
- (BOOL)contentLengthInRequest:(NSString *)request length:(NSUInteger *)length;
- (BOOL)authenticateMethod:(NSString *)method URL:(NSString *)URL headers:(NSDictionary *)headers cseq:(NSString *)cseq;
- (void)markMediaDemand;
- (void)response:(NSInteger)status cseq:(NSString *)cseq headers:(NSDictionary *)headers body:(NSData *)body;
- (void)checkIdleTimer:(NSTimer *)timer;
@end

@interface HARTSPServer ()
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, copy, readwrite) NSString *authenticationUsername;
@property (nonatomic, copy) NSString *authenticationPassword;
@property (nonatomic, assign) CFSocketRef listener;
@property (nonatomic, assign) CFRunLoopSourceRef listenerSource;
@property (nonatomic, strong) NSMutableArray<HARTSPClient *> *clients;
@property (nonatomic, strong) NSData *avcConfiguration;
@property (nonatomic, strong) NSData *aacConfiguration;
@property (nonatomic, assign) NSUInteger audioChannels;
@property (nonatomic, assign) NSUInteger audioSampleRate;
@property (nonatomic, copy) NSString *spsBase64;
@property (nonatomic, copy) NSString *ppsBase64;
@property (nonatomic, strong) NSData *spsNAL;
@property (nonatomic, strong) NSData *ppsNAL;
@property (nonatomic, copy) NSString *profileLevelID;
@property (nonatomic, assign) BOOL hasVideoTimestamp;
@property (nonatomic, assign) BOOL hasAudioTimestamp;
@property (nonatomic, assign) uint32_t lastVideoTimestamp;
@property (nonatomic, assign) uint32_t lastAudioTimestamp;
@property (nonatomic, assign) uint32_t videoTimestampStep;
@property (nonatomic, assign, getter=isRunning) BOOL running;
@property (nonatomic, copy) HARTSPSendFunction sendFunctionForTesting;
@property (nonatomic, assign) NSUInteger maximumPendingOutputBytes;
- (void)addClient:(HARTSPClient *)client;
- (void)removeClient:(HARTSPClient *)client;
- (BOOL)canAcceptClient;
- (void)clientStateDidChange;
- (NSArray<HARTSPClient *> *)clientSnapshot;
- (NSString *)sessionDescription;
- (ssize_t)sendBytes:(const void *)bytes
              length:(size_t)length
              socket:(CFSocketNativeHandle)socket
               error:(int *)errorOut;
- (NSUInteger)pendingOutputByteCountForTesting;
- (void)flushPendingClientWritesForTesting;
@end

static void HARTSPAccept(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address,
                         const void *data, void *info) {
    (void)socket; (void)address;
    if (type != kCFSocketAcceptCallBack || !data) return;
    HARTSPServer *server = (__bridge HARTSPServer *)info;
    CFSocketNativeHandle nativeSocket = *(const CFSocketNativeHandle *)data;
    if (![server canAcceptClient]) {
        HALogW(@"rtsp", @"Port %u rejected a connection because the client limit was reached.", server.port);
        close(nativeSocket);
        return;
    }
    HARTSPClient *client = [[HARTSPClient alloc] initWithNativeSocket:nativeSocket server:server];
    if (!client) { close(nativeSocket); return; }
    [server addClient:client];
}

static void HARTSPSocketActivity(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address,
                                const void *data, void *info) {
    (void)socket; (void)address; (void)data;
    HARTSPClient *client = (__bridge HARTSPClient *)info;
    if (type == kCFSocketReadCallBack) {
        [client readAvailable];
    } else if (type == kCFSocketWriteCallBack) {
        [client flushOutput];
    }
}

@implementation HARTSPServer

- (instancetype)initWithHost:(NSString *)host
                         port:(uint16_t)port
                     username:(NSString *)username
                     password:(NSString *)password {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _authenticationUsername = [username copy];
        _authenticationPassword = [password copy];
        _clients = [NSMutableArray array];
        _maximumPendingOutputBytes = kHARTSPMaxPendingOutputBytes;
    }
    return self;
}

- (NSString *)streamURL { return self.running ? [NSString stringWithFormat:@"rtsp://%@:%u/live", self.host, self.port] : nil; }
- (NSArray<HARTSPClient *> *)clientSnapshot {
    @synchronized (self.clients) { return [self.clients copy]; }
}
- (NSUInteger)connectionCount {
    @synchronized (self.clients) { return self.clients.count; }
}
- (NSUInteger)clientCount {
    NSUInteger count = 0;
    for (HARTSPClient *client in [self clientSnapshot]) {
        if (client.isAuthenticated && client.mediaDemand && !client.closed) count++;
    }
    return count;
}
- (NSUInteger)playingClientCount {
    NSUInteger count = 0;
    for (HARTSPClient *client in [self clientSnapshot]) {
        if (client.isAuthenticated && client.playing && !client.closed) count++;
    }
    return count;
}

- (BOOL)start:(NSError **)error {
    if (self.running) return YES;
    if (!self.authenticationUsername.length || !self.authenticationPassword.length) {
        if (error) *error = [self error:@"RTSP authentication credentials are required."];
        return NO;
    }
    CFSocketContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    self.listener = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP,
        kCFSocketAcceptCallBack, HARTSPAccept, &context);
    if (!self.listener) { if (error) *error = [self error:@"Could not create the local RTSP listener."]; return NO; }
    int reuse = 1;
    setsockopt(CFSocketGetNative(self.listener), SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(self.port);
    if (inet_pton(AF_INET, self.host.UTF8String, &address.sin_addr) != 1) {
        CFRelease(self.listener); self.listener = NULL;
        if (error) *error = [self error:@"The selected local RTSP address is invalid."];
        return NO;
    }
    NSData *addressData = [NSData dataWithBytes:&address length:sizeof(address)];
    if (CFSocketSetAddress(self.listener, (__bridge CFDataRef)addressData) != kCFSocketSuccess) {
        CFRelease(self.listener); self.listener = NULL;
        if (error) *error = [self error:[NSString stringWithFormat:@"Port %u is unavailable for the local RTSP stream.", self.port]];
        return NO;
    }
    self.listenerSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, self.listener, 0);
    if (!self.listenerSource) {
        CFSocketInvalidate(self.listener);
        CFRelease(self.listener);
        self.listener = NULL;
        if (error) *error = [self error:@"Could not create the local RTSP listener source."];
        return NO;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), self.listenerSource, kCFRunLoopCommonModes);
    self.running = YES;
    return YES;
}

- (void)stop {
    for (HARTSPClient *client in [self clientSnapshot]) [client close];
    @synchronized (self.clients) { [self.clients removeAllObjects]; }
    if (self.listenerSource) { CFRunLoopRemoveSource(CFRunLoopGetMain(), self.listenerSource, kCFRunLoopCommonModes); CFRelease(self.listenerSource); self.listenerSource = NULL; }
    if (self.listener) { CFSocketInvalidate(self.listener); CFRelease(self.listener); self.listener = NULL; }
    self.running = NO;
}

- (BOOL)canAcceptClient { return self.running && self.connectionCount < kHARTSPMaxConnections; }
- (void)addClient:(HARTSPClient *)client {
    @synchronized (self.clients) { [self.clients addObject:client]; }
    HALogI(@"rtsp", @"Port %u client connected (%lu sockets, %lu media clients)", self.port,
           (unsigned long)self.connectionCount, (unsigned long)self.clientCount);
    [self.delegate rtspServerDidChangeClientCount:self];
}
- (void)removeClient:(HARTSPClient *)client {
    @synchronized (self.clients) {
        if (![self.clients containsObject:client]) return;
        [self.clients removeObject:client];
    }
    HALogI(@"rtsp", @"Port %u client disconnected (%lu sockets, %lu media clients)", self.port,
           (unsigned long)self.connectionCount, (unsigned long)self.clientCount);
    [self.delegate rtspServerDidChangeClientCount:self];
}
- (void)clientStateDidChange {
    HALogI(@"rtsp", @"Port %u client state changed (%lu media clients, %lu playing)", self.port,
           (unsigned long)self.clientCount, (unsigned long)self.playingClientCount);
    [self.delegate rtspServerDidChangeClientCount:self];
}

- (ssize_t)sendBytes:(const void *)bytes
              length:(size_t)length
              socket:(CFSocketNativeHandle)socket
               error:(int *)errorOut {
    if (errorOut) *errorOut = 0;
    if (self.sendFunctionForTesting) {
        return self.sendFunctionForTesting(socket, bytes, length, errorOut);
    }
    ssize_t sent = send(socket, bytes, length, 0);
    if (sent < 0 && errorOut) *errorOut = errno;
    return sent;
}

- (NSUInteger)pendingOutputByteCountForTesting {
    NSUInteger count = 0;
    for (HARTSPClient *client in [self clientSnapshot]) {
        count += client.pendingOutputLength;
    }
    return count;
}

- (void)flushPendingClientWritesForTesting {
    for (HARTSPClient *client in [self clientSnapshot]) [client flushOutput];
}

- (void)setVideoConfiguration:(NSData *)configuration {
    if ([self.avcConfiguration isEqualToData:configuration]) return;
    self.avcConfiguration = [configuration copy];
    const uint8_t *b = configuration.bytes;
    if (configuration.length < 11 || b[0] != 1) return;
    NSUInteger offset = 6;
    NSUInteger spsLength = ((NSUInteger)b[offset] << 8) | b[offset + 1]; offset += 2;
    if (offset + spsLength + 3 > configuration.length || spsLength < 4) return;
    NSData *sps = [NSData dataWithBytes:b + offset length:spsLength]; offset += spsLength;
    offset += 1; NSUInteger ppsLength = ((NSUInteger)b[offset] << 8) | b[offset + 1]; offset += 2;
    if (offset + ppsLength > configuration.length) return;
    NSData *pps = [NSData dataWithBytes:b + offset length:ppsLength];
    self.spsNAL = sps;
    self.ppsNAL = pps;
    self.spsBase64 = [sps base64EncodedStringWithOptions:0];
    self.ppsBase64 = [pps base64EncodedStringWithOptions:0];
    self.profileLevelID = [NSString stringWithFormat:@"%02X%02X%02X", b[1], b[2], b[3]];
    for (HARTSPClient *client in [self clientSnapshot]) {
        client.needsVideoParameterSets = YES;
        [client sendPendingDescriptionIfReady];
    }
}

- (void)setAudioConfiguration:(NSData *)configuration channels:(NSUInteger)channels sampleRate:(NSUInteger)sampleRate {
    if ([self.aacConfiguration isEqualToData:configuration] &&
        self.audioChannels == channels && self.audioSampleRate == sampleRate) return;
    self.aacConfiguration = [configuration copy]; self.audioChannels = channels; self.audioSampleRate = sampleRate;
    for (HARTSPClient *client in [self clientSnapshot]) [client sendPendingDescriptionIfReady];
}

- (void)clearMediaConfiguration {
    self.avcConfiguration = nil;
    self.aacConfiguration = nil;
    self.audioChannels = 0;
    self.audioSampleRate = 0;
    self.spsBase64 = nil;
    self.ppsBase64 = nil;
    self.spsNAL = nil;
    self.ppsNAL = nil;
    self.profileLevelID = nil;
    self.hasVideoTimestamp = NO;
    self.hasAudioTimestamp = NO;
    self.videoTimestampStep = 0;
}

- (void)sendVideoSample:(NSData *)avccNalus keyFrame:(BOOL)keyFrame timestamp:(uint32_t)milliseconds {
    if (!self.running || self.playingClientCount == 0) return;
    uint32_t timestamp = (uint32_t)(((uint64_t)milliseconds * 90));
    if (self.hasVideoTimestamp && (int32_t)(timestamp - self.lastVideoTimestamp) <= 0) {
        timestamp = self.lastVideoTimestamp + (self.videoTimestampStep ?: 3000);
    } else if (self.hasVideoTimestamp) {
        uint32_t step = timestamp - self.lastVideoTimestamp;
        if (step > 0 && step < 90000) self.videoTimestampStep = step;
    }
    self.hasVideoTimestamp = YES;
    self.lastVideoTimestamp = timestamp;
    for (HARTSPClient *client in [self clientSnapshot]) if (client.isAuthenticated && client.playing && client.videoSetup) [self sendVideo:avccNalus keyFrame:keyFrame timestamp:timestamp client:client];
}

- (void)sendAudioSample:(NSData *)aacRaw timestamp:(uint32_t)milliseconds {
    if (!self.running || self.audioSampleRate == 0 || self.playingClientCount == 0) return;
    uint32_t timestamp = (uint32_t)(((uint64_t)milliseconds * self.audioSampleRate) / 1000);
    if (self.hasAudioTimestamp && (int32_t)(timestamp - self.lastAudioTimestamp) <= 0) {
        timestamp = self.lastAudioTimestamp + 1;
    }
    self.hasAudioTimestamp = YES;
    self.lastAudioTimestamp = timestamp;
    for (HARTSPClient *client in [self clientSnapshot]) if (client.isAuthenticated && client.playing && client.audioSetup) {
        NSMutableData *payload = [NSMutableData dataWithCapacity:aacRaw.length + 4];
        uint8_t auLength[2] = {0, 16}; [payload appendBytes:auLength length:2];
        uint16_t header = htons((uint16_t)MIN((aacRaw.length << 3), 0xFFFF)); [payload appendBytes:&header length:2]; [payload appendData:aacRaw];
        uint16_t sequence = client.audioSequence; client.audioSequence = sequence + 1;
        [self sendRTPPayload:payload payloadType:97 marker:YES timestamp:timestamp sequence:sequence ssrc:client.audioSSRC channel:client.audioChannel client:client];
    }
}

- (void)sendVideo:(NSData *)avcc keyFrame:(BOOL)keyFrame timestamp:(uint32_t)timestamp client:(HARTSPClient *)client {
    if (keyFrame && client.needsVideoParameterSets && self.spsNAL.length && self.ppsNAL.length) {
        NSArray<NSData *> *parameterSets = @[self.spsNAL, self.ppsNAL];
        for (NSData *parameterSet in parameterSets) {
            uint16_t sequence = client.videoSequence;
            client.videoSequence = sequence + 1;
            [self sendRTPPayload:parameterSet payloadType:96 marker:NO timestamp:timestamp
                        sequence:sequence ssrc:client.videoSSRC channel:client.videoChannel client:client];
        }
        client.needsVideoParameterSets = NO;
    }
    const uint8_t *bytes = avcc.bytes; NSUInteger offset = 0;
    while (offset + 4 <= avcc.length) {
        uint32_t nalLength = ((uint32_t)bytes[offset] << 24) | ((uint32_t)bytes[offset+1] << 16) | ((uint32_t)bytes[offset+2] << 8) | bytes[offset+3]; offset += 4;
        if (nalLength == 0 || offset + nalLength > avcc.length) return;
        BOOL lastNal = (offset + nalLength == avcc.length); const uint8_t *nal = bytes + offset;
        if (nalLength <= kHARTSPMaxRTPPayload) {
            NSData *payload = [NSData dataWithBytes:nal length:nalLength]; uint16_t sequence=client.videoSequence; client.videoSequence=sequence+1; [self sendRTPPayload:payload payloadType:96 marker:lastNal timestamp:timestamp sequence:sequence ssrc:client.videoSSRC channel:client.videoChannel client:client];
        } else {
            uint8_t indicator = (nal[0] & 0xE0) | 28; uint8_t nalType = nal[0] & 0x1F; NSUInteger position = 1;
            while (position < nalLength) { NSUInteger length = MIN(kHARTSPMaxRTPPayload - 2, nalLength - position); BOOL start = position == 1; BOOL end = position + length == nalLength; uint8_t header[2] = { indicator, (uint8_t)(nalType | (start ? 0x80 : 0) | (end ? 0x40 : 0)) }; NSMutableData *fragment = [NSMutableData dataWithBytes:header length:2]; [fragment appendBytes:nal + position length:length]; uint16_t sequence=client.videoSequence; client.videoSequence=sequence+1; [self sendRTPPayload:fragment payloadType:96 marker:(lastNal && end) timestamp:timestamp sequence:sequence ssrc:client.videoSSRC channel:client.videoChannel client:client]; position += length; }
        }
        offset += nalLength;
    }
}

- (void)sendRTPPayload:(NSData *)payload payloadType:(uint8_t)payloadType marker:(BOOL)marker timestamp:(uint32_t)timestamp sequence:(uint16_t)sequence ssrc:(uint32_t)ssrc channel:(uint8_t)channel client:(HARTSPClient *)client {
    if (payloadType == 96 && !client.loggedVideoPacket) { client.loggedVideoPacket = YES; HALogI(@"rtsp", @"Sending first H.264 RTP packet to a client."); }
    if (payloadType == 97 && !client.loggedAudioPacket) { client.loggedAudioPacket = YES; HALogI(@"rtsp", @"Sending first AAC RTP packet to a client."); }
    NSMutableData *rtp = [NSMutableData dataWithCapacity:payload.length + 12]; uint8_t head[2] = {0x80, (uint8_t)(payloadType | (marker ? 0x80 : 0))}; [rtp appendBytes:head length:2]; uint16_t seq = htons(sequence); [rtp appendBytes:&seq length:2]; uint32_t ts = htonl(timestamp), source = htonl(ssrc); [rtp appendBytes:&ts length:4]; [rtp appendBytes:&source length:4]; [rtp appendData:payload];
    NSMutableData *interleaved = [NSMutableData dataWithCapacity:rtp.length + 4]; uint8_t dollar = '$'; [interleaved appendBytes:&dollar length:1]; [interleaved appendBytes:&channel length:1]; uint16_t len = htons((uint16_t)rtp.length); [interleaved appendBytes:&len length:2]; [interleaved appendData:rtp]; [client queue:interleaved];
}

- (NSString *)sessionDescription {
    if (!self.spsBase64.length || !self.ppsBase64.length || !self.aacConfiguration.length) return nil;
    NSMutableString *asc = [NSMutableString stringWithCapacity:self.aacConfiguration.length * 2];
    const uint8_t *ascBytes = self.aacConfiguration.bytes;
    for (NSUInteger index = 0; index < self.aacConfiguration.length; index++) {
        [asc appendFormat:@"%02X", ascBytes[index]];
    }
    return [NSString stringWithFormat:@"v=0\r\no=- 0 0 IN IP4 %@\r\ns=HA Dashboard\r\nc=IN IP4 %@\r\nt=0 0\r\na=control:*\r\nm=video 0 RTP/AVP 96\r\na=rtpmap:96 H264/90000\r\na=fmtp:96 packetization-mode=1;profile-level-id=%@;sprop-parameter-sets=%@,%@\r\na=control:trackID=0\r\nm=audio 0 RTP/AVP 97\r\na=rtpmap:97 MPEG4-GENERIC/%lu/%lu\r\na=fmtp:97 streamtype=5;profile-level-id=1;mode=AAC-hbr;config=%@;SizeLength=13;IndexLength=3;IndexDeltaLength=3\r\na=control:trackID=1\r\n", self.host, self.host, self.profileLevelID, self.spsBase64, self.ppsBase64, (unsigned long)self.audioSampleRate, (unsigned long)self.audioChannels, asc];
}

- (NSError *)error:(NSString *)description { return [NSError errorWithDomain:HARTSPServerErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:description}]; }
@end

@implementation HARTSPClient
- (instancetype)initWithNativeSocket:(CFSocketNativeHandle)socket server:(HARTSPServer *)server {
    self = [super init];
    if (!self) return nil;
    _server = server;
    _nativeSocket = socket;
    _inputBuffer = [NSMutableData data];
    _outputBuffer = [NSMutableData data];
    _sessionID = [[NSUUID UUID] UUIDString];
    _videoSequence = arc4random_uniform(UINT16_MAX);
    _audioSequence = arc4random_uniform(UINT16_MAX);
    _videoSSRC = arc4random();
    _audioSSRC = arc4random();
    _connectedAt = CFAbsoluteTimeGetCurrent();
    _lastActivity = _connectedAt;
    _authenticationNonce = HARTSPRandomNonce();
    if (!_authenticationNonce.length) return nil;
    int flags = fcntl(socket, F_GETFL, 0);
    if (flags < 0 || fcntl(socket, F_SETFL, flags | O_NONBLOCK) < 0) return nil;
    int noSignal = 1;
    if (setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal)) != 0) return nil;
    int noDelay = 1; setsockopt(socket, IPPROTO_TCP, TCP_NODELAY, &noDelay, sizeof(noDelay));
    CFSocketContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    _socket = CFSocketCreateWithNative(kCFAllocatorDefault, socket,
        kCFSocketReadCallBack | kCFSocketWriteCallBack, HARTSPSocketActivity, &context);
    if (!_socket) return nil;
    CFOptionFlags socketFlags = CFSocketGetSocketFlags(_socket);
    socketFlags |= kCFSocketCloseOnInvalidate | kCFSocketAutomaticallyReenableReadCallBack;
    socketFlags &= ~kCFSocketAutomaticallyReenableWriteCallBack;
    CFSocketSetSocketFlags(_socket, socketFlags);
    CFSocketDisableCallBacks(_socket, kCFSocketWriteCallBack);
    _socketSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);
    if (!_socketSource) {
        // The accept callback still owns the native descriptor on init failure.
        // Prevent invalidation here from closing it before that callback does.
        CFSocketSetSocketFlags(_socket,
            CFSocketGetSocketFlags(_socket) & ~kCFSocketCloseOnInvalidate);
        CFSocketInvalidate(_socket);
        CFRelease(_socket);
        _socket = NULL;
        return nil;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), _socketSource, kCFRunLoopCommonModes);
    _idleTimer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(checkIdleTimer:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_idleTimer forMode:NSRunLoopCommonModes];
    return self;
}
- (void)close {
    if (self.closed) return;
    self.closed = YES;
    [self.idleTimer invalidate];
    self.idleTimer = nil;
    self.pendingDescribeCSeq = nil;
    self.closeAfterOutputDrains = NO;
    self.outputBacklogStartedAt = 0;
    self.outputOffset = 0;
    [self.outputBuffer setLength:0];
    if (_socketSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _socketSource, kCFRunLoopCommonModes);
        CFRelease(_socketSource);
        _socketSource = NULL;
    }
    if (_socket) {
        CFSocketInvalidate(_socket);
        CFRelease(_socket);
        _socket = NULL;
    }
    [_server removeClient:self];
}
- (void)queue:(NSData *)data {
    if (self.closed || self.closeAfterOutputDrains || data.length == 0) return;
    NSUInteger pending = self.pendingOutputLength;
    NSUInteger maximum = self.server.maximumPendingOutputBytes ?: kHARTSPMaxPendingOutputBytes;
    if (data.length > maximum || pending > maximum - data.length) {
        HALogW(@"rtsp", @"Closing an RTSP client whose pending output exceeded %lu bytes.",
               (unsigned long)maximum);
        [self close];
        return;
    }
    BOOL wasEmpty = pending == 0;
    [self.outputBuffer appendData:data];
    if (wasEmpty) {
        self.outputBacklogStartedAt = CFAbsoluteTimeGetCurrent();
        [self flushOutput];
    }
}

- (NSUInteger)pendingOutputLength {
    return self.outputBuffer.length > self.outputOffset
        ? self.outputBuffer.length - self.outputOffset : 0;
}

- (void)flushOutput {
    if (self.closed) return;
    if (self.socket) CFSocketDisableCallBacks(self.socket, kCFSocketWriteCallBack);
    while (self.pendingOutputLength > 0) {
        const uint8_t *bytes = self.outputBuffer.bytes;
        int sendError = 0;
        ssize_t sent = [self.server sendBytes:bytes + self.outputOffset
                                       length:self.pendingOutputLength
                                       socket:self.nativeSocket
                                        error:&sendError];
        if (sent > 0) {
            self.outputOffset += (NSUInteger)sent;
            self.lastActivity = CFAbsoluteTimeGetCurrent();
            if (!self.closeAfterOutputDrains) self.outputBacklogStartedAt = self.lastActivity;
            continue;
        }
        if (sent < 0 && sendError == EINTR) continue;
        if (sent < 0 && (sendError == EAGAIN || sendError == EWOULDBLOCK)) {
            if (self.outputOffset > 0) {
                [self.outputBuffer replaceBytesInRange:NSMakeRange(0, self.outputOffset)
                                             withBytes:NULL
                                                length:0];
                self.outputOffset = 0;
            }
            if (self.socket && !self.closed) {
                CFSocketEnableCallBacks(self.socket, kCFSocketWriteCallBack);
            }
            return;
        }
        HALogW(@"rtsp", @"Socket write failed: %s", strerror(sendError));
        [self close];
        return;
    }
    [self.outputBuffer setLength:0];
    self.outputOffset = 0;
    self.outputBacklogStartedAt = 0;
    if (self.closeAfterOutputDrains) [self close];
}

- (void)closeAfterFlushingOutput {
    if (self.closed) return;
    BOOL mediaStateChanged = self.mediaDemand || self.playing;
    self.mediaDemand = NO;
    self.playing = NO;
    self.closeAfterOutputDrains = YES;
    if (self.socket) CFSocketDisableCallBacks(self.socket, kCFSocketReadCallBack);
    BOOL waitingForDrain = self.pendingOutputLength > 0;
    if (!waitingForDrain) {
        [self close];
    } else if (self.socket) {
        self.outputBacklogStartedAt = CFAbsoluteTimeGetCurrent();
        CFSocketEnableCallBacks(self.socket, kCFSocketWriteCallBack);
    }
    if (waitingForDrain && mediaStateChanged) [self.server clientStateDidChange];
}
- (void)readAvailable {
    if (self.closed || self.closeAfterOutputDrains) return;
    uint8_t bytes[4096];
    while (YES) {
        ssize_t received = recv(self.nativeSocket, bytes, sizeof(bytes), 0);
        if (received > 0) {
            self.lastActivity = CFAbsoluteTimeGetCurrent();
            if (self.inputBuffer.length + (NSUInteger)received > kHARTSPMaxInputBytes) {
                HALogW(@"rtsp", @"Closing a client that exceeded the RTSP input limit.");
                [self response:413 cseq:@"0" headers:nil body:nil];
                [self closeAfterFlushingOutput];
                return;
            }
            [self.inputBuffer appendBytes:bytes length:(NSUInteger)received];
            [self parse];
            if (self.closed || self.closeAfterOutputDrains) return;
            continue;
        }
        if (received == 0) { [self close]; return; }
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) return;
        HALogW(@"rtsp", @"Socket read failed: %s", strerror(errno));
        [self close];
        return;
    }
}
- (void)parse {
    NSData *end = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    while (_inputBuffer.length) {
        const uint8_t *bytes = _inputBuffer.bytes;
        if (bytes[0] == '$') {
            if (_inputBuffer.length < 4) return;
            NSUInteger length = ((NSUInteger)bytes[2] << 8) | bytes[3];
            if (length + 4 > kHARTSPMaxInputBytes) { [self close]; return; }
            if (_inputBuffer.length < length + 4) return;
            // Interleaved RTCP arrives from clients on the paired RTP channel.
            // It is not an RTSP request and must not poison the request buffer.
            [_inputBuffer replaceBytesInRange:NSMakeRange(0, length + 4) withBytes:NULL length:0];
            continue;
        }
        NSRange r = [_inputBuffer rangeOfData:end options:0 range:NSMakeRange(0, _inputBuffer.length)];
        if (r.location == NSNotFound) return;
        NSUInteger headerLength = r.location + 4;
        NSData *request = [_inputBuffer subdataWithRange:NSMakeRange(0, headerLength)];
        NSString *text = [[NSString alloc] initWithData:request encoding:NSUTF8StringEncoding];
        if (!text) {
            [self response:400 cseq:@"0" headers:nil body:nil];
            [self closeAfterFlushingOutput];
            return;
        }
        NSUInteger bodyLength = 0;
        if (![self contentLengthInRequest:text length:&bodyLength]) {
            [self response:400 cseq:@"0" headers:nil body:nil];
            [self closeAfterFlushingOutput];
            return;
        }
        if (bodyLength > kHARTSPMaxInputBytes - headerLength) {
            [self response:413 cseq:@"0" headers:nil body:nil];
            [self closeAfterFlushingOutput];
            return;
        }
        NSUInteger requestLength = headerLength + bodyLength;
        if (_inputBuffer.length < requestLength) return;
        [_inputBuffer replaceBytesInRange:NSMakeRange(0, requestLength) withBytes:NULL length:0];
        [self respond:text];
        if (self.closed || self.closeAfterOutputDrains) return;
    }
}
- (BOOL)contentLengthInRequest:(NSString *)request length:(NSUInteger *)length {
    NSUInteger parsedLength = 0;
    BOOL found = NO;
    NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
    for (NSUInteger index = 1; index < lines.count; index++) {
        NSString *line = lines[index];
        if (!line.length) break;
        NSRange separator = [line rangeOfString:@":"];
        if (separator.location == NSNotFound) return NO;
        NSString *key = [[[line substringToIndex:separator.location]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
        if (![key isEqualToString:@"content-length"]) continue;
        if (found) return NO;
        NSString *value = [[line substringFromIndex:separator.location + 1]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!HARTSPParseUnsigned(value, kHARTSPMaxInputBytes, &parsedLength)) return NO;
        found = YES;
    }
    if (length) *length = parsedLength;
    return YES;
}
- (void)respond:(NSString *)request {
    NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
    NSString *first = lines.firstObject ?: @"";
    NSArray *rawParts = [first componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:rawParts.count];
    for (NSString *part in rawParts) if (part.length) [parts addObject:part];

    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    BOOL malformedHeaders = NO;
    for (NSUInteger index = 1; index < lines.count; index++) {
        NSString *line = lines[index];
        if (!line.length) break;
        NSRange separator = [line rangeOfString:@":"];
        if (separator.location == NSNotFound) { malformedHeaders = YES; break; }
        NSString *key = [[[line substringToIndex:separator.location]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
        NSString *value = [[line substringFromIndex:separator.location + 1]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!key.length || headers[key]) { malformedHeaders = YES; break; }
        headers[key] = value;
    }
    NSString *cseq = headers[@"cseq"];
    if (malformedHeaders || parts.count != 3 || ![parts[2] isEqualToString:@"RTSP/1.0"] ||
        !HARTSPValidCSeq(cseq)) {
        [self response:400 cseq:@"0" headers:nil body:nil];
        [self closeAfterFlushingOutput];
        return;
    }

    NSString *method = parts[0];
    NSString *URL = parts[1];
    NSSet *knownMethods = [NSSet setWithObjects:@"OPTIONS", @"DESCRIBE", @"SETUP", @"PLAY", @"TEARDOWN", nil];
    HALogI(@"rtsp", @"Request %@ CSeq %@", [knownMethods containsObject:method] ? method : @"UNKNOWN", cseq);

    BOOL protectedMethod = [method isEqualToString:@"DESCRIBE"] || [method isEqualToString:@"SETUP"] ||
                           [method isEqualToString:@"PLAY"] || [method isEqualToString:@"TEARDOWN"];
    if (protectedMethod && ![self authenticateMethod:method URL:URL headers:headers cseq:cseq]) return;

    NSString *requestSession = headers[@"session"];
    NSRange sessionSeparator = [requestSession rangeOfString:@";"];
    if (sessionSeparator.location != NSNotFound) {
        requestSession = [requestSession substringToIndex:sessionSeparator.location];
    }
    BOOL requiresSession = [method isEqualToString:@"PLAY"] || [method isEqualToString:@"TEARDOWN"];
    if ((requiresSession && ![requestSession isEqualToString:self.sessionID]) ||
        ([method isEqualToString:@"SETUP"] && requestSession.length &&
         ![requestSession isEqualToString:self.sessionID])) {
        [self response:454 cseq:cseq headers:nil body:nil];
        return;
    }

    if ([method isEqualToString:@"OPTIONS"]) {
        [self response:200 cseq:cseq headers:@{ @"Public": @"OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN" } body:nil];
        return;
    }
    if ([method isEqualToString:@"DESCRIBE"]) {
        [self markMediaDemand];
        NSString *description = [_server sessionDescription];
        if (!description) {
            self.pendingDescribeCSeq = cseq;
            [_server.delegate rtspServerNeedsMediaConfiguration:_server];
            return;
        }
        [self response:200 cseq:cseq
                headers:@{ @"Content-Type": @"application/sdp", @"Content-Base": [_server streamURL] }
                   body:[description dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }
    if ([method isEqualToString:@"SETUP"]) {
        NSString *transport = headers[@"transport"];
        if ([transport rangeOfString:@"RTP/AVP/TCP" options:NSCaseInsensitiveSearch].location == NSNotFound) {
            [self response:461 cseq:cseq headers:nil body:nil];
            return;
        }
        BOOL video = [URL rangeOfString:@"trackID=0" options:NSCaseInsensitiveSearch].location != NSNotFound;
        BOOL audio = [URL rangeOfString:@"trackID=1" options:NSCaseInsensitiveSearch].location != NSNotFound;
        if (!video && !audio) {
            [self response:404 cseq:cseq headers:nil body:nil];
            return;
        }
        uint8_t channel = video ? 0 : 2;
        NSRange interleavedRange = [transport rangeOfString:@"interleaved=" options:NSCaseInsensitiveSearch];
        if (interleavedRange.location != NSNotFound) {
            NSString *tail = [transport substringFromIndex:interleavedRange.location + interleavedRange.length];
            NSRange semicolon = [tail rangeOfString:@";"];
            NSString *channels = semicolon.location == NSNotFound ? tail : [tail substringToIndex:semicolon.location];
            NSArray *channelParts = [channels componentsSeparatedByString:@"-"];
            NSUInteger firstChannel = 0, secondChannel = 0;
            if (channelParts.count != 2 || !HARTSPParseUnsigned(channelParts[0], 254, &firstChannel) ||
                !HARTSPParseUnsigned(channelParts[1], 255, &secondChannel) || secondChannel != firstChannel + 1) {
                [self response:461 cseq:cseq headers:nil body:nil];
                return;
            }
            channel = (uint8_t)firstChannel;
        }
        [self markMediaDemand];
        if (video) { self.videoSetup = YES; self.videoChannel = channel; }
        else { self.audioSetup = YES; self.audioChannel = channel; }
        [self response:200 cseq:cseq
                headers:@{ @"Transport": [NSString stringWithFormat:@"RTP/AVP/TCP;unicast;interleaved=%u-%u", channel, channel + 1],
                           @"Session": self.sessionID }
                   body:nil];
        return;
    }
    if ([method isEqualToString:@"PLAY"]) {
        if (!self.videoSetup && !self.audioSetup) {
            [self response:455 cseq:cseq headers:nil body:nil];
            return;
        }
        [self markMediaDemand];
        if (!self.playing) {
            self.playing = YES;
            [_server clientStateDidChange];
        }
        [_server.delegate rtspServerNeedsVideoKeyFrame:_server];
        [self response:200 cseq:cseq headers:@{ @"Session": self.sessionID, @"Range": @"npt=0.000-" } body:nil];
        return;
    }
    if ([method isEqualToString:@"TEARDOWN"]) {
        [self response:200 cseq:cseq headers:@{ @"Session": self.sessionID } body:nil];
        [self closeAfterFlushingOutput];
        return;
    }
    [self response:405 cseq:cseq headers:nil body:nil];
}
- (BOOL)authenticateMethod:(NSString *)method URL:(NSString *)URL headers:(NSDictionary *)headers cseq:(NSString *)cseq {
    // VLC 3.x reuses its authenticated DESCRIBE Authorization value for later
    // SETUP and PLAY requests on the same TCP connection. Digest establishes
    // the connection's identity once; RTSP session/state validation below still
    // applies independently to every subsequent protected request.
    if (self.isAuthenticated) return YES;

    NSString *authorization = headers[@"authorization"];
    NSDictionary *parameters = HARTSPDigestParameters(authorization);
    if (!authorization.length) {
        HALogI(@"rtsp", @"RTSP authentication is required for this connection.");
        [self response:401 cseq:cseq headers:@{
            @"WWW-Authenticate": [NSString stringWithFormat:
                @"Digest realm=\"%@\", nonce=\"%@\", algorithm=MD5",
                HARTSPAuthenticationRealm, self.authenticationNonce]
        } body:nil];
        return NO;
    }
    NSString *username = parameters[@"username"];
    NSString *realm = parameters[@"realm"];
    NSString *nonce = parameters[@"nonce"];
    NSString *digestURI = parameters[@"uri"];
    NSString *providedResponse = parameters[@"response"];
    NSString *algorithm = parameters[@"algorithm"];

    BOOL fieldsValid = username.length && realm.length && nonce.length && digestURI.length &&
        providedResponse.length == CC_MD5_DIGEST_LENGTH * 2 &&
        [username isEqualToString:_server.authenticationUsername] &&
        [realm isEqualToString:HARTSPAuthenticationRealm] &&
        HARTSPURIMatchesRequest(digestURI, URL) && !parameters[@"qop"] &&
        (!algorithm.length || [algorithm caseInsensitiveCompare:@"MD5"] == NSOrderedSame);
    BOOL digestValid = NO;
    if (fieldsValid) {
        NSString *HA1 = HARTSPMD5Hex([NSString stringWithFormat:@"%@:%@:%@", _server.authenticationUsername,
                                      HARTSPAuthenticationRealm, _server.authenticationPassword]);
        NSString *HA2 = HARTSPMD5Hex([NSString stringWithFormat:@"%@:%@", method, digestURI]);
        NSString *expected = HARTSPMD5Hex([NSString stringWithFormat:@"%@:%@:%@", HA1,
                                           nonce, HA2]);
        digestValid = HARTSPConstantTimeEqualHex(expected, providedResponse);
    }
    BOOL currentNonce = nonce.length && HARTSPConstantTimeEqualHex(nonce, self.authenticationNonce);
    if (digestValid && currentNonce) {
        self.authenticated = YES;
        self.authenticationFailures = 0;
        return YES;
    }

    if (digestValid && !currentNonce) {
        HALogI(@"rtsp", @"Requested a fresh RTSP Digest nonce for a reconnecting client.");
        [self response:401 cseq:cseq headers:@{
            @"WWW-Authenticate": [NSString stringWithFormat:
                @"Digest realm=\"%@\", nonce=\"%@\", algorithm=MD5, stale=true",
                HARTSPAuthenticationRealm, self.authenticationNonce]
        } body:nil];
        return NO;
    }

    self.authenticationFailures++;
    HALogW(@"rtsp", @"Rejected invalid RTSP credentials (%lu of %lu).",
           (unsigned long)self.authenticationFailures, (unsigned long)kHARTSPMaxAuthenticationFailures);
    NSMutableDictionary *challengeHeaders = [@{
        @"WWW-Authenticate": [NSString stringWithFormat:@"Digest realm=\"%@\", nonce=\"%@\", algorithm=MD5",
                              HARTSPAuthenticationRealm, self.authenticationNonce]
    } mutableCopy];
    BOOL closeAfterResponse = self.authenticationFailures >= kHARTSPMaxAuthenticationFailures;
    if (closeAfterResponse) challengeHeaders[@"Connection"] = @"close";
    [self response:401 cseq:cseq headers:challengeHeaders body:nil];
    if (closeAfterResponse) [self closeAfterFlushingOutput];
    return NO;
}
- (void)markMediaDemand {
    if (self.mediaDemand) return;
    self.mediaDemand = YES;
    [_server clientStateDidChange];
}
- (void)response:(NSInteger)status cseq:(NSString *)cseq headers:(NSDictionary *)headers body:(NSData *)body {
    NSDictionary *reasons = @{
        @200: @"OK", @400: @"Bad Request", @401: @"Unauthorized", @404: @"Not Found",
        @405: @"Method Not Allowed", @413: @"Request Entity Too Large", @454: @"Session Not Found",
        @455: @"Method Not Valid in This State", @461: @"Unsupported Transport",
        @503: @"Service Unavailable"
    };
    NSString *reason = reasons[@(status)] ?: @"Error";
    NSMutableString *head = [NSMutableString stringWithFormat:@"RTSP/1.0 %ld %@\r\nCSeq: %@\r\n",
                             (long)status, reason, HARTSPValidCSeq(cseq) ? cseq : @"0"];
    for (NSString *key in headers) [head appendFormat:@"%@: %@\r\n", key, headers[key]];
    [head appendFormat:@"Content-Length: %lu\r\n\r\n", (unsigned long)body.length];
    NSMutableData *data = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if (body.length) [data appendData:body];
    HALogI(@"rtsp", @"Response %ld CSeq %@", (long)status, HARTSPValidCSeq(cseq) ? cseq : @"0");
    [self queue:data];
}
- (void)sendPendingDescriptionIfReady {
    if (!self.isAuthenticated || !self.mediaDemand || !self.pendingDescribeCSeq.length) return;
    NSString *description = [_server sessionDescription];
    if (!description) return;
    NSString *cseq = self.pendingDescribeCSeq;
    self.pendingDescribeCSeq = nil;
    [self response:200 cseq:cseq
            headers:@{ @"Content-Type": @"application/sdp", @"Content-Base": [_server streamURL] }
               body:[description dataUsingEncoding:NSUTF8StringEncoding]];
}
- (void)checkIdleTimer:(NSTimer *)timer {
    (void)timer;
    if (self.closed) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!self.isAuthenticated && now - self.connectedAt >= kHARTSPAuthenticationTimeout) {
        HALogI(@"rtsp", @"Closing an RTSP client that did not authenticate in time.");
        [self close];
    } else if (self.pendingOutputLength > 0 && self.outputBacklogStartedAt > 0 &&
               now - self.outputBacklogStartedAt >= kHARTSPOutputBackpressureTimeout) {
        HALogW(@"rtsp", @"Closing an RTSP client whose output remained blocked for %.0f seconds.",
               kHARTSPOutputBackpressureTimeout);
        [self close];
    } else if (now - self.lastActivity >= kHARTSPClientIdleTimeout) {
        HALogI(@"rtsp", @"Closing an idle RTSP client.");
        [self close];
    }
}
@end
