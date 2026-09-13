#import "HABLEAPIServer.h"
#import "HABLENoiseSession.h"
#import "HABLEProto.h"
#import <CFNetwork/CFNetwork.h>
#import <arpa/inet.h>
#import <netinet/tcp.h>
#import <sys/socket.h>
#import <unistd.h>

@interface HABLEAPIConnection () <NSStreamDelegate>
@property (nonatomic, weak) HABLEAPIServer *server;
@property (nonatomic, strong) NSInputStream *input;
@property (nonatomic, strong) NSOutputStream *output;
@property (nonatomic, strong) NSMutableData *incoming;
@property (nonatomic, strong) NSMutableData *outgoing;
@property (nonatomic, strong) HABLENoiseSession *noise;
@property (nonatomic, assign) NSUInteger stage;
@property (nonatomic, assign) BOOL closed;
@property (nonatomic, assign) BOOL closeAfterFlush;
@property (nonatomic, assign, readwrite) BOOL authenticated;
@property (nonatomic, assign) CFAbsoluteTime openedAt;
@property (nonatomic, assign) CFAbsoluteTime receivedAt;
@property (nonatomic, assign) CFAbsoluteTime backlogAt;
- (void)close;
- (void)sendFrame:(NSData *)frame;
- (void)flush;
- (void)consume;
@end

@interface HABLEAPIServer ()
@property (nonatomic, strong) NSMutableSet<HABLEAPIConnection *> *connections;
@property (nonatomic, strong) NSData *key;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *address;
@property (nonatomic, assign) CFSocketRef listener;
@property (nonatomic, assign) CFRunLoopSourceRef source;
@property (nonatomic, strong) NSTimer *timer;
- (void)accept:(CFSocketNativeHandle)fd;
@end

static void HABLEAccept(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    if (type == kCFSocketAcceptCallBack && data) [(__bridge HABLEAPIServer *)info accept:*(const CFSocketNativeHandle *)data];
}

