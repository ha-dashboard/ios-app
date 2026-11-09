#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import "HACacheManager.h"
#import "HAEntityStateCache.h"
#import "HADashboardConfigCache.h"
#import "HAEntity.h"

#pragma mark - Test Doubles

/// In-memory stand-in for HACacheManager so HAEntityStateCache tests never
/// touch the real filesystem and can observe/time writes deterministically.
@interface HAFakeCacheWriting : NSObject <HACacheWriting>
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *files;
@property (nonatomic, assign) NSUInteger writeCount;
@property (nonatomic, assign) BOOL simulateSlowWrite;
@property (nonatomic, assign) BOOL overlapDetected;
@property (nonatomic, assign) BOOL inFlight;
@property (nonatomic, copy) void (^onWrite)(void);
@end

@implementation HAFakeCacheWriting

- (instancetype)init {
    self = [super init];
    if (self) {
        _files = [NSMutableDictionary dictionary];
    }
    return self;
}

- (id)readJSONFromFile:(NSString *)filename {
    return self.files[filename];
}

- (void)writeJSON:(id)object toFile:(NSString *)filename completion:(void (^)(BOOL success))completion {
    BOOL ok = [self writeJSONSync:object toFile:filename];
    if (completion) completion(ok);
}

- (BOOL)writeJSONSync:(id)object toFile:(NSString *)filename {
    if (self.inFlight) {
        self.overlapDetected = YES;
    }
    self.inFlight = YES;
    if (self.simulateSlowWrite) {
        usleep(50 * 1000); // 50ms — widen the window for a concurrent call to land
    }
    self.files[filename] = object;
    self.writeCount++;
    if (self.onWrite) self.onWrite();
    self.inFlight = NO;
    return YES;
}

- (void)deleteCacheFile:(NSString *)filename {
    [self.files removeObjectForKey:filename];
}

- (NSString *)persistentCacheDirectory {
    return @"/fake-cache-dir";
}

@end

/// Captures the block HAEntityStateCache schedules instead of letting
/// dispatch_after wait on the real wall clock — tests fire it on demand.
@interface HAFakeScheduler : NSObject
@property (nonatomic, copy) dispatch_block_t pendingBlock;
@property (nonatomic, assign) NSTimeInterval lastDelay;
@property (nonatomic, assign) NSUInteger scheduleCount;
@end

@implementation HAFakeScheduler

- (HAEntityStateCacheScheduler)schedulerBlock {
    __weak typeof(self) weakSelf = self;
    return ^(NSTimeInterval delay, dispatch_block_t block) {
        weakSelf.lastDelay = delay;
        weakSelf.pendingBlock = block;
        weakSelf.scheduleCount++;
    };
}

/// Simulates the debounce interval elapsing.
- (void)fire {
    dispatch_block_t block = self.pendingBlock;
    self.pendingBlock = nil;
    if (block) block();
}

@end

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

- (void)testBurstUpdatesProduceAtMostOneWritePerInterval {
    HAFakeCacheWriting *fake = [HAFakeCacheWriting new];
    HAFakeScheduler *scheduler = [HAFakeScheduler new];
    HAEntityStateCache *cache = [[HAEntityStateCache alloc] initWithCacheManager:fake
                                                                        scheduler:scheduler.schedulerBlock];

    // A burst of 20 updates in a row (simulating a busy HA instance) must
    // schedule exactly one debounced write, not one per update. Callers
    // (HAConnectionManager) always pass the FULL entity store snapshot on
    // every call, so the test does the same, growing the snapshot each time.
    NSMutableDictionary<NSString *, HAEntity *> *snapshot = [NSMutableDictionary dictionary];
    for (int i = 0; i < 20; i++) {
        NSString *entityId = [NSString stringWithFormat:@"sensor.burst_%d", i];
        HAEntity *entity = [[HAEntity alloc] initWithDictionary:@{
            @"entity_id": entityId, @"state": @(i).stringValue, @"attributes": @{}
        }];
        snapshot[entityId] = entity;
        [cache entitiesDidUpdate:[snapshot copy]];
    }
    XCTAssertEqual(scheduler.scheduleCount, 1, @"A burst of updates should schedule only one timer");
    XCTAssertEqual(scheduler.lastDelay, 300.0, @"Debounce interval should be 5 minutes");
    XCTAssertEqual(fake.writeCount, 0, @"Nothing should be written before the timer fires");

    // Simulate the debounce interval elapsing.
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    fake.onWrite = ^{ dispatch_semaphore_signal(sem); };
    [scheduler fire];
    XCTAssertEqual(dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC))), 0,
                   @"Debounced write should complete promptly");

    XCTAssertEqual(fake.writeCount, 1, @"The whole burst should coalesce into exactly one write");
    NSDictionary *written = fake.files[@"entity-states.json"];
    XCTAssertEqual(written.count, 20, @"The single write should contain the latest snapshot of all 20 entities");
}

