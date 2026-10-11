#import "HAConnectionManager.h"
#import "HAWebSocketClient.h"

NS_ASSUME_NONNULL_BEGIN

/// Exposes HAConnectionManager's private reconnect-backoff machinery to
/// HADashboardTests, so the backoff logic (attempt counter, delay/cap
/// computation, reset points, timer lifecycle) can be exercised directly
/// without waiting on real timers or a live WebSocket connection.
///
/// None of these members are implemented here — they're declared on the
/// primary class/extension in HAConnectionManager.m. This header only makes
/// the existing selectors visible to the test target.
@interface HAConnectionManager (TestAccess) <HAWebSocketClientDelegate>

@property (nonatomic, assign) NSInteger reconnectAttempt;
@property (nonatomic, strong, readonly, nullable) NSTimer *reconnectTimer;
@property (nonatomic, assign) BOOL intentionalDisconnect;

/// Deterministic jitter injection for -reconnectDelayForAttempt:. Defaults
/// to an arc4random()-based provider; tests should set this to a fixed-value
/// block (e.g. always 0 or always ~1) to pin down the expected delay bounds.
@property (nonatomic, copy) double (^reconnectJitterProvider)(void);

/// Pure delay computation for a given attempt number (1-based). Exposed so
/// tests can assert the exponential-growth/cap/jitter shape without
/// actually scheduling or waiting for timers.
- (NSTimeInterval)reconnectDelayForAttempt:(NSInteger)attempt;

/// Increments reconnectAttempt and (re)schedules a real NSTimer at the
/// computed delay. Tests call this directly to simulate a disconnect
/// without going through the WebSocket delegate machinery.
- (void)scheduleReconnect;

/// Simulates the reconnect timer firing (opens the socket via the
/// non-resetting path) without waiting for a real timer.
- (void)reconnectTimerFired;

- (void)cancelReconnect;

/// The non-attempt-resetting connection path used by the reconnect timer.
- (void)openWebSocketConnection;

@end

NS_ASSUME_NONNULL_END