@implementation HABLEAPIConnection
- (void)close {
    // NSStream delegates are not owners. Removing the connection from the
    // server may release its final external reference during this method.
    __attribute__((objc_precise_lifetime)) HABLEAPIConnection *keepAlive = self;
    (void)keepAlive;
    if (self.closed) return;
    self.closed = YES;
    self.input.delegate = nil; self.output.delegate = nil;
    [self.input removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [self.output removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [self.input close]; [self.output close];
    self.noise = nil; self.incoming = nil; self.outgoing = nil;
    HABLEAPIServer *server = self.server;
    [server.connections removeObject:self];
    [server.delegate bleServer:server closedConnection:self];
}
- (void)sendFrame:(NSData *)frame {
    if (self.closed || !frame || frame.length > 16404) { [self close]; return; }
    if (self.outgoing.length + frame.length + 3 > 256 * 1024) { [self close]; return; }
    if (!self.outgoing.length) self.backlogAt = CFAbsoluteTimeGetCurrent();
    uint8_t header[] = {1, (uint8_t)(frame.length >> 8), (uint8_t)frame.length};
    [self.outgoing appendBytes:header length:3]; [self.outgoing appendData:frame]; [self flush];
}
- (void)flush {
    while (!self.closed && self.outgoing.length && self.output.hasSpaceAvailable) {
        NSInteger count = [self.output write:self.outgoing.bytes maxLength:self.outgoing.length];
        if (count < 0) { [self close]; return; }
        if (!count) break;
        [self.outgoing replaceBytesInRange:NSMakeRange(0, (NSUInteger)count) withBytes:NULL length:0];
    }
    if (self.closeAfterFlush && !self.outgoing.length) [self close];
}
- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event {
    __attribute__((objc_precise_lifetime)) HABLEAPIConnection *keepAlive = self;
    (void)keepAlive;
    if (event == NSStreamEventHasBytesAvailable) {
        uint8_t buffer[4096];
        NSInteger count = [self.input read:buffer maxLength:sizeof(buffer)];
        if (count <= 0) { [self close]; return; }
        if (self.incoming.length + (NSUInteger)count > 64 * 1024) { [self close]; return; }
        [self.incoming appendBytes:buffer length:(NSUInteger)count]; [self consume];
    } else if (event == NSStreamEventHasSpaceAvailable) [self flush];
    else if (event == NSStreamEventErrorOccurred || event == NSStreamEventEndEncountered) [self close];
}
- (void)consume {
    while (!self.closed && self.incoming.length >= 3) {
        const uint8_t *bytes = self.incoming.bytes;
        if (bytes[0] != 1) {
            // The plaintext client recognises this preamble as "requires encryption".
            uint8_t marker = 1; [self sendFrame:[NSData dataWithBytes:&marker length:1]];
            self.stage = 99; return;
        }
        NSUInteger length = ((NSUInteger)bytes[1] << 8) | bytes[2];
        if (length > 16404) { [self close]; return; }
        if (self.incoming.length < length + 3) return;
        NSData *frame = [self.incoming subdataWithRange:NSMakeRange(3, length)];
        [self.incoming replaceBytesInRange:NSMakeRange(0, length + 3) withBytes:NULL length:0];
        self.receivedAt = CFAbsoluteTimeGetCurrent();
        if (self.stage == 0) {
            if (length) { [self close]; return; }
            uint8_t protocol = 1, zero = 0;
            NSMutableData *hello = [NSMutableData dataWithBytes:&protocol length:1];
            [hello appendData:[self.server.name dataUsingEncoding:NSUTF8StringEncoding]]; [hello appendBytes:&zero length:1];
            [hello appendData:[self.server.address dataUsingEncoding:NSUTF8StringEncoding]]; [hello appendBytes:&zero length:1];
            self.stage = 1; [self sendFrame:hello];
        } else if (self.stage == 1) {
            if (length != 49 || ((const uint8_t *)frame.bytes)[0] != 0) { [self close]; return; }
            NSData *reply = [self.noise respondToHandshake:[frame subdataWithRange:NSMakeRange(1, 48)]];
            if (!reply) {
                // HA deliberately probes with a wrong PSK to learn the name.
                // Its client requires this exact rejection to classify an
                // unknown key separately from a broken network connection.
                uint8_t failed = 1;
                NSMutableData *rejection = [NSMutableData dataWithBytes:&failed length:1];
                [rejection appendData:[@"Handshake MAC failure" dataUsingEncoding:NSUTF8StringEncoding]];
                self.closeAfterFlush = YES; [self sendFrame:rejection]; return;
            }
            uint8_t zero = 0; NSMutableData *message = [NSMutableData dataWithBytes:&zero length:1]; [message appendData:reply];
            self.stage = 2; self.authenticated = YES; [self sendFrame:message];
        } else if (self.stage == 2) {
            NSData *plain = [self.noise decrypt:frame];
            if (plain.length < 4) { [self close]; return; }
            const uint8_t *body = plain.bytes;
            NSUInteger type = ((NSUInteger)body[0] << 8) | body[1];
            NSUInteger size = ((NSUInteger)body[2] << 8) | body[3];
            if (size != plain.length - 4) { [self close]; return; }
            [self.server.delegate bleServer:self.server receivedType:type data:[plain subdataWithRange:NSMakeRange(4, size)] connection:self];
        } else { [self close]; return; }
    }
}
@end

@implementation HABLEAPIServer
- (instancetype)initWithName:(NSString *)name address:(NSString *)address key:(NSData *)key {
    if (key.length != 32 || !name.length || !address.length) return nil;
    if ((self = [super init])) { _name = [name copy]; _address = [address copy]; _key = [key copy]; _connections = [NSMutableSet set]; }
    return self;
}
- (void)dealloc { [self stop]; }
- (NSUInteger)authenticatedClients {
    NSUInteger count = 0; for (HABLEAPIConnection *connection in self.connections) if (connection.authenticated) count++; return count;
}
- (BOOL)startWithHost:(NSString *)host port:(uint16_t)port error:(NSError **)error {
    [self stop];
    CFSocketContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    self.listener = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, HABLEAccept, &context);
    if (self.listener) {
        int yes = 1; setsockopt(CFSocketGetNative(self.listener), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
        struct sockaddr_in addr = {0}; addr.sin_len = sizeof(addr); addr.sin_family = AF_INET; addr.sin_port = htons(port);
        if (inet_pton(AF_INET, host.UTF8String, &addr.sin_addr) == 1 && CFSocketSetAddress(self.listener, (__bridge CFDataRef)[NSData dataWithBytes:&addr length:sizeof(addr)]) == kCFSocketSuccess) {
            self.source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, self.listener, 0);
            if (self.source) {
                CFRunLoopAddSource(CFRunLoopGetMain(), self.source, kCFRunLoopCommonModes);
                self.timer = [NSTimer timerWithTimeInterval:1 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
                [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes]; return YES;
            }
        }
    }
    [self stop];
    if (error) *error = [NSError errorWithDomain:@"HABLEAPIServer" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Could not open the Bluetooth proxy port on the local network."}];
    return NO;
}
- (void)accept:(CFSocketNativeHandle)fd {
    if (self.connections.count >= 4) { close(fd); return; }
    int yes = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes)); setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));
    CFReadStreamRef read = NULL; CFWriteStreamRef write = NULL;
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, fd, &read, &write);
    if (!read || !write) { if (read) CFRelease(read); if (write) CFRelease(write); close(fd); return; }
    CFReadStreamSetProperty(read, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    CFWriteStreamSetProperty(write, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    HABLEAPIConnection *connection = [[HABLEAPIConnection alloc] init];
    connection.server = self; connection.input = CFBridgingRelease(read); connection.output = CFBridgingRelease(write);
    connection.incoming = [NSMutableData data]; connection.outgoing = [NSMutableData data];
    connection.noise = [[HABLENoiseSession alloc] initWithKey:self.key];
    connection.openedAt = connection.receivedAt = CFAbsoluteTimeGetCurrent();
    [self.connections addObject:connection];
    connection.input.delegate = connection; connection.output.delegate = connection;
    [connection.input scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [connection.output scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [connection.input open]; [connection.output open];
}
- (void)tick:(NSTimer *)timer {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    for (HABLEAPIConnection *connection in [self.connections copy]) {
        if ((!connection.authenticated && now - connection.openedAt > 10) || now - connection.receivedAt > 90 || (connection.outgoing.length && now - connection.backlogAt > 10)) [connection close];
    }
}
- (void)stop {
    [self.timer invalidate]; self.timer = nil;
    if (self.source) { CFRunLoopRemoveSource(CFRunLoopGetMain(), self.source, kCFRunLoopCommonModes); CFRelease(self.source); self.source = NULL; }
    if (self.listener) { CFSocketInvalidate(self.listener); CFRelease(self.listener); self.listener = NULL; }
    for (HABLEAPIConnection *connection in [self.connections copy]) [connection close];
}
- (void)sendType:(NSUInteger)type data:(NSData *)data to:(HABLEAPIConnection *)connection {
    if (!connection.authenticated || connection.closed || data.length > 16384 || type > UINT16_MAX) return;
    uint8_t header[] = {(uint8_t)(type >> 8), (uint8_t)type, (uint8_t)(data.length >> 8), (uint8_t)data.length};
    NSMutableData *plain = [NSMutableData dataWithBytes:header length:4]; [plain appendData:data ?: [NSData data]];
    [connection sendFrame:[connection.noise encrypt:plain]];
}
- (BOOL)broadcastAdvertisement:(NSData *)data {
    BOOL sent = NO;
    for (HABLEAPIConnection *c in [self.connections copy]) if (c.advertisements && c.authenticated) { [self sendType:67 data:data to:c]; sent = YES; }
    return sent;
}
- (void)broadcastSlots:(NSData *)data {
    for (HABLEAPIConnection *c in [self.connections copy]) if (c.connectionSlots) [self sendType:81 data:data to:c];
}
- (void)broadcastLog:(NSString *)message {
    NSMutableData *data = [NSMutableData data]; HABLEPutInteger(data, 1, 3); HABLEPutString(data, 3, message);
    for (HABLEAPIConnection *c in [self.connections copy]) if (c.logs) [self sendType:29 data:data to:c];
}
@end