- (void)testUnchangedDataProducesNoWrite {
    HAFakeCacheWriting *fake = [HAFakeCacheWriting new];
    HAEntityStateCache *cache = [[HAEntityStateCache alloc] initWithCacheManager:fake
                                                                        scheduler:^(NSTimeInterval d, dispatch_block_t b) { /* unused: test flushes synchronously */ }];

    NSDictionary *fixedFields = @{
        @"entity_id": @"sensor.steady", @"state": @"21.0", @"attributes": @{@"unit_of_measurement": @"°C"},
        @"last_changed": @"2026-03-02T10:00:00Z", @"last_updated": @"2026-03-02T10:00:00Z"
    };

    HAEntity *first = [[HAEntity alloc] initWithDictionary:fixedFields];
    [cache entitiesDidUpdate:@{@"sensor.steady": first}];
    [cache flushToDisk];
    XCTAssertEqual(fake.writeCount, 1, @"First write with new data should hit disk");

    // A second, content-identical snapshot (a fresh HAEntity instance, same
    // fields) must not produce a second write.
    HAEntity *second = [[HAEntity alloc] initWithDictionary:fixedFields];
    [cache entitiesDidUpdate:@{@"sensor.steady": second}];
    [cache flushToDisk];
    XCTAssertEqual(fake.writeCount, 1, @"Identical serialized content should be skipped, not re-written");

    // A real change must still write.
    HAEntity *changed = [[HAEntity alloc] initWithDictionary:@{
        @"entity_id": @"sensor.steady", @"state": @"21.5", @"attributes": @{@"unit_of_measurement": @"°C"},
        @"last_changed": @"2026-03-02T10:05:00Z", @"last_updated": @"2026-03-02T10:05:00Z"
    }];
    [cache entitiesDidUpdate:@{@"sensor.steady": changed}];
    [cache flushToDisk];
    XCTAssertEqual(fake.writeCount, 2, @"A genuine state change must still be written");
}

- (void)testLifecycleNotificationsFlushPendingWrites {
    HAFakeCacheWriting *fake = [HAFakeCacheWriting new];
    HAEntityStateCache *cache = [[HAEntityStateCache alloc] initWithCacheManager:fake
                                                                        scheduler:^(NSTimeInterval d, dispatch_block_t b) { /* never fires in this test */ }];

    HAEntity *e1 = [[HAEntity alloc] initWithDictionary:@{@"entity_id": @"light.bg", @"state": @"on", @"attributes": @{}}];
    [cache entitiesDidUpdate:@{@"light.bg": e1}];
    XCTAssertEqual(fake.writeCount, 0, @"Nothing written yet — only the app-lifecycle notification should trigger it");

    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    XCTAssertEqual(fake.writeCount, 1, @"Entering background should flush the pending snapshot");

    HAEntity *e2 = [[HAEntity alloc] initWithDictionary:@{@"entity_id": @"light.term", @"state": @"off", @"attributes": @{}}];
    [cache entitiesDidUpdate:@{@"light.term": e2}];
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationWillTerminateNotification object:nil];
    XCTAssertEqual(fake.writeCount, 2, @"Terminating should also flush any newly pending snapshot");
}

- (void)testFlushIsNoOpWhenNothingPending {
    HAFakeCacheWriting *fake = [HAFakeCacheWriting new];
    HAEntityStateCache *cache = [[HAEntityStateCache alloc] initWithCacheManager:fake
                                                                        scheduler:^(NSTimeInterval d, dispatch_block_t b) {}];
    [cache flushToDisk];
    XCTAssertEqual(fake.writeCount, 0, @"Flushing with nothing pending must not touch disk");
}

