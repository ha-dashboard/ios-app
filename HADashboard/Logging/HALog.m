#import "HALog.h"
#import <UIKit/UIKit.h>
#include <mach/mach_time.h>
#include <signal.h>
#include <execinfo.h>

static NSString *const kHALogMinLevelKey = @"HALogMinLevel";
static NSString *const kHALogFileName = @"ha-log.txt";
static NSString *const kHALogPreviousFileName = @"ha-log-prev.txt";
static const NSUInteger kHALogMaxFileSize = 2 * 1024 * 1024; // 2MB
static const NSTimeInterval kHALogStartupWindow = 30.0; // seconds

static NSString *_logLevelNames[] = { @"DEBUG", @"INFO", @"WARN", @"ERROR" };

@implementation HALog {
}

// -- State (file-scoped statics for simplicity in Obj-C class methods) --

static NSFileHandle *_fileHandle = nil;
static NSString *_currentPath = nil;
static NSString *_previousPath = nil;
static HALogLevel _minLevel = HALogLevelInfo;
static BOOL _fileLoggingEnabled = YES;
static BOOL _consoleLoggingEnabled = YES;
static BOOL _initialized = NO;

// Startup profiling state (absorbed from HAStartupLog)
static uint64_t _processStartTime = 0;
static mach_timebase_info_data_t _timebase;
static NSDate *_initDate = nil;

#pragma mark - Initialization

+ (void)initialize {
    if (self != [HALog class]) return;

    _processStartTime = mach_absolute_time();
    mach_timebase_info(&_timebase);
    _initDate = [NSDate date];

    // Restore persisted min level (objectForKey: returns nil if never set,
    // vs integerForKey: which returns 0 == HALogLevelDebug)
    NSNumber *stored = [[NSUserDefaults standardUserDefaults] objectForKey:kHALogMinLevelKey];
    if (stored && stored.integerValue >= HALogLevelDebug && stored.integerValue <= HALogLevelError) {
        _minLevel = (HALogLevel)stored.integerValue;
    }
    // Also support launch argument: -HALogMinLevel 0 (debug) / 1 (info) / 2 (warn) / 3 (error)
    // NSUserDefaults automatically picks up command-line arguments.

#ifdef DEBUG
    _consoleLoggingEnabled = YES;
#else
    _consoleLoggingEnabled = NO;
#endif

    [self _openLogFile];
    _initialized = YES;
}

+ (void)_openLogFile {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    _currentPath = [docs stringByAppendingPathComponent:kHALogFileName];
    _previousPath = [docs stringByAppendingPathComponent:kHALogPreviousFileName];

    // Create file if it doesn't exist
    if (![[NSFileManager defaultManager] fileExistsAtPath:_currentPath]) {
        [[NSFileManager defaultManager] createFileAtPath:_currentPath
                                                contents:nil
                                              attributes:nil];
    }

    _fileHandle = [NSFileHandle fileHandleForWritingAtPath:_currentPath];
    [_fileHandle seekToEndOfFile];

    // Write session header
    @try {
        NSString *header = [NSString stringWithFormat:
            @"\n=== HA Dashboard log session ===\n"
            @"Device: %@ / iOS %@\n"
            @"Date: %@\n"
            @"Min level: %@\n\n",
            [[UIDevice currentDevice] model],
            [[UIDevice currentDevice] systemVersion],
            [NSDate date],
            _logLevelNames[_minLevel]];
        [_fileHandle writeData:[header dataUsingEncoding:NSUTF8StringEncoding]];
        [_fileHandle synchronizeFile];
    } @catch (NSException *e) {
        NSLog(@"[HALog] Failed to write session header: %@", e.reason);
        _fileHandle = nil;
    }
}

#pragma mark - Public API

+ (void)debug:(NSString *)tag format:(NSString *)fmt, ... {
    if (_minLevel > HALogLevelDebug) return;
    va_list args;
    va_start(args, fmt);
    [self _logLevel:HALogLevelDebug tag:tag format:fmt args:args];
    va_end(args);
}

+ (void)info:(NSString *)tag format:(NSString *)fmt, ... {
    if (_minLevel > HALogLevelInfo) return;
    va_list args;
    va_start(args, fmt);
    [self _logLevel:HALogLevelInfo tag:tag format:fmt args:args];
    va_end(args);
}

