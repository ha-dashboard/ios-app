#import <XCTest/XCTest.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import "HACameraEntityCell.h"
#import "HAConnectionManager.h"
#import "HAEntity.h"

// -----------------------------------------------------------------------
// Issue #10: crash after pressing Home on iOS 10.
//
// Returning to the foreground rebuilds the dashboard twice. The second
// rebuild stopped the camera cell and started a second camera/stream
// request while the first was pending, so both responses reached
// playHLSURL:. The second call released the first AVPlayerLayer while it
// was still KVO-observed, which throws on iOS 10.
// -----------------------------------------------------------------------

typedef void (^HACommandCompletion)(id result, NSError *error);

@interface HACameraEntityCell (HLSTestAccess)
@property (nonatomic, copy) NSString *currentEntityId;
@property (nonatomic, strong) AVPlayer *hlsPlayer;
@property (nonatomic, strong) AVPlayerLayer *hlsPlayerLayer;
- (void)startHLSStream;
- (void)playHLSURL:(NSURL *)url;
- (void)stopRefresh;
- (void)stopHLSPlayer;
@end

@interface HACameraHLSTests : XCTestCase
@property (nonatomic, strong) HACameraEntityCell *cell;
@property (nonatomic, strong) HAEntity *entity;
@property (nonatomic, strong) NSMutableArray<HACommandCompletion> *capturedCompletions;
@property (nonatomic, assign) IMP originalSendCommand;
@end

@implementation HACameraHLSTests

- (void)setUp {
    [super setUp];
    self.entity = [[HAEntity alloc] initWithDictionary:@{
        @"entity_id": @"camera.front_door", @"state": @"idle",
        @"attributes": @{@"supported_features": @3}
    }];
    self.cell = [[HACameraEntityCell alloc] initWithFrame:CGRectMake(0, 0, 320, 200)];
    self.cell.entity = self.entity;
    self.cell.currentEntityId = self.entity.entityId;

    // Capture camera/stream completions instead of sending them over the WebSocket.
    self.capturedCompletions = [NSMutableArray array];
    NSMutableArray *captured = self.capturedCompletions;
    Method method = class_getInstanceMethod([HAConnectionManager class], @selector(sendCommand:completion:));
    self.originalSendCommand = method_setImplementation(method, imp_implementationWithBlock(
        ^(id manager, NSDictionary *command, HACommandCompletion completion) {
            [captured addObject:[completion copy]];
        }));
}

- (void)tearDown {
    [self.cell stopRefresh];
    Method method = class_getInstanceMethod([HAConnectionManager class], @selector(sendCommand:completion:));
    method_setImplementation(method, self.originalSendCommand);
    self.cell = nil;
    [super tearDown];
}

- (NSURL *)streamURL {
    return [NSURL URLWithString:@"http://127.0.0.1:9/api/hls/test/master_playlist.m3u8"];
}

- (void)testSecondPlayReleasesFirstPlayerObservers {
    [self.cell playHLSURL:[self streamURL]];
    AVPlayerLayer *firstLayer = self.cell.hlsPlayerLayer;
    AVPlayerItem *firstItem = self.cell.hlsPlayer.currentItem;
    XCTAssertNotNil(firstLayer);
    XCTAssertNotNil(firstItem);

    [self.cell playHLSURL:[self streamURL]];

    XCTAssertNotEqual(self.cell.hlsPlayerLayer, firstLayer, @"Second play should create a new layer");
    // Removing an observer that is not registered throws, so these only pass
    // once the cell has already detached from the replaced player.
    XCTAssertThrows([firstLayer removeObserver:self.cell forKeyPath:@"readyForDisplay"],
                    @"Cell must stop observing the first AVPlayerLayer when it is replaced");
    XCTAssertThrows([firstItem removeObserver:self.cell forKeyPath:@"status"],
                    @"Cell must stop observing the first AVPlayerItem when it is replaced");
}

- (void)testStaleStreamResponseIgnoredAfterStopRefresh {
    [self.cell startHLSStream];
    XCTAssertEqual(self.capturedCompletions.count, 1u);

    // Dashboard reload: the cell is stopped and immediately reloaded.
    [self.cell stopRefresh];
    [self.cell startHLSStream];
    XCTAssertEqual(self.capturedCompletions.count, 2u, @"Reload should issue a second request");

    NSDictionary *response = @{@"url": [self streamURL].absoluteString};
    self.capturedCompletions[0](response, nil);
    XCTAssertNil(self.cell.hlsPlayer, @"Response to the cancelled request must not start playback");

    self.capturedCompletions[1](response, nil);
    XCTAssertNotNil(self.cell.hlsPlayer, @"Response to the current request should start playback");
}

- (void)testStreamResponseAfterStopRefreshDoesNotPlay {
    [self.cell startHLSStream];
    [self.cell stopRefresh];

    self.capturedCompletions[0](@{@"url": [self streamURL].absoluteString}, nil);
    XCTAssertNil(self.cell.hlsPlayer, @"A stopped cell must not start playback");
}

@end
