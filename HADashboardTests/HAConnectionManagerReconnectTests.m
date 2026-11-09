#import <XCTest/XCTest.h>
#import "HAConnectionManager.h"
#import "HAConnectionManager+TestAccess.h"
#import "HAAuthManager.h"

/// Regression tests for the WebSocket reconnect backoff (device-soak bug:
/// every timer-driven retry logged "attempt 1" and fired every 2s
/// indefinitely, because the reconnect timer's target, -connect, reset
/// reconnectAttempt back to 0 before the next -scheduleReconnect could
/// compute a grown delay from it).
///
/// These tests drive HAConnectionManager's private reconnect machinery
/// directly through the HAConnectionManager+TestAccess category, using a
/// fresh instance (not +sharedManager) so they don't interact with the
/// host app's own connection, and a deterministic jitter provider so the
/// delay assertions aren't flaky.
@interface HAConnectionManagerReconnectTests : XCTestCase
@end

@implementation HAConnectionManagerReconnectTests

- (HAConnectionManager *)freshManagerWithMinJitter {
    HAConnectionManager *mgr = [[HAConnectionManager alloc] init];
    mgr.reconnectJitterProvider = ^double { return 0.0; };
    return mgr;
}

- (void)tearDownManager:(HAConnectionManager *)mgr {
    [mgr cancelReconnect];
}

#pragma mark - Attempt counter

/// The core regression: repeated timer-driven disconnects must increase the
/// attempt counter monotonically, never reset it back to 0/1 along the way.
- (void)testTimerDrivenRetriesIncreaseAttemptWithoutReset {
    HAConnectionManager *mgr = [self freshManagerWithMinJitter];

    XCTAssertEqual(mgr.reconnectAttempt, 0);

    for (NSInteger expected = 1; expected <= 6; expected++) {
        // Simulate the WebSocket dropping again (this is what
        // -scheduleReconnect is invoked from in production).
        [mgr webSocketClient:nil didDisconnectWithError:nil];
        XCTAssertEqual(mgr.reconnectAttempt, expected,
            @"attempt counter must increase monotonically across timer-driven retries, not reset");
    }

    [self tearDownManager:mgr];
}

#pragma mark - Delay / cap

- (void)testBackoffDelayGrowsExponentiallyThenCaps {
    HAConnectionManager *mgr = [[HAConnectionManager alloc] init];

    // Pin jitter to its minimum (0.0) so the "ramping up" phase delays are
    // exactly the base exponential values times the jitter floor (0.85).
    mgr.reconnectJitterProvider = ^double { return 0.0; };

    NSTimeInterval delay1 = [mgr reconnectDelayForAttempt:1];
    NSTimeInterval delay2 = [mgr reconnectDelayForAttempt:2];
    NSTimeInterval delay3 = [mgr reconnectDelayForAttempt:3];
    NSTimeInterval delay4 = [mgr reconnectDelayForAttempt:4];

    // Base sequence is 2, 4, 8, 16s with a ±15% jitter band.
    XCTAssertEqualWithAccuracy(delay1, 2.0 * 0.85, 0.01);
    XCTAssertEqualWithAccuracy(delay2, 4.0 * 0.85, 0.01);
    XCTAssertEqualWithAccuracy(delay3, 8.0 * 0.85, 0.01);
    XCTAssertEqualWithAccuracy(delay4, 16.0 * 0.85, 0.01);

    // Still increasing attempt-over-attempt while ramping up.
    XCTAssertLessThan(delay1, delay2);
    XCTAssertLessThan(delay2, delay3);
    XCTAssertLessThan(delay3, delay4);

    // Once the uncapped exponential value reaches 30s, the delay must stay
    // within [30, 60] forever after — it must never grow unbounded, and it
    // must never drop below the cap either.
    for (NSInteger attempt = 5; attempt <= 12; attempt++) {
        NSTimeInterval delay = [mgr reconnectDelayForAttempt:attempt];
        XCTAssertGreaterThanOrEqual(delay, 30.0, @"attempt %ld should be within the steady-state band", (long)attempt);
        XCTAssertLessThanOrEqual(delay, 60.0, @"attempt %ld should never exceed the hard cap", (long)attempt);
    }

    // With max jitter, the steady state should approach the 60s ceiling.
    mgr.reconnectJitterProvider = ^double { return 0.999999; };
    NSTimeInterval steadyMax = [mgr reconnectDelayForAttempt:8];
    XCTAssertEqualWithAccuracy(steadyMax, 60.0, 0.01);

    // With zero jitter, the steady state should sit at the 30s floor.
    mgr.reconnectJitterProvider = ^double { return 0.0; };
    NSTimeInterval steadyMin = [mgr reconnectDelayForAttempt:8];
    XCTAssertEqualWithAccuracy(steadyMin, 30.0, 0.01);
}