+ (void)warn:(NSString *)tag format:(NSString *)fmt, ... {
    if (_minLevel > HALogLevelWarning) return;
    va_list args;
    va_start(args, fmt);
    [self _logLevel:HALogLevelWarning tag:tag format:fmt args:args];
    va_end(args);
}

+ (void)error:(NSString *)tag format:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    [self _logLevel:HALogLevelError tag:tag format:fmt args:args];
    va_end(args);
}

+ (void)logStartup:(NSString *)message {
    if (!_initialized) [self initialize];

    uint64_t elapsed = mach_absolute_time() - _processStartTime;
    double ms = (double)elapsed * (double)_timebase.numer
                / (double)_timebase.denom / 1e6;

    NSString *line = [NSString stringWithFormat:@"+%8.1fms  [startup] %@\n", ms, message];

    @synchronized(self) {
        [self _writeToFile:line];
    }

    if (_consoleLoggingEnabled) {
        NSLog(@"[startup] +%.0fms %@", ms, message);
    }
}

+ (void)setMinLevel:(HALogLevel)level {
    _minLevel = level;
    [[NSUserDefaults standardUserDefaults] setInteger:level forKey:kHALogMinLevelKey];
}

+ (HALogLevel)minLevel {
    return _minLevel;
}

+ (void)setFileLoggingEnabled:(BOOL)enabled {
    _fileLoggingEnabled = enabled;
}

+ (void)setConsoleLoggingEnabled:(BOOL)enabled {
    _consoleLoggingEnabled = enabled;
}

+ (NSString *)currentLogFilePath {
    if (!_initialized) [self initialize];
    return _currentPath;
}

+ (NSString *)previousLogFilePath {
    if (!_initialized) [self initialize];
    return _previousPath;
}

+ (void)flush {
    @synchronized(self) {
        @try {
            [_fileHandle synchronizeFile];
        } @catch (NSException *e) {
            // Silently ignore — file may have been invalidated
        }
    }
}

+ (void)clearLogs {
    @synchronized(self) {
        @try {
            [_fileHandle synchronizeFile];
            [_fileHandle closeFile];
        } @catch (NSException *exception) {
            (void)exception;
        }
        _fileHandle = nil;
        NSFileManager *manager = [NSFileManager defaultManager];
        if (_currentPath.length) [manager removeItemAtPath:_currentPath error:nil];
        if (_previousPath.length) [manager removeItemAtPath:_previousPath error:nil];
        [self _openLogFile];
    }
}

#pragma mark - Internal

+ (void)_logLevel:(HALogLevel)level
              tag:(NSString *)tag
           format:(NSString *)fmt
             args:(va_list)args {
    if (!_initialized) [self initialize];

    NSString *message = [[NSString alloc] initWithFormat:fmt arguments:args];

    // Build timestamp
    NSString *timestamp;
    NSTimeInterval sinceInit = -[_initDate timeIntervalSinceNow];
    if (sinceInit < kHALogStartupWindow) {
        // Startup mode: mach_absolute_time offsets
        uint64_t elapsed = mach_absolute_time() - _processStartTime;
        double ms = (double)elapsed * (double)_timebase.numer
                    / (double)_timebase.denom / 1e6;
        timestamp = [NSString stringWithFormat:@"+%8.1fms", ms];
    } else {
        // Normal mode: wall clock HH:mm:ss.SSS
        timestamp = [self _wallClockTimestamp];
    }

    NSString *line = [NSString stringWithFormat:@"%@ %5s [%@] %@\n",
        timestamp,
        _logLevelNames[level].UTF8String,
        tag,
        message];

    @synchronized(self) {
        if (_fileLoggingEnabled) {
            [self _writeToFile:line];
        }
    }

    // Auto-flush on error
    if (level == HALogLevelError) {
        [self flush];
    }

    if (_consoleLoggingEnabled) {
        NSLog(@"[%@] %@", tag, message);
    }
}

+ (NSString *)_wallClockTimestamp {
    // Manual formatting for iOS 9 perf (avoid NSDateFormatter allocation)
    NSDate *now = [NSDate date];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:(NSCalendarUnitHour |
                                           NSCalendarUnitMinute |
                                           NSCalendarUnitSecond)
                                 fromDate:now];
    NSTimeInterval frac = [now timeIntervalSince1970];
    int millis = (int)((frac - floor(frac)) * 1000);
    return [NSString stringWithFormat:@"%02ld:%02ld:%02ld.%03d",
        (long)c.hour, (long)c.minute, (long)c.second, millis];
}

