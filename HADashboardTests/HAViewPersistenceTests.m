#import <XCTest/XCTest.h>
#import "HADashboardViewController.h"
#import "HAConnectionManager.h"
#import "HAAuthManager.h"
#import "HALovelaceParser.h"
#import "HAEntity.h"

// -----------------------------------------------------------------------
// Expose private properties/methods for testing.
// -----------------------------------------------------------------------

@interface HADashboardViewController (ViewPersistenceTestAccess)
@property (nonatomic, assign) BOOL statesLoaded;
@property (nonatomic, assign) BOOL lovelaceLoaded;
@property (nonatomic, assign) BOOL lovelaceFetchDone;
@property (nonatomic, strong) HALovelaceDashboard *lovelaceDashboard;
@property (nonatomic, assign) NSUInteger selectedViewIndex;
@property (nonatomic, strong) UICollectionView *collectionView;

- (void)rebuildDashboard;
- (void)showLoading:(BOOL)loading message:(NSString *)message;
- (void)connectionManager:(HAConnectionManager *)manager didReceiveLovelaceDashboard:(HALovelaceDashboard *)dashboard;
- (void)saveSelectedViewSelection;
@end

@interface HAConnectionManager (ViewPersistenceTestAccess)
@property (nonatomic, strong) NSMutableDictionary<NSString *, HAEntity *> *entityStore;
@end

// -----------------------------------------------------------------------
// Issue #9: After an app restart or device reboot, the app always goes
// back to the first Lovelace *view* (tab), even though the selected
// *dashboard* is persisted. These tests verify the fix: the last-selected
// view is persisted per dashboard and restored on launch / dashboard load,
// with a launch-argument override and a safe fallback when the saved view
// no longer exists.
// -----------------------------------------------------------------------

@interface HAViewPersistenceTests : XCTestCase
@property (nonatomic, strong) HADashboardViewController *dashVC;
@end

@implementation HAViewPersistenceTests

- (void)setUp {
    [super setUp];
    [[HAConnectionManager sharedManager] clearEntityStore];
    [self clearStoredViewSelections];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"HAViewIndex"];

    self.dashVC = [[HADashboardViewController alloc] init];
    [self.dashVC loadViewIfNeeded];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:self.dashVC];
    [window makeKeyAndVisible];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}

- (void)tearDown {
    self.dashVC = nil;
    [self clearStoredViewSelections];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"HAViewIndex"];
    [[HAAuthManager sharedManager] saveSelectedDashboardPath:nil];
    [super tearDown];
}

// Cleans up the NSUserDefaults key this feature writes to, so tests don't
// leak state into each other or into a real device's settings.
- (void)clearStoredViewSelections {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ha_last_selected_views"];
}

#pragma mark - Helpers

- (HALovelaceDashboard *)dashboardWithViewPaths:(NSArray<NSString *> *)paths {
    NSMutableArray *views = [NSMutableArray array];
    for (NSString *path in paths) {
        [views addObject:@{
            @"title": path,
            @"path": path,
            @"cards": @[@{
                @"type": @"entities",
                @"entities": @[@{@"entity": @"light.test_0"}]
            }]
        }];
    }
    NSDictionary *config = @{@"views": views};
    return [HALovelaceParser parseDashboardFromDictionary:config];
}

- (void)populateOneEntity {
    HAConnectionManager *conn = [HAConnectionManager sharedManager];
    HAEntity *entity = [[HAEntity alloc] initWithDictionary:@{
        @"entity_id": @"light.test_0",
        @"state": @"on",
        @"attributes": @{@"friendly_name": @"Test Light"},
        @"last_changed": @"2026-03-17T02:41:00Z",
        @"last_updated": @"2026-03-17T02:41:00Z"
    }];
    conn.entityStore[@"light.test_0"] = entity;
}

#pragma mark - Fix Verification: Issue #9

/// Selecting a view on one dashboard and then loading a *different*
/// dashboard, then coming back to the first, should restore the view
/// that was selected on the first dashboard (not reset to 0).
- (void)testFix_PersistsLastSelectedViewPerDashboard {
    [self populateOneEntity];

    HALovelaceDashboard *dashboardA = [self dashboardWithViewPaths:@[@"home", @"climate", @"security"]];

    self.dashVC.lovelaceLoaded = NO;
    [self.dashVC connectionManager:[HAConnectionManager sharedManager] didReceiveLovelaceDashboard:dashboardA];
    XCTAssertEqual(self.dashVC.selectedViewIndex, 0, @"First load should start at view 0");

    // User taps to view index 2 ("security") on dashboard A.
    self.dashVC.selectedViewIndex = 2;
    [self.dashVC saveSelectedViewSelection];

    // Switch to a different dashboard (simulates HAAuthManager path change).
    [[HAAuthManager sharedManager] saveSelectedDashboardPath:@"other-dashboard"];
    self.dashVC.lovelaceLoaded = NO;
    HALovelaceDashboard *dashboardB = [self dashboardWithViewPaths:@[@"only-view"]];
    [self.dashVC connectionManager:[HAConnectionManager sharedManager] didReceiveLovelaceDashboard:dashboardB];
    XCTAssertEqual(self.dashVC.selectedViewIndex, 0, @"Other dashboard has no saved view yet, should default to 0");

    // Switch back to dashboard A (nil / default path).
    [[HAAuthManager sharedManager] saveSelectedDashboardPath:nil];
    self.dashVC.lovelaceLoaded = NO;
    [self.dashVC connectionManager:[HAConnectionManager sharedManager] didReceiveLovelaceDashboard:dashboardA];

    XCTAssertEqual(self.dashVC.selectedViewIndex, 2,
                   @"Returning to dashboard A should restore its own last-selected view (index 2), "
                   @"not reset to view 0.");
}

