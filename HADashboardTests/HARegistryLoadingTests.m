#import <XCTest/XCTest.h>
#import "HAConnectionManager.h"

// -----------------------------------------------------------------------
// Floor names for {type: floor} card names need both the floor registry and
// the area registry (which carries each area's floor_id). The floor registry
// is requested last, so dashboards used to rebuild on the registries
// notification before floor names existed and never rebuilt again.
// -----------------------------------------------------------------------

@interface HAConnectionManager (RegistryTestAccess)
@property (nonatomic, assign) NSInteger areaRegistryMessageId;
@property (nonatomic, assign) NSInteger entityRegistryMessageId;
@property (nonatomic, assign) NSInteger deviceRegistryMessageId;
@property (nonatomic, assign) NSInteger floorRegistryMessageId;
@property (nonatomic, assign) BOOL areasLoaded;
@property (nonatomic, assign) BOOL entitiesRegistryLoaded;
@property (nonatomic, assign) BOOL devicesLoaded;
@property (nonatomic, assign) BOOL floorsLoaded;
- (void)webSocketClient:(id)client didReceiveMessage:(NSDictionary *)message;
@end

@interface HARegistryLoadingTests : XCTestCase
@property (nonatomic, strong) HAConnectionManager *conn;
@property (nonatomic, assign) NSUInteger notificationCount;
@property (nonatomic, copy) NSDictionary *floorNamesAtNotification;
@property (nonatomic, strong) id observer;
@end

@implementation HARegistryLoadingTests

- (void)setUp {
    [super setUp];
    self.conn = [HAConnectionManager sharedManager];
    [self.conn disconnect]; // clears registry state left by other tests
    self.conn.areasLoaded = NO;
    self.conn.devicesLoaded = NO;
    self.conn.entitiesRegistryLoaded = NO;
    self.conn.floorsLoaded = NO;
    self.conn.areaRegistryMessageId = 9101;
    self.conn.deviceRegistryMessageId = 9102;
    self.conn.entityRegistryMessageId = 9103;
    self.conn.floorRegistryMessageId = 9104;

    __weak typeof(self) weakSelf = self;
    self.observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:HAConnectionManagerDidReceiveRegistriesNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        weakSelf.notificationCount++;
        weakSelf.floorNamesAtNotification = weakSelf.conn.floorNamesByAreaId;
    }];
}

- (void)tearDown {
    [[NSNotificationCenter defaultCenter] removeObserver:self.observer];
    [super tearDown];
}

- (void)deliver:(NSInteger)msgId result:(id)result success:(BOOL)success {
    NSMutableDictionary *message = [@{@"type": @"result", @"id": @(msgId), @"success": @(success)} mutableCopy];
    if (result) message[@"result"] = result;
    [self.conn webSocketClient:nil didReceiveMessage:message];
}

- (void)deliverAreasDevicesEntities {
    [self deliver:9101 result:@[@{@"area_id": @"downstairs", @"name": @"Downstairs", @"floor_id": @"ground"}] success:YES];
    [self deliver:9102 result:@[] success:YES];
    [self deliver:9103 result:@[@{@"entity_id": @"sensor.temp", @"area_id": @"downstairs"}] success:YES];
}

- (void)testFloorsArrivingLast_RegistriesNotificationIncludesFloorNames {
    [self deliverAreasDevicesEntities];
    XCTAssertEqual(self.notificationCount, 0u, @"Should wait for the floor registry before announcing registries");

    [self deliver:9104 result:@[@{@"floor_id": @"ground", @"name": @"Ground Floor"}] success:YES];
    XCTAssertEqual(self.notificationCount, 1u);
    XCTAssertEqualObjects(self.floorNamesAtNotification[@"downstairs"], @"Ground Floor");
}

- (void)testFloorsArrivingFirst_StillMappedAfterAreas {
    [self deliver:9104 result:@[@{@"floor_id": @"ground", @"name": @"Ground Floor"}] success:YES];
    [self deliverAreasDevicesEntities];
    XCTAssertEqual(self.notificationCount, 1u);
    XCTAssertEqualObjects(self.floorNamesAtNotification[@"downstairs"], @"Ground Floor");
}

- (void)testFloorRegistryUnsupported_RegistriesStillComplete {
    [self deliverAreasDevicesEntities];
    [self deliver:9104 result:nil success:NO];
    XCTAssertEqual(self.notificationCount, 1u, @"Older HA without floors must not block registry loading");
    XCTAssertEqual(self.conn.floorNamesByAreaId.count, 0u);
}

@end
