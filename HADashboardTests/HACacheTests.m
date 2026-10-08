#import <XCTest/XCTest.h>
#import "HACacheManager.h"
#import "HAEntityStateCache.h"
#import "HADashboardConfigCache.h"
#import "HAEntity.h"

#pragma mark - HACacheManager Tests

@interface HACacheManagerTests : XCTestCase
@property (nonatomic, strong) HACacheManager *manager;
@end

@implementation HACacheManagerTests

- (void)setUp {
    [super setUp];
    self.manager = [HACacheManager sharedManager];
    self.manager.serverURL = @"http://test-server.local:8123";
}

- (void)tearDown {
    [self.manager clearAllCaches];
    [super tearDown];
}

- (void)testCacheDirectoryCreatedWithSHA256Prefix {
    NSString *dir = [self.manager persistentCacheDirectory];
    XCTAssertNotNil(dir, @"persistentCacheDirectory should not be nil");
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:dir],
                  @"Cache directory should be created on disk");
    // Directory name should be a hex string (SHA256 prefix)
    NSString *dirName = [dir lastPathComponent];
    XCTAssertEqual(dirName.length, 16, @"SHA256 prefix should be 16 hex chars (8 bytes)");
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    NSCharacterSet *dirChars = [NSCharacterSet characterSetWithCharactersInString:dirName];
    XCTAssertTrue([hexSet isSupersetOfSet:dirChars], @"Directory name should be hex chars only");
}

- (void)testDifferentServerURLsProduceDifferentDirectories {
    self.manager.serverURL = @"http://server-a.local:8123";
    NSString *dirA = [self.manager persistentCacheDirectory];

    self.manager.serverURL = @"http://server-b.local:8123";
    NSString *dirB = [self.manager persistentCacheDirectory];

    XCTAssertNotEqualObjects(dirA, dirB,
        @"Different server URLs should produce different cache directories");

    // Clean up both
    [[NSFileManager defaultManager] removeItemAtPath:dirA error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:dirB error:nil];
}

- (void)testWriteJSONReadJSONRoundTrip {
    NSDictionary *testData = @{@"key": @"value", @"number": @42, @"nested": @{@"a": @YES}};
    XCTestExpectation *exp = [self expectationWithDescription:@"write completes"];

    [self.manager writeJSON:testData toFile:@"test-roundtrip.json" completion:^(BOOL success) {
        XCTAssertTrue(success, @"Write should succeed");
        [exp fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];

    id readBack = [self.manager readJSONFromFile:@"test-roundtrip.json"];
    XCTAssertNotNil(readBack, @"Read should return data");
    XCTAssertTrue([readBack isKindOfClass:[NSDictionary class]], @"Should be a dictionary");
    XCTAssertEqualObjects(readBack[@"key"], @"value");
    XCTAssertEqualObjects(readBack[@"number"], @42);
    XCTAssertEqualObjects(readBack[@"nested"][@"a"], @YES);
}

- (void)testWriteJSONSyncRoundTrip {
    NSArray *testData = @[@"one", @"two", @"three"];
    BOOL ok = [self.manager writeJSONSync:testData toFile:@"test-sync.json"];
    XCTAssertTrue(ok, @"Sync write should succeed");

    id readBack = [self.manager readJSONFromFile:@"test-sync.json"];
    XCTAssertTrue([readBack isKindOfClass:[NSArray class]]);
    XCTAssertEqual([readBack count], 3);
}

- (void)testReadJSONReturnsNilForMissingFile {
    id result = [self.manager readJSONFromFile:@"nonexistent-file.json"];
    XCTAssertNil(result, @"Reading a missing file should return nil");
}

- (void)testReadJSONReturnsNilForCorruptedJSON {
    // Write garbage data directly to disk
    NSString *dir = [self.manager persistentCacheDirectory];
    NSString *path = [dir stringByAppendingPathComponent:@"corrupt.json"];
    [@"this is not valid json {{{" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];

    id result = [self.manager readJSONFromFile:@"corrupt.json"];
    XCTAssertNil(result, @"Corrupted JSON should return nil");

    // Verify corrupt file was cleaned up
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:path],
                   @"Corrupt cache file should be deleted");
}