/// Simulates an app restart: the view index is NOT persisted in the VC
/// (it's a fresh instance), only in HAAuthManager-backed storage. A new
/// HADashboardViewController loading the same dashboard should restore it.
- (void)testFix_RestoresSavedViewOnFreshLaunch {
    [self populateOneEntity];
    [[HAAuthManager sharedManager] saveSelectedDashboardPath:nil];

    HALovelaceDashboard *dashboard = [self dashboardWithViewPaths:@[@"home", @"climate", @"security"]];

    self.dashVC.lovelaceLoaded = NO;
    [self.dashVC connectionManager:[HAConnectionManager sharedManager] didReceiveLovelaceDashboard:dashboard];
    self.dashVC.selectedViewIndex = 1; // "climate"
    [self.dashVC saveSelectedViewSelection];

    // Simulate app restart: brand-new view controller instance, same
    // persisted NSUserDefaults state.
    HADashboardViewController *freshVC = [[HADashboardViewController alloc] init];
    [freshVC loadViewIfNeeded];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:freshVC];
    [window makeKeyAndVisible];

    [freshVC connectionManager:[HAConnectionManager sharedManager] didReceiveLovelaceDashboard:dashboard];

    XCTAssertEqual(freshVC.selectedViewIndex, 1,
                   @"A fresh launch should restore the previously-selected view (index 1), "
                   @"not always land back on view 0 (Issue #9).");
}

/// If the previously-selected view has since been removed from the
/// dashboard, restoring must fall back to view 0 rather than crashing
/// or pointing at an out-of-range/wrong index.
- (void)testFix_RemovedViewFallsBackToZero {
    [self populateOneEntity];
    [[HAAuthManager sharedManager] saveSelectedDashboardPath:nil];

    HALovelaceDashboard *original = [self dashboardWithViewPaths:@[@"home", @"climate", @"security"]];
    self.dashVC.lovelaceLoaded = NO;
    [self.dashVC connectionManager:[HAConnectionManager sharedManager] didReceiveLovelaceDashboard:original];
    self.dashVC.selectedViewIndex = 2; // "security"
    [self.dashVC saveSelectedViewSelection];

    // Dashboard reconfigured server-side: "security" view removed.
    HALovelaceDashboard *reduced = [self dashboardWithViewPaths:@[@"home", @"climate"]];
    self.dashVC.lovelaceLoaded = NO;
    [self.dashVC connectionManager:[HAConnectionManager sharedManager] didReceiveLovelaceDashboard:reduced];

    XCTAssertEqual(self.dashVC.selectedViewIndex, 0,
                   @"When the saved view no longer exists, restore should fall back to view 0.");
}

/// The -HAViewIndex launch argument (used by the screenshot test harness)
/// must still override any persisted selection.
- (void)testFix_LaunchArgumentOverridesPersistedSelection {
    [self populateOneEntity];
    [[HAAuthManager sharedManager] saveSelectedDashboardPath:nil];

    HALovelaceDashboard *dashboard = [self dashboardWithViewPaths:@[@"home", @"climate", @"security"]];
    self.dashVC.lovelaceLoaded = NO;
    [self.dashVC connectionManager:[HAConnectionManager sharedManager] didReceiveLovelaceDashboard:dashboard];
    self.dashVC.selectedViewIndex = 2;
    [self.dashVC saveSelectedViewSelection];

    // -HAViewIndex 1 should win even though index 2 was persisted.
    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"HAViewIndex"];

    HADashboardViewController *freshVC = [[HADashboardViewController alloc] init];
    [freshVC loadViewIfNeeded];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:freshVC];
    [window makeKeyAndVisible];

    [freshVC connectionManager:[HAConnectionManager sharedManager] didReceiveLovelaceDashboard:dashboard];

    XCTAssertEqual(freshVC.selectedViewIndex, 1,
                   @"-HAViewIndex launch argument must override the persisted view selection.");
}

/// Views can be reordered server-side (e.g. user drags a tab in the HA
/// Lovelace UI). Because views are matched by their stable `path`, not
/// positional index, the restored view should follow the path even when
/// its index in the array changes.
- (void)testFix_PathBasedRestoreSurvivesReordering {
    [self populateOneEntity];
    [[HAAuthManager sharedManager] saveSelectedDashboardPath:nil];

    HALovelaceDashboard *original = [self dashboardWithViewPaths:@[@"home", @"climate", @"security"]];
    self.dashVC.lovelaceLoaded = NO;
    [self.dashVC connectionManager:[HAConnectionManager sharedManager] didReceiveLovelaceDashboard:original];
    self.dashVC.selectedViewIndex = 2; // "security" at index 2
    [self.dashVC saveSelectedViewSelection];

    // Server reorders views: "security" is now at index 0.
    HALovelaceDashboard *reordered = [self dashboardWithViewPaths:@[@"security", @"home", @"climate"]];
    self.dashVC.lovelaceLoaded = NO;
    [self.dashVC connectionManager:[HAConnectionManager sharedManager] didReceiveLovelaceDashboard:reordered];

    XCTAssertEqual(self.dashVC.selectedViewIndex, 0,
                   @"Path-based matching should find \"security\" at its new index (0) after reordering, "
                   @"rather than resetting to the old positional index or view 0 by coincidence.");

    HALovelaceView *restoredView = reordered.views[self.dashVC.selectedViewIndex];
    XCTAssertEqualObjects(restoredView.path, @"security");
}

@end
