#import <Foundation/Foundation.h>

/// Lightweight startup tracer. Writes timestamped lines to /tmp/ha-launch.log
/// (jailbroken) or Documents/ha-launch.log (sandboxed). Each line includes
/// milliseconds since app start so we can pinpoint exactly where the main
/// thread blocks during scene creation.
@interface HAStartupLog : NSObject

/// Log a milestone with elapsed time since process start.
+ (void)log:(NSString *)message;

/// Flush and return the log file path (for display or retrieval).
+ (NSString *)logPath;

@end