+ (void)_writeToFile:(NSString *)line {
    if (!_fileHandle) return;

    @try {
        [_fileHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];

        // Check rotation
        unsigned long long size = [_fileHandle offsetInFile];
        if (size >= kHALogMaxFileSize) {
            [self _rotateLogFile];
        }
    } @catch (NSException *e) {
        _fileHandle = nil; // Disk full or gone — disable file logging
    }
}

#pragma mark - Crash Handling

static NSUncaughtExceptionHandler *_previousExceptionHandler = nil;

/// Signals we trap. All are synchronous (caused by the crashing thread itself),
/// so our handler runs on the same thread — no cross-thread issues.
static const int kCrashSignals[] = { SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL };
static const int kCrashSignalCount = sizeof(kCrashSignals) / sizeof(kCrashSignals[0]);
static struct sigaction _previousSignalActions[5]; // indexed same as kCrashSignals

static void _HACrashExceptionHandler(NSException *exception) {
    NSString *message = [NSString stringWithFormat:
        @"\n\n=== CRASH: Uncaught Exception ===\n"
        @"Name: %@\n"
        @"Reason: %@\n"
        @"Stack:\n%@\n"
        @"=================================\n",
        exception.name,
        exception.reason,
        [exception.callStackSymbols componentsJoinedByString:@"\n"]];
    [HALog logCrashMessage:message];

    // Forward to previous handler if any
    if (_previousExceptionHandler) {
        _previousExceptionHandler(exception);
    }
}

static void _HACrashSignalHandler(int sig) {
    // backtrace() is async-signal-safe on Darwin.
    void *frames[128];
    int count = backtrace(frames, 128);
    char **symbols = backtrace_symbols(frames, count);

    NSMutableString *message = [NSMutableString stringWithFormat:
        @"\n\n=== CRASH: Signal %d (%s) ===\nStack:\n",
        sig, strsignal(sig)];
    if (symbols) {
        for (int i = 0; i < count; i++) {
            [message appendFormat:@"%s\n", symbols[i]];
        }
        free(symbols);
    }
    [message appendString:@"=================================\n"];
    [HALog logCrashMessage:message];

    // Restore default handler and re-raise so the OS gets the crash
    signal(sig, SIG_DFL);
    raise(sig);
}

+ (void)installCrashHandler {
    // Ensure log file is open
    if (!_initialized) [self initialize];

    // Uncaught Obj-C exceptions
    _previousExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(&_HACrashExceptionHandler);

    // POSIX signals
    for (int i = 0; i < kCrashSignalCount; i++) {
        struct sigaction action = {0};
        action.sa_handler = &_HACrashSignalHandler;
        sigemptyset(&action.sa_mask);
        sigaction(kCrashSignals[i], &action, &_previousSignalActions[i]);
    }

    HALogI(@"log", @"Crash handler installed");
}

+ (void)logCrashMessage:(NSString *)message {
    // Best-effort write directly to the file handle.
    // We're in a crash context so keep it minimal.
    @synchronized(self) {
        @try {
            if (_fileHandle) {
                [_fileHandle writeData:[message dataUsingEncoding:NSUTF8StringEncoding]];
                [_fileHandle synchronizeFile];
            }
        } @catch (NSException *e) {
            // Nothing we can do
        }
    }
    // Also try NSLog in case the file is gone
    NSLog(@"[HALog CRASH] %@", message);
}

+ (void)_rotateLogFile {
    @try {
        [_fileHandle synchronizeFile];
        [_fileHandle closeFile];
    } @catch (NSException *e) {
        // Ignore close errors
    }
    _fileHandle = nil;

    NSFileManager *fm = [NSFileManager defaultManager];

    // Delete previous log
    [fm removeItemAtPath:_previousPath error:nil];

    // Current -> previous
    [fm moveItemAtPath:_currentPath toPath:_previousPath error:nil];

    // Create new current
    [fm createFileAtPath:_currentPath contents:nil attributes:nil];
    _fileHandle = [NSFileHandle fileHandleForWritingAtPath:_currentPath];
}

@end
