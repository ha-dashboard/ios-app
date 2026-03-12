#import "HAPerfMonitor.h"
#import "HALog.h"
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <sys/utsname.h>
#import <UIKit/UIKit.h>

// Ring buffer size — 120 frames ≈ 2s at 60fps or 4s at 30fps
#define kFrameRingSize 120

// Flush interval in seconds
static const NSTimeInterval kFlushInterval = 10.0;

@interface HAPerfMonitor ()
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) NSTimer *flushTimer;
@property (nonatomic, strong) NSFileHandle *logHandle;
@property (nonatomic, copy) NSString *logPath;
@property (nonatomic, copy) NSString *deviceModel;
@property (nonatomic, assign) BOOL isLightweight; // iPad2/iPad3 class device
@end

@implementation HAPerfMonitor {
    // Frame timing ring buffer — pure C, zero allocations in displayLink callback
    CFTimeInterval _frameTimes[kFrameRingSize];
    NSUInteger _frameWriteIndex;
    NSUInteger _frameCount; // total frames since last flush
    CFTimeInterval _lastFrameTime;

    // Rebuild timing
    CFTimeInterval _rebuildStart;
    double _lastRebuildMs; // most recent rebuild duration

    // Cell timing
    CFTimeInterval _cellStart;
    NSString *_cellType;
    double _cellTotalMs;
    NSUInteger _cellCount;
    double _cellMaxMs;
    NSString *_cellMaxType;

    BOOL _headerWritten;
}

+ (instancetype)sharedMonitor {
    static HAPerfMonitor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HAPerfMonitor alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self detectDevice];
        [self resolveLogPath];
    }
    return self;
}

#pragma mark - Device Detection

- (void)detectDevice {
#if !TARGET_OS_SIMULATOR
    struct utsname systemInfo;
    if (uname(&systemInfo) == 0) {
        self.deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    }
    self.isLightweight = (self.deviceModel &&
        ([self.deviceModel hasPrefix:@"iPad2"] || [self.deviceModel hasPrefix:@"iPad3"] ||
         [self.deviceModel hasPrefix:@"iPhone4"] || [self.deviceModel hasPrefix:@"iPod5"]));
#else
    self.deviceModel = @"Simulator";
    self.isLightweight = NO;
#endif
}

- (void)resolveLogPath {
    // Jailbroken apps in /Applications can write to /tmp; sandboxed apps use Documents
    NSString *appPath = [[NSBundle mainBundle] bundlePath];
    if ([appPath hasPrefix:@"/Applications"]) {
        self.logPath = @"/tmp/perf.log";
    } else {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        self.logPath = [paths.firstObject stringByAppendingPathComponent:@"perf.log"];
    }
}

#pragma mark - Start / Stop

- (void)start {
    if (self.displayLink) return; // already running

    // Reset counters
    _frameWriteIndex = 0;
    _frameCount = 0;
    _lastFrameTime = 0;
    _lastRebuildMs = 0;
    _cellTotalMs = 0;
    _cellCount = 0;
    _cellMaxMs = 0;
    _cellMaxType = nil;
    _headerWritten = NO;

    // Open log file (truncate on fresh start)
    [[NSFileManager defaultManager] createFileAtPath:self.logPath contents:nil attributes:nil];
    self.logHandle = [NSFileHandle fileHandleForWritingAtPath:self.logPath];
    [self writeHeader];

    // CADisplayLink for frame timing
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkFired:)];
    if (self.isLightweight) {
        // iPad 2: fire every other frame to halve callback overhead
        self.displayLink.frameInterval = 2;
    }
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    // Periodic flush timer
    self.flushTimer = [NSTimer scheduledTimerWithTimeInterval:kFlushInterval
                                                      target:self
                                                    selector:@selector(flush)
                                                    userInfo:nil
                                                     repeats:YES];

    HALogI(@"perf", @"Started — device=%@ lightweight=%d log=%@",
          self.deviceModel, self.isLightweight, self.logPath);
}

