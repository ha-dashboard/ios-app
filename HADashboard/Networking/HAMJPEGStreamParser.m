#import "HAMJPEGStreamParser.h"

/// Queue for JPEG decoding — avoid blocking main thread with image decompression.
static dispatch_queue_t _decodeQueue;

static const NSTimeInterval kFirstFrameTimeout = 10.0;

@interface HAMJPEGStreamParser () <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, copy) NSData *boundaryData;
@property (nonatomic, assign) BOOL streaming;
@property (nonatomic, assign) BOOL receivedFirstFrame;
@property (nonatomic, strong) NSTimer *firstFrameTimer;
@property (nonatomic, assign) BOOL usePartAccumulation; // NSURLSession splits multipart for us
@end

@implementation HAMJPEGStreamParser

+ (void)initialize {
    if (self == [HAMJPEGStreamParser class]) {
        _decodeQueue = dispatch_queue_create("com.hadashboard.mjpeg.decode", DISPATCH_QUEUE_SERIAL);
    }
}

- (void)dealloc {
    [self stop];
}

#pragma mark - Public

- (void)startWithURL:(NSURL *)url authToken:(NSString *)token {
    [self stop]; // Cancel any existing stream

    self.buffer = [NSMutableData data];
    self.boundaryData = nil; // Will be extracted from Content-Type header
    self.streaming = YES;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    if (token.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }
    // Long timeout — stream runs until cancelled
    request.timeoutInterval = 300;

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 30; // Initial connection timeout
    config.timeoutIntervalForResource = 0; // No overall timeout for streaming
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    self.task = [self.session dataTaskWithRequest:request];
    [self.task resume];
}

- (void)stop {
    self.streaming = NO;
    [self.firstFrameTimer invalidate];
    self.firstFrameTimer = nil;
    [self.task cancel];
    self.task = nil;
    [self.session invalidateAndCancel];
    self.session = nil;
    self.buffer = nil;
    self.boundaryData = nil;
    self.receivedFirstFrame = NO;
    self.usePartAccumulation = NO;
}

- (BOOL)isStreaming {
    return _streaming;
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    if (!self.streaming) {
        completionHandler(NSURLSessionResponseCancel);
        return;
    }

    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    if (http.statusCode != 200) {
        NSError *error = [NSError errorWithDomain:@"HAMJPEGStreamParser" code:http.statusCode
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)http.statusCode]}];
        [self reportError:error];
        completionHandler(NSURLSessionResponseCancel);
        return;
    }

    NSString *contentType = http.allHeaderFields[@"Content-Type"];
    NSLog(@"[HAMJPEGStreamParser] Response %ld, Content-Type: %@", (long)http.statusCode, contentType);

    // NSURLSession splits multipart/x-mixed-replace into per-part responses.
    // First call: Content-Type is multipart/x-mixed-replace (extract boundary).
    // Subsequent calls: Content-Type is image/jpeg (one per MJPEG frame).
    // When we detect a subsequent part, flush the accumulated buffer as a frame.
    if (self.boundaryData) {
        self.usePartAccumulation = YES;
        // Flush previous part's data as a JPEG frame
        if (self.buffer.length > 100) {
            [self decodeJPEGFromChunk:[self.buffer copy]];
        }
        [self.buffer setLength:0];
        completionHandler(NSURLSessionResponseAllow);
        return;
    }

    // First response — check if it's actually multipart
    if (contentType && ![contentType containsString:@"multipart"]) {
        NSLog(@"[HAMJPEGStreamParser] Not a multipart stream (Content-Type: %@) — aborting", contentType);
        NSError *error = [NSError errorWithDomain:@"HAMJPEGStreamParser" code:-3
            userInfo:@{NSLocalizedDescriptionKey: @"Not a multipart MJPEG stream"}];
        [self reportError:error];
        completionHandler(NSURLSessionResponseCancel);
        return;
    }

    [self extractBoundaryFromContentType:contentType];

    // Start first-frame timeout — if no frame arrives within 10s, abort
    dispatch_async(dispatch_get_main_queue(), ^{
        self.firstFrameTimer = [NSTimer scheduledTimerWithTimeInterval:kFirstFrameTimeout
                                                               target:self
                                                             selector:@selector(firstFrameTimedOut)
                                                             userInfo:nil
                                                              repeats:NO];
    });

    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if (!self.streaming) return;
    [self.buffer appendData:data];
    // In part accumulation mode, NSURLSession splits parts for us — frames are flushed
    // in didReceiveResponse when the next part starts. Only use boundary extraction
    // when NSURLSession doesn't split (single continuous stream).
    if (!self.usePartAccumulation) {
        [self extractFrames];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!self.streaming) return;
    self.streaming = NO;
    if (error && error.code != NSURLErrorCancelled) {
        [self reportError:error];
    }
}

#pragma mark - Boundary Parsing