#pragma mark - Reset points

/// A successful authentication must reset the attempt counter back to 0
/// and cancel any pending backoff timer left over from before the retry
/// that just succeeded.
- (void)testSuccessfulAuthenticationResetsAttemptAndCancelsTimer {
    HAConnectionManager *mgr = [self freshManagerWithMinJitter];

    for (NSInteger i = 0; i < 4; i++) {
        [mgr scheduleReconnect];
    }
    XCTAssertEqual(mgr.reconnectAttempt, 4);
    XCTAssertNotNil(mgr.reconnectTimer);

    [mgr webSocketClientDidAuthenticate:nil];

    XCTAssertEqual(mgr.reconnectAttempt, 0, @"successful auth must reset the backoff");
    XCTAssertNil(mgr.reconnectTimer, @"successful auth must cancel any pending backoff timer");

    [self tearDownManager:mgr];
}

/// -connect (the user/foreground entry point) must reset the backoff state
/// immediately, even if a retry was already pending from a prior outage.
- (void)testExplicitConnectResetsBackoffImmediately {
    HAConnectionManager *mgr = [self freshManagerWithMinJitter];

    HAAuthManager *auth = [HAAuthManager sharedManager];
    // Point at an address nothing is listening on — we only care that
    // -connect takes the "configured" branch and resets state synchronously
    // before any (necessarily async) socket I/O happens.
    [auth saveOAuthCredentials:@"http://127.0.0.1:1"
                   accessToken:@"test-access"
                  refreshToken:@"test-refresh"
                     expiresIn:3600];

    for (NSInteger i = 0; i < 3; i++) {
        [mgr scheduleReconnect];
    }
    XCTAssertEqual(mgr.reconnectAttempt, 3);
    XCTAssertNotNil(mgr.reconnectTimer);

    [mgr connect];

    XCTAssertEqual(mgr.reconnectAttempt, 0, @"-connect must reset the attempt counter");
    XCTAssertNil(mgr.reconnectTimer, @"-connect must cancel any pending backoff timer");
    XCTAssertFalse(mgr.intentionalDisconnect);

    [mgr disconnect];
    [auth clearCredentials];
}

#pragma mark - Timer lifecycle

/// -disconnect must never leave a reconnect timer running.
- (void)testDisconnectLeavesNoReconnectTimerPending {
    HAConnectionManager *mgr = [self freshManagerWithMinJitter];

    [mgr scheduleReconnect];
    XCTAssertNotNil(mgr.reconnectTimer);

    [mgr disconnect];

    XCTAssertNil(mgr.reconnectTimer, @"disconnect must invalidate any pending reconnect timer");
}

/// An intentional disconnect must suppress further reconnect scheduling —
/// e.g. the disconnect notification firing after -disconnect was already
/// called must not resurrect a backoff timer.
- (void)testIntentionalDisconnectSuppressesReconnectScheduling {
    HAConnectionManager *mgr = [self freshManagerWithMinJitter];

    [mgr disconnect]; // sets intentionalDisconnect = YES
    [mgr webSocketClient:nil didDisconnectWithError:nil];

    XCTAssertNil(mgr.reconnectTimer, @"an intentional disconnect must not schedule a reconnect");
    XCTAssertEqual(mgr.reconnectAttempt, 0);
}

@end