- (void)stop {
    [self.displayLink invalidate];
    self.displayLink = nil;
    [self.flushTimer invalidate];
    self.flushTimer = nil;

    // Final flush — write synchronously since we're about to close the handle.
    // Can't use the async flush path because logHandle will be closed immediately after.
    if (self.logHandle) {
        NSUInteger count = MIN(_frameWriteIndex, (NSUInteger)kFrameRingSize);
        if (count > 0) {
            double totalInterval = 0, maxInterval = 0;
            NSUInteger start = (_frameWriteIndex > kFrameRingSize) ? (_frameWriteIndex - kFrameRingSize) : 0;
            for (NSUInteger i = 0; i < count; i++) {
                double dt = _frameTimes[(start + i) % kFrameRingSize];
                totalInterval += dt;
                if (dt > maxInterval) maxInterval = dt;
            }
            double fpsAvg = (totalInterval > 0) ? (1.0 / (totalInterval / count)) : 0;
            double fpsMin = (maxInterval > 0) ? (1.0 / maxInterval) : 0;
            double cellAvgMs = (_cellCount > 0) ? (_cellTotalMs / _cellCount) : 0;
            NSTimeInterval ts = [[NSDate date] timeIntervalSince1970];
            NSString *line = [NSString stringWithFormat:@"%.0f,%.1f,%.1f,%.1f,%.1f,%.1f,%.2f,%.2f,%@\n",
                ts, fpsAvg, fpsMin, fpsMin, [self residentMemoryMB],
                _lastRebuildMs, cellAvgMs, _cellMaxMs, _cellMaxType ?: @"-"];
            [self.logHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [self.logHandle synchronizeFile];
        }
        [self.logHandle closeFile];
        self.logHandle = nil;
    }

    // Reset counters
    _frameWriteIndex = 0;
    _frameCount = 0;
    _lastRebuildMs = 0;
    _cellTotalMs = 0;
    _cellCount = 0;
    _cellMaxMs = 0;
    _cellMaxType = nil;

    HALogI(@"perf", @"Stopped — log at %@", self.logPath);
}

#pragma mark - Header

- (void)writeHeader {
    if (_headerWritten) return;
    _headerWritten = YES;

    NSString *iosVersion = [[UIDevice currentDevice] systemVersion];
    CGFloat scale = [UIScreen mainScreen].scale;

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    NSString *startTime = [fmt stringFromDate:[NSDate date]];

    NSString *header = [NSString stringWithFormat:
        @"# HAPerfMonitor v1 | device=%@ | iOS=%@ | scale=%.0fx | started=%@\n"
        @"# ts,fps_avg,fps_min,fps_p1,mem_mb,rebuild_ms,cell_avg_ms,cell_max_ms,cell_max_type\n",
        self.deviceModel ?: @"unknown", iosVersion, scale, startTime];

    [self.logHandle writeData:[header dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark - CADisplayLink Callback (hot path — no ObjC allocations)

- (void)displayLinkFired:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    if (_lastFrameTime > 0) {
        _frameTimes[_frameWriteIndex % kFrameRingSize] = now - _lastFrameTime;
        _frameWriteIndex++;
        _frameCount++;
    }
    _lastFrameTime = now;
}

#pragma mark - Timing Marks

- (void)markRebuildStart {
    _rebuildStart = CACurrentMediaTime();
}

- (void)markRebuildEnd {
    if (_rebuildStart > 0) {
        _lastRebuildMs = (CACurrentMediaTime() - _rebuildStart) * 1000.0;
        _rebuildStart = 0;
    }
}

- (void)markCellStart:(NSString *)cellType {
    _cellStart = CACurrentMediaTime();
    _cellType = cellType;
}

- (void)markCellEnd {
    if (_cellStart > 0) {
        double ms = (CACurrentMediaTime() - _cellStart) * 1000.0;
        _cellTotalMs += ms;
        _cellCount++;
        if (ms > _cellMaxMs) {
            _cellMaxMs = ms;
            _cellMaxType = _cellType;
        }
        _cellStart = 0;
    }
}

#pragma mark - Flush

- (void)flush {
    if (!self.logHandle) return;

    // Snapshot frame data on main thread (fast — just memcpy)
    NSUInteger count = MIN(_frameWriteIndex, (NSUInteger)kFrameRingSize);
    double *snapshotFrames = (double *)malloc(count * sizeof(double));
    if (!snapshotFrames) return;
    if (count > 0) {
        NSUInteger start = (_frameWriteIndex > kFrameRingSize) ? (_frameWriteIndex - kFrameRingSize) : 0;
        for (NSUInteger i = 0; i < count; i++) {
            snapshotFrames[i] = _frameTimes[(start + i) % kFrameRingSize];
        }
    }
    double rebuildMs = _lastRebuildMs;
    double cellTotal = _cellTotalMs;
    NSUInteger cellCount = _cellCount;
    double cellMax = _cellMaxMs;
    NSString *cellType = _cellMaxType ?: @"-";

    // Reset counters immediately (main thread)
    _frameWriteIndex = 0;
    _frameCount = 0;
    _lastRebuildMs = 0;
    _cellTotalMs = 0;
    _cellCount = 0;
    _cellMaxMs = 0;
    _cellMaxType = nil;

    // Compute stats + write on background queue (sort, format, file I/O)
    NSFileHandle *handle = self.logHandle;
    long queuePriority;
    if (@available(iOS 8.0, *)) {
        queuePriority = QOS_CLASS_UTILITY;
    } else {
        queuePriority = DISPATCH_QUEUE_PRIORITY_LOW;
    }
    dispatch_async(dispatch_get_global_queue(queuePriority, 0), ^{
        double fpsAvg = 0, fpsMin = 999, fpsP1 = 999;
        if (count > 0) {
            double totalInterval = 0, maxInterval = 0;
            for (NSUInteger i = 0; i < count; i++) {
                totalInterval += snapshotFrames[i];
                if (snapshotFrames[i] > maxInterval) maxInterval = snapshotFrames[i];
            }
            double avgInterval = totalInterval / count;
            fpsAvg = (avgInterval > 0) ? (1.0 / avgInterval) : 0;
            fpsMin = (maxInterval > 0) ? (1.0 / maxInterval) : 0;

            // P1 — copy to mutable for sort
            double sorted[kFrameRingSize];
            memcpy(sorted, snapshotFrames, count * sizeof(double));
            for (NSUInteger i = 1; i < count; i++) {
                double key = sorted[i];
                NSInteger j = (NSInteger)i - 1;
                while (j >= 0 && sorted[j] > key) { sorted[j + 1] = sorted[j]; j--; }
                sorted[j + 1] = key;
            }
            NSUInteger p1Index = (NSUInteger)(count * 0.99);
            if (p1Index >= count) p1Index = count - 1;
            fpsP1 = (sorted[p1Index] > 0) ? (1.0 / sorted[p1Index]) : 0;
        }

        double memMB = [self residentMemoryMB];
        double cellAvgMs = (cellCount > 0) ? (cellTotal / cellCount) : 0;
        NSTimeInterval ts = [[NSDate date] timeIntervalSince1970];

        NSString *line = [NSString stringWithFormat:@"%.0f,%.1f,%.1f,%.1f,%.1f,%.1f,%.2f,%.2f,%@\n",
            ts, fpsAvg, fpsMin, fpsP1, memMB, rebuildMs, cellAvgMs, cellMax, cellType];
        @synchronized(handle) {
            [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [handle synchronizeFile];
        }
        free(snapshotFrames);
    });
}

- (double)residentMemoryMB {
    struct mach_task_basic_info info;
    mach_msg_type_number_t size = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &size);
    if (kr == KERN_SUCCESS) {
        return (double)info.resident_size / (1024.0 * 1024.0);
    }
    return -1.0;
}

@end