- (void)extractBoundaryFromContentType:(NSString *)contentType {
    // Content-Type: multipart/x-mixed-replace; boundary=--frameboundary
    // or: multipart/x-mixed-replace;boundary=frameboundary
    if (!contentType) {
        // Fallback: common HA boundary
        self.boundaryData = [@"\r\n--frame\r\n" dataUsingEncoding:NSUTF8StringEncoding];
        return;
    }
    NSRange boundaryRange = [contentType rangeOfString:@"boundary=" options:NSCaseInsensitiveSearch];
    if (boundaryRange.location == NSNotFound) {
        self.boundaryData = [@"\r\n--frame\r\n" dataUsingEncoding:NSUTF8StringEncoding];
        return;
    }
    NSString *boundary = [contentType substringFromIndex:NSMaxRange(boundaryRange)];
    // Trim quotes and whitespace
    boundary = [boundary stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\" \t"]];
    // The actual boundary in the body is prefixed with --
    if (![boundary hasPrefix:@"--"]) {
        boundary = [@"--" stringByAppendingString:boundary];
    }
    self.boundaryData = [[NSString stringWithFormat:@"\r\n%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - Frame Extraction

- (void)extractFrames {
    if (!self.boundaryData || self.buffer.length == 0) return;

    // Search for JPEG data between boundaries.
    // JPEG frames start after headers (Content-Type + Content-Length + empty line)
    // and end at the next boundary marker.

    while (self.streaming) {
        NSRange boundaryRange = [self rangeOfData:self.boundaryData inData:self.buffer];
        if (boundaryRange.location == NSNotFound) break;

        // Everything before the boundary is part of the current frame (headers + JPEG)
        NSData *chunk = [self.buffer subdataWithRange:NSMakeRange(0, boundaryRange.location)];

        // Remove processed data + boundary from buffer
        NSUInteger consumed = NSMaxRange(boundaryRange);
        if (consumed < self.buffer.length) {
            NSData *remaining = [self.buffer subdataWithRange:NSMakeRange(consumed, self.buffer.length - consumed)];
            self.buffer = [remaining mutableCopy];
        } else {
            [self.buffer setLength:0];
        }

        // Extract JPEG from chunk (skip HTTP headers to find JPEG data)
        [self decodeJPEGFromChunk:chunk];
    }
}

- (void)decodeJPEGFromChunk:(NSData *)chunk {
    if (chunk.length < 10) return;

    // Find JPEG start marker (0xFF 0xD8) — skip any preceding HTTP headers
    const uint8_t *bytes = chunk.bytes;
    NSUInteger jpegStart = NSNotFound;
    for (NSUInteger i = 0; i + 1 < chunk.length; i++) {
        if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8) {
            jpegStart = i;
            break;
        }
    }
    if (jpegStart == NSNotFound) return;

    NSData *jpegData = [chunk subdataWithRange:NSMakeRange(jpegStart, chunk.length - jpegStart)];
    if (jpegData.length < 100) return; // Too small for a valid JPEG

    // Decode on background thread to avoid main thread stalls.
    // Use weak/strong to prevent crash if parser is deallocated mid-decode (iPad 2 iOS 9).
    __weak typeof(self) weakSelf = self;
    dispatch_async(_decodeQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.streaming) return;

        // Autoreleasepool per frame prevents memory accumulation on A5 (iPad 2)
        @autoreleasepool {
            UIImage *lazyImage = [UIImage imageWithData:jpegData];
            if (!lazyImage) return;

            UIGraphicsBeginImageContextWithOptions(lazyImage.size, YES, 1.0);
            [lazyImage drawAtPoint:CGPointZero];
            UIImage *decoded = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            if (!decoded || !strongSelf.streaming) return;

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) mainSelf = weakSelf;
                if (!mainSelf || !mainSelf.streaming || !mainSelf.frameHandler) return;
                if (!mainSelf.receivedFirstFrame) {
                    mainSelf.receivedFirstFrame = YES;
                    [mainSelf.firstFrameTimer invalidate];
                    mainSelf.firstFrameTimer = nil;
                }
                mainSelf.frameHandler(decoded);
            });
        }
    });
}

- (void)firstFrameTimedOut {
    if (!self.streaming || self.receivedFirstFrame) return;
    NSLog(@"[HAMJPEGStreamParser] No frame received within %.0fs — aborting", kFirstFrameTimeout);
    self.streaming = NO;
    [self.task cancel];
    NSError *error = [NSError errorWithDomain:@"HAMJPEGStreamParser" code:-4
        userInfo:@{NSLocalizedDescriptionKey: @"No MJPEG frame received within timeout"}];
    [self reportError:error];
}

#pragma mark - Helpers

- (NSRange)rangeOfData:(NSData *)needle inData:(NSData *)haystack {
    if (needle.length == 0 || haystack.length < needle.length) {
        return NSMakeRange(NSNotFound, 0);
    }
    // Use NSData's rangeOfData if available (iOS 4+)
    return [haystack rangeOfData:needle options:0 range:NSMakeRange(0, haystack.length)];
}

- (void)reportError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.errorHandler) {
            self.errorHandler(error);
        }
    });
}

@end