- (void)testDeleteCacheFile {
    [self.manager writeJSONSync:@{@"k": @"v"} toFile:@"delete-me.json"];
    XCTAssertNotNil([self.manager readJSONFromFile:@"delete-me.json"]);

    [self.manager deleteCacheFile:@"delete-me.json"];
    XCTAssertNil([self.manager readJSONFromFile:@"delete-me.json"],
                 @"Deleted file should not be readable");
}

- (void)testClearAllCachesRemovesDirectory {
    [self.manager writeJSONSync:@{@"k": @"v"} toFile:@"cleartest.json"];
    NSString *dir = [self.manager persistentCacheDirectory];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:dir]);

    [self.manager clearAllCaches];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:dir],
                   @"clearAllCaches should remove the directory");
}

@end

#pragma mark - HAEntityStateCache Tests

@interface HAEntityStateCacheTests : XCTestCase
@end

@implementation HAEntityStateCacheTests

- (void)setUp {
    [super setUp];
    [HACacheManager sharedManager].serverURL = @"http://entity-cache-test.local:8123";
}

- (void)tearDown {
    [[HACacheManager sharedManager] clearAllCaches];
    [super tearDown];
}

- (void)testWriteAndReadRoundTrip {
    // Create test entities
    HAEntity *light = [[HAEntity alloc] initWithDictionary:@{
        @"entity_id": @"light.living_room",
        @"state": @"on",
        @"attributes": @{@"friendly_name": @"Living Room Light", @"brightness": @255},
        @"last_changed": @"2026-03-02T10:00:00Z",
        @"last_updated": @"2026-03-02T10:00:00Z"
    }];
    HAEntity *sensor = [[HAEntity alloc] initWithDictionary:@{
        @"entity_id": @"sensor.temperature",
        @"state": @"21.5",
        @"attributes": @{@"friendly_name": @"Temperature", @"unit_of_measurement": @"°C"},
        @"last_changed": @"2026-03-02T10:01:00Z",
        @"last_updated": @"2026-03-02T10:01:00Z"
    }];

    NSDictionary *entities = @{
        @"light.living_room": light,
        @"sensor.temperature": sensor
    };

    // Write via entitiesDidUpdate + immediate flush
    HAEntityStateCache *cache = [HAEntityStateCache sharedCache];
    [cache entitiesDidUpdate:entities];
    [cache flushToDisk];

    // Read back
    NSDictionary *cached = [cache loadCachedStates];
    XCTAssertNotNil(cached, @"Cached states should exist after flush");
    XCTAssertEqual(cached.count, 2, @"Should have 2 entities");

    NSDictionary *lightDict = cached[@"light.living_room"];
    XCTAssertNotNil(lightDict);
    XCTAssertEqualObjects(lightDict[@"state"], @"on");
    XCTAssertEqualObjects(lightDict[@"attributes"][@"brightness"], @255);
    XCTAssertEqualObjects(lightDict[@"attributes"][@"friendly_name"], @"Living Room Light");

    NSDictionary *sensorDict = cached[@"sensor.temperature"];
    XCTAssertNotNil(sensorDict);
    XCTAssertEqualObjects(sensorDict[@"state"], @"21.5");
    XCTAssertEqualObjects(sensorDict[@"attributes"][@"unit_of_measurement"], @"°C");
}

- (void)testHasCachedStatesReturnsFalseWhenEmpty {
    XCTAssertFalse([[HAEntityStateCache sharedCache] hasCachedStates],
                   @"Should return NO when no cache exists");
}

- (void)testHasCachedStatesReturnsTrueAfterWrite {
    HAEntity *e = [[HAEntity alloc] initWithDictionary:@{
        @"entity_id": @"switch.test", @"state": @"off", @"attributes": @{}
    }];
    HAEntityStateCache *cache = [HAEntityStateCache sharedCache];
    [cache entitiesDidUpdate:@{@"switch.test": e}];
    [cache flushToDisk];
    XCTAssertTrue([cache hasCachedStates], @"Should return YES after flush");
}

- (void)testFlushToDiskBypassesDebounce {
    // Write entities, then immediately flush — should write synchronously
    HAEntity *e = [[HAEntity alloc] initWithDictionary:@{
        @"entity_id": @"light.flush_test", @"state": @"on", @"attributes": @{}
    }];
    HAEntityStateCache *cache = [HAEntityStateCache sharedCache];
    [cache entitiesDidUpdate:@{@"light.flush_test": e}];

    // flushToDisk is synchronous — file should exist immediately after
    [cache flushToDisk];

    NSDictionary *cached = [cache loadCachedStates];
    XCTAssertNotNil(cached, @"Cache should exist immediately after flushToDisk");
    XCTAssertNotNil(cached[@"light.flush_test"]);
}

