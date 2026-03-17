#import <XCTest/XCTest.h>
#import "HADashboardViewController.h"
#import "HAConnectionManager.h"
#import "HALovelaceParser.h"
#import "HAEntity.h"

// -----------------------------------------------------------------------
// Expose private properties for testing.
// -----------------------------------------------------------------------

@interface HADashboardViewController (TestAccess)
@property (nonatomic, assign) BOOL statesLoaded;
@property (nonatomic, assign) BOOL lovelaceLoaded;
@property (nonatomic, assign) BOOL lovelaceFetchDone;
@property (nonatomic, strong) HALovelaceDashboard *lovelaceDashboard;
@property (nonatomic, strong) UICollectionView *collectionView;

- (void)rebuildDashboard;
- (void)showLoading:(BOOL)loading message:(NSString *)message;
@end

@interface HAConnectionManager (TestAccess)
@property (nonatomic, strong) NSMutableDictionary<NSString *, HAEntity *> *entityStore;
@end

// -----------------------------------------------------------------------
// HADashboardRaceConditionTests
//
// Issue #4: User sees blank white screen on iPad 4 (iOS 10.3.4).
//
// Root cause hypothesis: When the dashboard config cache misses for the
// selected dashboard, the instant-launch path is skipped and statesLoaded
// stays NO. The WebSocket delivers the Lovelace config before the REST
// fetchAllStates call completes. rebuildDashboard was gated on
// statesLoaded, so it refused to render even though cached entities were
// available in the entity store.
//
// Fix: rebuildDashboard now promotes statesLoaded=YES when the entity
// store has cached entities, allowing rendering without waiting for REST.
//
// These tests verify the fix works and that the dashboard renders in all
// launch scenarios.
// -----------------------------------------------------------------------

@interface HADashboardRaceConditionTests : XCTestCase
@property (nonatomic, strong) HADashboardViewController *dashVC;
@end

@implementation HADashboardRaceConditionTests

- (void)setUp {
    [super setUp];
    // Clear singleton entity store from previous tests
    [[HAConnectionManager sharedManager] clearEntityStore];
    self.dashVC = [[HADashboardViewController alloc] init];
    [self.dashVC loadViewIfNeeded];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:self.dashVC];
    [window makeKeyAndVisible];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}

- (void)tearDown {
    self.dashVC = nil;
    [super tearDown];
}

- (HALovelaceDashboard *)dashboardWithCardCount:(NSUInteger)count {
    NSMutableArray *cards = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) {
        [cards addObject:@{
            @"type": @"entities",
            @"entities": @[
                @{@"entity": [NSString stringWithFormat:@"light.test_%lu", (unsigned long)i]}
            ]
        }];
    }
    NSDictionary *config = @{
        @"views": @[@{
            @"title": @"Home",
            @"cards": cards
        }]
    };
    return [HALovelaceParser parseDashboardFromDictionary:config];
}

- (void)populateEntityStore:(NSUInteger)count {
    HAConnectionManager *conn = [HAConnectionManager sharedManager];
    for (NSUInteger i = 0; i < count; i++) {
        NSString *entityId = [NSString stringWithFormat:@"light.test_%lu", (unsigned long)i];
        HAEntity *entity = [[HAEntity alloc] initWithDictionary:@{
            @"entity_id": entityId,
            @"state": @"on",
            @"attributes": @{@"friendly_name": [NSString stringWithFormat:@"Light %lu", (unsigned long)i]},
            @"last_changed": @"2026-03-17T02:41:00Z",
            @"last_updated": @"2026-03-17T02:41:00Z"
        }];
        conn.entityStore[entityId] = entity;
    }
}

#pragma mark - Fix Verification: Issue #4

