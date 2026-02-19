#import "HAStartupLog.h"
#import <UIKit/UIKit.h>
#include <mach/mach_time.h>

static NSFileHandle *_logHandle = nil;
static uint64_t _startTime = 0;
static mach_timebase_info_data_t _timebase;

@implementation HAStartupLog

+ (void)initialize {
    if (self != [HAStartupLog class]) return;

    _startTime = mach_absolute_time();
    mach_timebase_info(&_timebase);

    NSString *path = [self logPath];

    // Truncate any previous log
    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    _logHandle = [NSFileHandle fileHandleForWritingAtPath:path];

    // Header
    NSString *header = [NSString stringWithFormat:@"=== HA Dashboard startup log ===\nDevice: %@ / iOS %@\nDate: %@\n\n",
        [[UIDevice currentDevice] model],
        [[UIDevice currentDevice] systemVersion],
        [NSDate date]];
    [_logHandle writeData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    [_logHandle synchronizeFile];
}

+ (NSString *)logPath {
    // Prefer /tmp on jailbroken devices (world-readable via SSH)
    NSString *tmpPath = @"/tmp/ha-launch.log";
    if ([[NSFileManager defaultManager] isWritableFileAtPath:@"/tmp"]) {
        return tmpPath;
    }
    // Fall back to Documents (sandboxed)
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [docs stringByAppendingPathComponent:@"ha-launch.log"];
}

+ (void)log:(NSString *)message {
    if (!_logHandle) [self initialize]; // safety net

    uint64_t elapsed = mach_absolute_time() - _startTime;
    // Convert to milliseconds
    double ms = (double)elapsed * (double)_timebase.numer / (double)_timebase.denom / 1e6;

    NSString *line = [NSString stringWithFormat:@"+%8.1fms  %@\n", ms, message];

    // Write + flush immediately (survives watchdog kill)
    [_logHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [_logHandle synchronizeFile];

    // Also NSLog for syslog/console visibility
    NSLog(@"[HAStartup] +%.0fms %@", ms, message);
}

@end