- (void)testDebounceCoalescesWrites {
    HAEntityStateCache *cache = [HAEntityStateCache sharedCache];

    // Write 1
    HAEntity *e1 = [[HAEntity alloc] initWithDictionary:@{
        @"entity_id": @"light.debounce1", @"state": @"on", @"attributes": @{}
    }];
    [cache entitiesDidUpdate:@{@"light.debounce1": e1}];

    // Write 2 immediately after (should coalesce, not trigger a second disk write)
    HAEntity *e2 = [[HAEntity alloc] initWithDictionary:@{
        @"entity_id": @"light.debounce2", @"state": @"off", @"attributes": @{}
    }];
    [cache entitiesDidUpdate:@{@"light.debounce1": e1, @"light.debounce2": e2}];

    // Before debounce fires, file should NOT exist yet (no flush called)
    NSDictionary *immediate = [cache loadCachedStates];
    XCTAssertNil(immediate, @"Cache should not be written before debounce interval");

    // Wait for debounce (5s + margin)
    XCTestExpectation *exp = [self expectationWithDescription:@"debounce fires"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSDictionary *afterDebounce = [cache loadCachedStates];
        XCTAssertNotNil(afterDebounce, @"Cache should exist after debounce");
        // Should contain the LATEST update (both entities)
        XCTAssertEqual(afterDebounce.count, 2, @"Should have both entities from coalesced write");
        [exp fulfill];
    });
    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testServerURLChangeClearsCache {
    // Write cache for server A
    [HACacheManager sharedManager].serverURL = @"http://server-a.local:8123";
    HAEntity *e = [[HAEntity alloc] initWithDictionary:@{
        @"entity_id": @"light.server_a", @"state": @"on", @"attributes": @{}
    }];
    HAEntityStateCache *cache = [HAEntityStateCache sharedCache];
    [cache entitiesDidUpdate:@{@"light.server_a": e}];
    [cache flushToDisk];
    XCTAssertTrue([cache hasCachedStates]);

    // Switch to server B — server A cache should not be visible
    [HACacheManager sharedManager].serverURL = @"http://server-b.local:8123";
    XCTAssertFalse([cache hasCachedStates],
                   @"Server B should have no cached states");
    NSDictionary *cached = [cache loadCachedStates];
    XCTAssertNil(cached, @"Server B should not see server A's entities");

    // Clean up server A cache too
    [HACacheManager sharedManager].serverURL = @"http://server-a.local:8123";
    [[HACacheManager sharedManager] clearAllCaches];
    [HACacheManager sharedManager].serverURL = @"http://server-b.local:8123";
}

@end

#pragma mark - HADashboardConfigCache Tests

@interface HADashboardConfigCacheTests : XCTestCase
@end

@implementation HADashboardConfigCacheTests

- (void)setUp {
    [super setUp];
    [HACacheManager sharedManager].serverURL = @"http://config-cache-test.local:8123";
}

- (void)tearDown {
    [[HACacheManager sharedManager] clearAllCaches];
    [super tearDown];
}

- (void)testWriteAndReadRoundTrip {
    NSDictionary *config = @{
        @"views": @[@{
            @"title": @"Home",
            @"cards": @[@{@"type": @"entities", @"entities": @[@"light.test"]}]
        }]
    };

    HADashboardConfigCache *cache = [HADashboardConfigCache sharedCache];
    [cache cacheConfig:config forDashboard:@"home"];

    // Wait for async write
    XCTestExpectation *exp = [self expectationWithDescription:@"write completes"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [exp fulfill]; });
    [self waitForExpectationsWithTimeout:3 handler:nil];

    NSDictionary *readBack = [cache loadCachedConfigForDashboard:@"home"];
    XCTAssertNotNil(readBack, @"Should read back cached config");
    XCTAssertEqualObjects(readBack[@"views"][0][@"title"], @"Home");
}

