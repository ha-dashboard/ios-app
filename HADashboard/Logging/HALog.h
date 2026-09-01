#import <Foundation/Foundation.h>

/// Log severity levels, ordered from most verbose to most critical.
typedef NS_ENUM(NSInteger, HALogLevel) {
    HALogLevelDebug = 0,   // Verbose: camera frames, data sizes, polling
    HALogLevelInfo,        // Normal: connections, state changes, stream starts
    HALogLevelWarning,     // Noteworthy: fallbacks, retries, timeouts
    HALogLevelError,       // Failures: crashes, service errors, parse failures
};

/// Unified file logger for HA Dashboard.
///
/// Writes to Documents/ha-log.txt with 2-file rotation at 2MB.
/// Thread-safe. iOS 9 compatible. No external dependencies.
@interface HALog : NSObject

/// Log at specific levels with module tag.
+ (void)debug:(NSString *)tag format:(NSString *)fmt, ... NS_FORMAT_FUNCTION(2,3);
+ (void)info:(NSString *)tag format:(NSString *)fmt, ... NS_FORMAT_FUNCTION(2,3);
+ (void)warn:(NSString *)tag format:(NSString *)fmt, ... NS_FORMAT_FUNCTION(2,3);
+ (void)error:(NSString *)tag format:(NSString *)fmt, ... NS_FORMAT_FUNCTION(2,3);

/// Runtime configuration. Min level persisted to NSUserDefaults.
+ (void)setMinLevel:(HALogLevel)level;
+ (HALogLevel)minLevel;
+ (void)setFileLoggingEnabled:(BOOL)enabled;
+ (void)setConsoleLoggingEnabled:(BOOL)enabled;

/// File management.
+ (NSString *)currentLogFilePath;
+ (NSString *)previousLogFilePath;
+ (void)flush;

/// Remove current and rotated logs, then start a fresh local session log.
+ (void)clearLogs;

/// Startup profiling mode (replaces HAStartupLog).
/// Uses mach_absolute_time offsets for the first 30 seconds, then wall clock.
+ (void)logStartup:(NSString *)message;

/// Install crash handlers (uncaught exceptions + POSIX signals).
/// Call once from main(), before UIApplicationMain.
/// Writes crash info + stack trace to the log file and flushes.
+ (void)installCrashHandler;

/// Write a raw line to the log file bypassing level checks.
/// Used internally by the crash handler; safe to call from signal context
/// only for the synchronous-signal-safe subset (the Obj-C path is best-effort).
+ (void)logCrashMessage:(NSString *)message;

@end

// Convenience macros — runtime filtered, not compile-time stripped,
// so users can enable debug logging to share diagnostics.
#define HALogD(tag, fmt, ...) [HALog debug:tag format:fmt, ##__VA_ARGS__]
#define HALogI(tag, fmt, ...) [HALog info:tag format:fmt, ##__VA_ARGS__]
#define HALogW(tag, fmt, ...) [HALog warn:tag format:fmt, ##__VA_ARGS__]
#define HALogE(tag, fmt, ...) [HALog error:tag format:fmt, ##__VA_ARGS__]