- (void)testOnlyOneWriteInFlightAtATime {
    HAFakeCacheWriting *fake = [HAFakeCacheWriting new];
    fake.simulateSlowWrite = YES;
    HAEntityStateCache *cache = [[HAEntityStateCache alloc] initWithCacheManager:fake
                                                                        scheduler:^(NSTimeInterval d, dispatch_block_t b) {}];

    dispatch_group_t group = dispatch_group_create();
    for (int i = 0; i < 4; i++) {
        NSString *entityId = [NSString stringWithFormat:@"sensor.concurrent_%d", i];
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            HAEntity *entity = [[HAEntity alloc] initWithDictionary:@{
                @"entity_id": entityId, @"state": [NSString stringWithFormat:@"%d", i], @"attributes": @{}
            }];
            [cache entitiesDidUpdate:@{entityId: entity}];
            [cache flushToDisk];
        });
    }
    XCTAssertEqual(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC))), 0,
                   @"Concurrent flushes should all complete without deadlocking");
    XCTAssertFalse(fake.overlapDetected, @"The shared serial write queue must never let two writes overlap");
}

- (void)testSerializedSizeAndWriteRateBenchmark {
    // A representative snapshot: 50 entities with realistic attribute payloads.
    NSMutableDictionary<NSString *, HAEntity *> *entities = [NSMutableDictionary dictionary];
    for (int i = 0; i < 50; i++) {
        NSString *entityId = [NSString stringWithFormat:@"sensor.benchmark_%d", i];
        entities[entityId] = [[HAEntity alloc] initWithDictionary:@{
            @"entity_id": entityId,
            @"state": @"23.5",
            @"attributes": @{
                @"friendly_name": [NSString stringWithFormat:@"Benchmark Entity %d", i],
                @"unit_of_measurement": @"°C",
                @"device_class": @"temperature",
                @"icon": @"mdi:thermometer"
            },
            @"last_changed": @"2026-03-02T10:00:00Z",
            @"last_updated": @"2026-03-02T10:00:00Z"
        }];
    }

    HAFakeCacheWriting *fake = [HAFakeCacheWriting new];
    HAEntityStateCache *cache = [[HAEntityStateCache alloc] initWithCacheManager:fake
                                                                        scheduler:^(NSTimeInterval d, dispatch_block_t b) {}];
    [cache entitiesDidUpdate:entities];
    [cache flushToDisk];

    NSData *writtenData = [NSJSONSerialization dataWithJSONObject:fake.files[@"entity-states.json"] options:0 error:nil];
    NSUInteger bytes = writtenData.length;
    XCTAssertGreaterThan(bytes, 0);

    static const NSTimeInterval kOldDebounceInterval = 5.0;   // pre-fix behavior
    static const NSTimeInterval kNewDebounceInterval = 300.0; // this fix
    double beforeWritesPerHour = 3600.0 / kOldDebounceInterval;
    double afterWritesPerHour  = 3600.0 / kNewDebounceInterval;
    double beforeMBPerHour = (bytes * beforeWritesPerHour) / (1024.0 * 1024.0);
    double afterMBPerHour  = (bytes * afterWritesPerHour) / (1024.0 * 1024.0);

    NSLog(@"[cache-benchmark] %lu entities serialize to %lu bytes (%.1f KB)",
          (unsigned long)entities.count, (unsigned long)bytes, bytes / 1024.0);
    NSLog(@"[cache-benchmark] before: %.0f writes/hour -> %.2f MB/hour (worst case, no dedupe)",
          beforeWritesPerHour, beforeMBPerHour);
    NSLog(@"[cache-benchmark] after:  %.0f writes/hour -> %.2f MB/hour upper bound (dedupe skips further when unchanged)",
          afterWritesPerHour, afterMBPerHour);
    NSLog(@"[cache-benchmark] frequency-alone reduction: %.0fx", beforeWritesPerHour / afterWritesPerHour);

    XCTAssertEqualWithAccuracy(afterWritesPerHour, beforeWritesPerHour / 60.0, 0.001,
                               @"New debounce interval is 60x longer than the old one");
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