- (void)testHashComparisonSameConfigReturnsUnchanged {
    NSDictionary *config = @{@"views": @[@{@"title": @"Test"}]};
    HADashboardConfigCache *cache = [HADashboardConfigCache sharedCache];

    // First write — should report changed
    BOOL changed1 = [cache cacheConfig:config forDashboard:@"test-hash"];
    XCTAssertTrue(changed1, @"First cache should report changed=YES");

    // Wait for async write
    XCTestExpectation *exp = [self expectationWithDescription:@"write1"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [exp fulfill]; });
    [self waitForExpectationsWithTimeout:3 handler:nil];

    // Same config again — should report unchanged
    BOOL changed2 = [cache cacheConfig:config forDashboard:@"test-hash"];
    XCTAssertFalse(changed2, @"Same config should report changed=NO");
}

- (void)testHashComparisonDifferentConfigReturnsChanged {
    HADashboardConfigCache *cache = [HADashboardConfigCache sharedCache];

    NSDictionary *configV1 = @{@"views": @[@{@"title": @"Version 1"}]};
    [cache cacheConfig:configV1 forDashboard:@"test-diff"];

    XCTestExpectation *exp = [self expectationWithDescription:@"write"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [exp fulfill]; });
    [self waitForExpectationsWithTimeout:3 handler:nil];

    NSDictionary *configV2 = @{@"views": @[@{@"title": @"Version 2", @"cards": @[]}]};
    BOOL changed = [cache cacheConfig:configV2 forDashboard:@"test-diff"];
    XCTAssertTrue(changed, @"Different config should report changed=YES");
}

- (void)testPerDashboardFileNaming {
    HADashboardConfigCache *cache = [HADashboardConfigCache sharedCache];

    NSDictionary *configA = @{@"views": @[@{@"title": @"Dashboard A"}]};
    NSDictionary *configB = @{@"views": @[@{@"title": @"Dashboard B"}]};

    [cache cacheConfig:configA forDashboard:@"living-room"];
    [cache cacheConfig:configB forDashboard:@"security"];

    XCTestExpectation *exp = [self expectationWithDescription:@"writes"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [exp fulfill]; });
    [self waitForExpectationsWithTimeout:3 handler:nil];

    NSDictionary *readA = [cache loadCachedConfigForDashboard:@"living-room"];
    NSDictionary *readB = [cache loadCachedConfigForDashboard:@"security"];

    XCTAssertNotNil(readA);
    XCTAssertNotNil(readB);
    XCTAssertEqualObjects(readA[@"views"][0][@"title"], @"Dashboard A");
    XCTAssertEqualObjects(readB[@"views"][0][@"title"], @"Dashboard B");
}

- (void)testDefaultDashboardUsesSpecialFilename {
    HADashboardConfigCache *cache = [HADashboardConfigCache sharedCache];

    NSDictionary *config = @{@"views": @[@{@"title": @"Default"}]};
    [cache cacheConfig:config forDashboard:nil];

    XCTestExpectation *exp = [self expectationWithDescription:@"write"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [exp fulfill]; });
    [self waitForExpectationsWithTimeout:3 handler:nil];

    NSDictionary *readBack = [cache loadCachedConfigForDashboard:nil];
    XCTAssertNotNil(readBack);
    XCTAssertEqualObjects(readBack[@"views"][0][@"title"], @"Default");

    // Named dashboard should NOT see default's config
    NSDictionary *readOther = [cache loadCachedConfigForDashboard:@"other"];
    XCTAssertNil(readOther, @"Different dashboard path should not see default's cache");
}

- (void)testClearCacheForDashboard {
    HADashboardConfigCache *cache = [HADashboardConfigCache sharedCache];

    // Synchronize on the write's actual completion instead of guessing at a
    // fixed delay — cacheConfig:forDashboard: writes to disk asynchronously,
    // and a fixed wait is inherently flaky under load/contention.
    XCTestExpectation *exp = [self expectationWithDescription:@"write completes"];
    BOOL changed = [cache cacheConfig:@{@"views": @[]} forDashboard:@"deleteme" completion:^(BOOL success) {
        XCTAssertTrue(success, @"Write should succeed for a new/changed config");
        [exp fulfill];
    }];
    XCTAssertTrue(changed, @"First write for this dashboard should report changed=YES");
    [self waitForExpectationsWithTimeout:3 handler:nil];

    XCTAssertTrue([cache hasCachedConfigForDashboard:@"deleteme"]);
    [cache clearCacheForDashboard:@"deleteme"];
    XCTAssertFalse([cache hasCachedConfigForDashboard:@"deleteme"]);
    XCTAssertNil([cache loadCachedConfigForDashboard:@"deleteme"]);
}

@end