/// FIX: When Lovelace config arrives from WebSocket before fetchAllStates
/// completes, rebuildDashboard now promotes statesLoaded using cached
/// entities from the store, allowing immediate rendering.
- (void)testFix_CachedEntitiesAllowRenderingBeforeRESTCompletes {
    [self populateEntityStore:10];

    self.dashVC.statesLoaded = NO;
    self.dashVC.lovelaceLoaded = NO;
    self.dashVC.lovelaceFetchDone = NO;
    [self.dashVC showLoading:YES message:@"Connecting..."];

    XCTAssertTrue(self.dashVC.collectionView.hidden,
                  @"Collection view should be hidden during loading");

    // WebSocket delivers Lovelace config before REST states complete
    self.dashVC.lovelaceDashboard = [self dashboardWithCardCount:10];
    self.dashVC.lovelaceLoaded = YES;
    self.dashVC.lovelaceFetchDone = YES;
    [self.dashVC rebuildDashboard];

    // FIX: rebuildDashboard promotes statesLoaded using cached entities
    XCTAssertFalse(self.dashVC.collectionView.hidden,
                   @"Collection view should be VISIBLE — rebuildDashboard should promote "
                   @"statesLoaded when cached entities exist in the store.");
    XCTAssertTrue(self.dashVC.statesLoaded,
                  @"statesLoaded should be promoted to YES by rebuildDashboard");
}

/// FIX: With 420 cached entities (matching user's setup), dashboard
/// renders immediately when config arrives, even without REST completion.
- (void)testFix_RaceConditionResolvedWith420CachedEntities {
    HAConnectionManager *conn = [HAConnectionManager sharedManager];
    [self populateEntityStore:420];
    XCTAssertEqual([conn allEntities].count, 420);

    self.dashVC.statesLoaded = NO;
    self.dashVC.lovelaceFetchDone = NO;
    [self.dashVC showLoading:YES message:@"Connecting..."];

    // WebSocket delivers config
    self.dashVC.lovelaceDashboard = [self dashboardWithCardCount:10];
    self.dashVC.lovelaceLoaded = YES;
    self.dashVC.lovelaceFetchDone = YES;
    [self.dashVC rebuildDashboard];

    XCTAssertFalse(self.dashVC.collectionView.hidden,
                   @"420 entities in store + 10-card config = should render immediately, "
                   @"not wait for REST fetchAllStates.");
}

/// Instant launch path still works correctly when both cache parts are present.
- (void)testInstantLaunch_BothCachedStillWorks {
    [self populateEntityStore:10];

    self.dashVC.statesLoaded = YES;
    self.dashVC.lovelaceLoaded = YES;
    self.dashVC.lovelaceFetchDone = YES;
    self.dashVC.lovelaceDashboard = [self dashboardWithCardCount:10];
    [self.dashVC showLoading:YES message:@"Connecting..."];
    [self.dashVC rebuildDashboard];

    XCTAssertFalse(self.dashVC.collectionView.hidden,
                   @"Instant launch with both entities and dashboard cached should render.");
}

/// When entity store is genuinely empty (first launch, no cache at all),
/// rebuildDashboard should still skip — we have nothing to show.
- (void)testSkip_EmptyEntityStoreStillBlocks {
    // Don't populate entity store — simulates first-ever launch
    self.dashVC.statesLoaded = NO;
    self.dashVC.lovelaceFetchDone = YES;
    self.dashVC.lovelaceLoaded = YES;
    self.dashVC.lovelaceDashboard = [self dashboardWithCardCount:10];
    [self.dashVC showLoading:YES message:@"Loading..."];

    [self.dashVC rebuildDashboard];

    XCTAssertTrue(self.dashVC.collectionView.hidden,
                  @"With zero entities in the store, rebuildDashboard should still skip — "
                  @"there's nothing to render.");
    XCTAssertFalse(self.dashVC.statesLoaded,
                   @"statesLoaded should NOT be promoted when entity store is empty.");
}

/// Verifies the user's workaround path still works.
- (void)testWorkaround_WiFiOffSettingsOnWorksViaCache {
    [self populateEntityStore:10];

    self.dashVC.statesLoaded = YES;
    self.dashVC.lovelaceLoaded = YES;
    self.dashVC.lovelaceFetchDone = YES;
    self.dashVC.lovelaceDashboard = [self dashboardWithCardCount:10];
    [self.dashVC showLoading:YES message:@"Connecting..."];
    [self.dashVC rebuildDashboard];

    XCTAssertFalse(self.dashVC.collectionView.hidden,
                   @"Workaround path (cached dashboard from Settings visit) should render.");
}

@end
