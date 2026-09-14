#import <XCTest/XCTest.h>
#import "HABLEIdentityEvidence.h"
#import "HABLEIdentityResolver.h"
#import "HAConnectionManager.h"
#import "HAAPIClient.h"

@interface HABLEIdentityResolver (GenericTests)
- (void)loadRegistry:(NSArray *)devices entries:(NSArray *)entries excludingSource:(NSString *)source;
- (void)observeAdvertisements:(NSArray *)advertisements;
- (void)loadCatalog:(id)value;
- (void)refreshNativeAdvertisements;
- (void)rebuildKnownDevices;
- (void)loadLocalBindings;
- (void)refreshNativeScannerDiagnostics;
- (HAAPIClient *)nativeDiagnosticsAPIClient;
- (void)observePeer:(id)value source:(NSString *)source;
- (void)observeInventory:(id)value source:(NSString *)source;
- (NSArray *)localInventoryAtTime:(NSTimeInterval)now;
- (HAConnectionManager *)connection;
- (BOOL)sourceIsCurrent;
@end
@interface HABLEFakeIdentityConnection : NSObject
@property (nonatomic, getter=isConnected) BOOL connected;
@property (nonatomic) BOOL delayUser;
@property (nonatomic, copy) void (^pendingUser)(id,NSError *);
@property (nonatomic, strong) NSMutableArray *commands;
@property (nonatomic, strong) NSMutableArray *subscriptions;
@property (nonatomic, strong) NSMutableArray *unsubscriptions;
@property (nonatomic, copy) void (^advertisementHandler)(NSDictionary *);
@property (nonatomic, copy) void (^registryHandler)(NSDictionary *);
@end
@implementation HABLEFakeIdentityConnection
- (instancetype)init { if((self=[super init])){_connected=YES;_commands=NSMutableArray.array;_subscriptions=NSMutableArray.array;_unsubscriptions=NSMutableArray.array;}return self; }
- (void)sendCommand:(NSDictionary *)command completion:(void (^)(id,NSError *))completion {
    [self.commands addObject:command];NSString *type=command[@"type"];
    if([type isEqual:@"auth/current_user"]){if(self.delayUser)self.pendingUser=completion;else completion(@{@"id":@"test-user"},nil);}
    else if([type isEqual:@"config_entries/get"])completion(@[@{@"entry_id":@"sensor-entry",@"domain":@"arbitrary_integration"}],nil);
    else if([type isEqual:@"config/device_registry/list"])completion(@[@{@"id":@"sensor",@"name":@"Room",@"connections":@[@[@"bluetooth",@"00:11:22:33:44:55"]],@"config_entries":@[@"sensor-entry"]}],nil);
    else if([type isEqual:@"manifest/list"])completion(@[@{@"domain":@"arbitrary_integration",@"bluetooth":@[@{@"local_name":@"Sample*",@"service_uuid":@"1234",@"connectable":@NO}]}],nil);
    else completion(@{@"value":NSNull.null},nil);
}
- (NSInteger)subscribeWithCommand:(NSDictionary *)command handler:(void (^)(NSDictionary *))handler { [self.subscriptions addObject:command[@"type"]];if([command[@"type"] isEqual:@"bluetooth/subscribe_advertisements"])self.advertisementHandler=handler;return self.subscriptions.count; }
- (NSInteger)subscribeToEventType:(NSString *)type handler:(void (^)(NSDictionary *))handler { self.registryHandler=handler;[self.subscriptions addObject:type];return self.subscriptions.count; }
- (void)unsubscribeFromEventWithId:(NSInteger)identifier { [self.unsubscriptions addObject:@(identifier)]; }
@end
@interface HABLEFakeDiagnosticsClient : NSObject
@property (nonatomic, strong) NSMutableArray *paths;
@property (nonatomic, copy) HAAPIResponseBlock pending;
@end
@implementation HABLEFakeDiagnosticsClient
- (instancetype)init {if((self=[super init]))_paths=NSMutableArray.array;return self;}
- (void)getJSONAtPath:(NSString *)path completion:(HAAPIResponseBlock)completion {[self.paths addObject:path];self.pending=completion;}
@end
@interface HABLETransportTestResolver : HABLEIdentityResolver
@property (nonatomic, strong) HABLEFakeIdentityConnection *fakeConnection;
@property (nonatomic) BOOL currentScope;
@property (nonatomic, strong) HABLEFakeDiagnosticsClient *fakeDiagnostics;
@end
@implementation HABLETransportTestResolver
- (HAConnectionManager *)connection { return (HAConnectionManager *)self.fakeConnection; }
- (BOOL)sourceIsCurrent { return self.currentScope; }
- (HAAPIClient *)nativeDiagnosticsAPIClient {return (HAAPIClient *)self.fakeDiagnostics;}
@end
@interface HABLEInventoryCountingResolver : HABLEIdentityResolver
@property NSUInteger rebuilds;
@end
@implementation HABLEInventoryCountingResolver
- (void)rebuildKnownDevices {self.rebuilds++;[super rebuildKnownDevices];}
@end
@interface HABLEIdentityEvidenceTests : XCTestCase
@end
@implementation HABLEIdentityEvidenceTests
- (void)testObservationInventoryAdmitsNewDevicesAfterCapacity {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    HABLEIdentityResolver *resolver=[HABLEIdentityResolver new];
    HABLEIdentityEvidence *evidence=[HABLEIdentityEvidence new];
    NSDictionary *payload=@{@"manufacturer_data":@"AQIDBA=="};
    for(NSUInteger i=0;i<256;i++) {
        NSString *identifier=[NSString stringWithFormat:@"device-%lu",(unsigned long)i];
        NSMutableDictionary *o=[payload mutableCopy];o[@"identifier"]=identifier;o[@"last_seen"]=@(now-300+i);
        [resolver recordObservation:o identifier:identifier];[evidence recordLocal:o identifier:identifier atTime:now-300+i];
    }
    NSDictionary *newDevice=@{@"identifier":@"new",@"last_seen":@(now),@"manufacturer_data":@"AQIDBA=="};
    [resolver recordObservation:newDevice identifier:@"new"];[evidence recordLocal:newDevice identifier:@"new" atTime:now];
    NSDictionary *inventory=[resolver valueForKey:@"localObservations"];
    XCTAssertEqual(inventory.count,256u);XCTAssertNotNil(inventory[@"new"]);XCTAssertNil(inventory[@"device-0"]);
    XCTAssertEqual([evidence recentLocalEventsForIdentifier:@"new" now:now].count,1u);
    XCTAssertEqual([evidence recentLocalEventsForIdentifier:@"device-0" now:now].count,0u);
    // Replayed older snapshots cannot push newer devices out of the window.
    [evidence recordLocal:payload identifier:@"replay" atTime:now-400];
    XCTAssertEqual([evidence recentLocalEventsForIdentifier:@"replay" now:now].count,0u);
    XCTAssertEqual([evidence recentLocalEventsForIdentifier:@"new" now:now].count,1u);
}
- (void)testNativeInventoryRotatesWithoutEvictingNewerEvidenceForReplay {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    HABLEIdentityResolver *resolver=[HABLEIdentityResolver new];
    [resolver loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    for(NSUInteger i=0;i<256;i++) {
        NSString *address=[NSString stringWithFormat:@"10:11:22:33:44:%02lX",(unsigned long)i];
        [resolver observeAdvertisements:@[@{@"address":address,@"source":@"20:00:00:00:00:01",@"time":@(now-300+i),@"name":@"Unit",@"raw":@"05ff01020304"}]];
    }
    NSDictionary *newDevice=@{@"address":@"10:11:22:33:55:00",@"source":@"20:00:00:00:00:01",@"time":@(now),@"name":@"New unit",@"raw":@"05ff01020304"};
    [resolver observeAdvertisements:@[newDevice]];
    NSDictionary *inventory=[resolver valueForKey:@"remoteInfo"];
    XCTAssertEqual(inventory.count,256u);XCTAssertNotNil(inventory[newDevice[@"address"]]);XCTAssertNil(inventory[@"10:11:22:33:44:00"]);
    NSMutableDictionary *replay=[newDevice mutableCopy];replay[@"address"]=@"10:11:22:33:66:00";replay[@"time"]=@(now-400);
    [resolver observeAdvertisements:@[replay]];
    XCTAssertNil(inventory[replay[@"address"]]);XCTAssertNotNil(inventory[newDevice[@"address"]]);
}
- (void)testPayloadAgreementRejectsDifferentLengthContradictions {
    NSDictionary *a=@{@"manufacturer_data":@"AQIDBA==",@"service_data":@{@"1234":@"BQYHCA=="}};
    NSDictionary *b=@{@"manufacturer_data":@"AQIDBA==",@"service_data":@{@"1234":@"BQYHCQk="}};
    NSArray *left=[HABLEIdentityEvidence tokensForObservation:a],*right=[HABLEIdentityEvidence tokensForObservation:b];
    XCTAssertFalse([HABLEIdentityEvidence tokens:left agreeWith:right]);
    XCTAssertFalse([HABLEIdentityEvidence tokens:right agreeWith:left]);
    XCTAssertTrue([HABLEIdentityEvidence tokens:left agreeWith:left]);
    // A genuinely absent scan-response channel is different from a conflict.
    NSArray *partial=[HABLEIdentityEvidence tokensForObservation:@{@"manufacturer_data":@"AQIDBA=="}];
    XCTAssertTrue([HABLEIdentityEvidence tokens:left agreeWith:partial]);
    XCTAssertTrue([HABLEIdentityEvidence tokens:partial agreeWith:left]);
}
- (void)testExtraContradictoryValueCannotHideBehindMatchingValue {
    NSArray *a=[HABLEIdentityEvidence tokensForObservation:@{@"manufacturer_data":@"AQIDBA=="}];
    NSArray *b=[a arrayByAddingObjectsFromArray:[HABLEIdentityEvidence tokensForObservation:@{@"manufacturer_data":@"AQIDBAU="}]];
    XCTAssertFalse([HABLEIdentityEvidence tokens:a agreeWith:b]);
    XCTAssertFalse([HABLEIdentityEvidence tokens:b agreeWith:a]);
}
- (NSDictionary *)recordPassiveUnit:(NSString *)name identifier:(NSString *)identifier address:(NSString *)address resolver:(HABLEIdentityResolver *)resolver atTime:(NSTimeInterval)time {
    NSDictionary *observation=@{@"identifier":identifier,@"name":name,@"last_seen":@(time),@"service_uuids":@[@"1234"],@"manufacturer_data":@"AQIDBAUGBwg="};
    [resolver recordObservation:observation identifier:identifier];
    [resolver observeAdvertisements:@[@{@"address":address,@"source":@"20:00:00:00:00:01",@"name":name,@"time":@(time),@"service_uuids":@[@"1234"],@"raw":@"09ff0102030405060708"}]];
    return observation;
}
- (void)testSustainedPassiveSignatureIsProvisionalAndDistinctNamesStaySeparate {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;HABLEIdentityResolver *resolver=[HABLEIdentityResolver new];
    [resolver loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];NSDictionary *a=nil,*b=nil;
    for(NSUInteger i=0;i<4;i++) {
        a=[self recordPassiveUnit:@"Unit1234" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:resolver atTime:now-30+i*10];
        b=[self recordPassiveUnit:@"Unit5678" identifier:@"b" address:@"AA:BB:CC:DD:EE:02" resolver:resolver atTime:now-30+i*10];
        if(i<3)XCTAssertNil([resolver automaticMatchForObservation:a]);
    }
    NSDictionary *match=[resolver automaticMatchForObservation:a];
    XCTAssertEqualObjects(match[@"method"],@"passive_signature");XCTAssertEqualObjects(match[@"address"],@"AA:BB:CC:DD:EE:01");
    XCTAssertEqualObjects([resolver automaticMatchForObservation:b][@"address"],@"AA:BB:CC:DD:EE:02");
    [resolver rememberAutomaticMatch:match];XCTAssertEqual([[resolver valueForKey:@"localBindings"] count],0u);
    // A newly observed twin vetoes the provisional match immediately.
    [self recordPassiveUnit:@"Unit1234" identifier:@"twin" address:@"AA:BB:CC:DD:EE:03" resolver:resolver atTime:now];
    XCTAssertNil([resolver automaticMatchForObservation:a]);
}
- (void)testPassiveSignatureDoesNotPromoteReplaysGenericNamesOrStaleEvidence {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;HABLEIdentityResolver *resolver=[HABLEIdentityResolver new];
    [resolver loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];NSDictionary *o=nil;
    for(NSUInteger i=0;i<4;i++)o=[self recordPassiveUnit:@"Unit1234" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:resolver atTime:now-30];
    XCTAssertNil([resolver automaticMatchForObservation:o]);
    for(NSUInteger i=0;i<4;i++)o=[self recordPassiveUnit:@"Thermometer" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:resolver atTime:now-30+i*10];
    XCTAssertNil([resolver automaticMatchForObservation:o]);
    for(NSUInteger i=0;i<4;i++)o=[self recordPassiveUnit:@"Unit1234" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:resolver atTime:now-100+i*10];
    XCTAssertNil([resolver automaticMatchForObservation:o]);
}
- (void)testPassiveSignatureResetsOnPayloadChangeOrObservationGap {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;HABLEIdentityResolver *resolver=[HABLEIdentityResolver new];
    [resolver loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];NSDictionary *o=nil;
    for(NSUInteger i=0;i<4;i++)o=[self recordPassiveUnit:@"Unit1234" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:resolver atTime:now-30+i*10];
    XCTAssertNotNil([resolver automaticMatchForObservation:o]);
    NSMutableDictionary *changed=[o mutableCopy];changed[@"manufacturer_data"]=@"AQIDBAUGBwk=";[resolver recordObservation:changed identifier:@"a"];
    XCTAssertNil([resolver automaticMatchForObservation:changed]);
    [self recordPassiveUnit:@"Unit1234" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:resolver atTime:now-60];
    o=[self recordPassiveUnit:@"Unit1234" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:resolver atTime:now];
    XCTAssertNil([resolver automaticMatchForObservation:o]);
}
- (void)testQualifiedPassiveSignatureSurvivesBriefReceptionGapButStillRequiresFreshReference {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;HABLEIdentityResolver *resolver=[HABLEIdentityResolver new];
    [resolver loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];NSDictionary *o=nil;
    for(NSUInteger i=0;i<4;i++)o=[self recordPassiveUnit:@"Unit1234" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:resolver atTime:now-90+i*10];
    o=[self recordPassiveUnit:@"Unit1234" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:resolver atTime:now];
    XCTAssertEqualObjects([resolver automaticMatchForObservation:o][@"address"],@"AA:BB:CC:DD:EE:01");
    NSMutableDictionary *remote=[resolver valueForKey:@"remoteInfo"][@"AA:BB:CC:DD:EE:01"];
    remote[@"time"]=@(now-121);XCTAssertNil([resolver automaticMatchForObservation:o],@"Prior qualification cannot replace a fresh independent reference");
    remote[@"time"]=@(now);
    [self recordPassiveUnit:@"Unit1234" identifier:@"twin" address:@"AA:BB:CC:DD:EE:02" resolver:resolver atTime:now];
    XCTAssertNil([resolver automaticMatchForObservation:o],@"A same-signature twin still vetoes the provisional match");
    HABLEIdentityResolver *expired=[HABLEIdentityResolver new];[expired loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    for(NSUInteger i=0;i<4;i++)[self recordPassiveUnit:@"Unit1234" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:expired atTime:now-180+i*10];
    o=[self recordPassiveUnit:@"Unit1234" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:expired atTime:now];
    XCTAssertNil([expired automaticMatchForObservation:o],@"Long reception gaps require learning again");
}
- (void)testPassiveSignatureAcceptsFreshReferenceWithoutCountingSnapshotReplays {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;HABLEIdentityResolver *resolver=[HABLEIdentityResolver new];
    [resolver loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    NSDictionary *o=[self recordPassiveUnit:@"Unit1234" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:resolver atTime:now-30];
    for(NSUInteger i=1;i<4;i++){NSMutableDictionary *next=[o mutableCopy];next[@"last_seen"]=@(now-30+i*10);[resolver recordObservation:next identifier:@"a"];o=next;}
    XCTAssertEqualObjects([resolver automaticMatchForObservation:o][@"method"],@"passive_signature");
    NSMutableDictionary *remote=[[resolver valueForKey:@"remoteInfo"][@"AA:BB:CC:DD:EE:01"] mutableCopy];remote[@"time"]=@(now-121);
    [[resolver valueForKey:@"remoteInfo"] setObject:remote forKey:@"AA:BB:CC:DD:EE:01"];
    XCTAssertNil([resolver automaticMatchForObservation:o]);
}
- (void)testCompletePayloadExtensionRequiresEveryReferenceByteAndChannel {
    NSArray *reference=[HABLEIdentityEvidence tokensForObservation:@{@"manufacturer_data":@"AQIDBAUGBwg="}];
    NSArray *extended=[HABLEIdentityEvidence tokensForObservation:@{@"manufacturer_data":@"AQIDBAUGBwgJCg=="}];
    NSArray *conflict=[HABLEIdentityEvidence tokensForObservation:@{@"manufacturer_data":@"AQIDBAUGBwkJCg=="}];
    XCTAssertTrue([HABLEIdentityEvidence tokens:extended extendCompleteTokens:reference]);
    XCTAssertFalse([HABLEIdentityEvidence tokens:reference extendCompleteTokens:extended]);
    XCTAssertFalse([HABLEIdentityEvidence tokens:conflict extendCompleteTokens:reference]);
    NSArray *extra=[extended arrayByAddingObjectsFromArray:[HABLEIdentityEvidence tokensForObservation:@{@"service_data":@{@"1234":@"AQIDBA=="}}]];
    XCTAssertFalse([HABLEIdentityEvidence tokens:extra extendCompleteTokens:reference]);
}
- (void)testProvisionalMatchingAllowsCompleteNativePayloadExtension {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;HABLEIdentityResolver *resolver=[HABLEIdentityResolver new];
    [resolver loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    [self recordPassiveUnit:@"Unit1234" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:resolver atTime:now-40];
    NSDictionary *o=nil;
    for(NSUInteger i=0;i<4;i++) {
        o=@{@"identifier":@"a",@"name":@"Unit1234",@"last_seen":@(now-30+i*10),@"service_uuids":@[@"1234"],@"manufacturer_data":@"AQIDBAUGBwgJCg=="};
        [resolver recordObservation:o identifier:@"a"];
    }
    XCTAssertEqualObjects([resolver automaticMatchForObservation:o][@"method"],@"passive_signature");
    NSMutableDictionary *twin=[o mutableCopy];twin[@"identifier"]=@"b";twin[@"manufacturer_data"]=@"AQIDBAUGBwgLCg==";[resolver recordObservation:twin identifier:@"b"];
    XCTAssertNil([resolver automaticMatchForObservation:o]);
}
- (void)testNativeSnapshotRefreshIsBoundedAndIgnoresRetiredCallbacks {
    HABLETransportTestResolver *resolver=[HABLETransportTestResolver new];resolver.fakeConnection=[HABLEFakeIdentityConnection new];resolver.currentScope=YES;
    [resolver loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    [resolver refreshNativeAdvertisements];void (^retired)(NSDictionary *)=resolver.fakeConnection.advertisementHandler;
    XCTAssertEqual(resolver.fakeConnection.subscriptions.count,1u);
    [resolver refreshNativeAdvertisements];XCTAssertEqual(resolver.fakeConnection.subscriptions.count,1u);
    [resolver setValue:@0 forKey:@"nextNativeSnapshot"];[resolver refreshNativeAdvertisements];
    XCTAssertEqual(resolver.fakeConnection.subscriptions.count,2u);XCTAssertEqualObjects(resolver.fakeConnection.unsubscriptions,(@[@1]));
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSDictionary *ad=@{@"address":@"AA:BB:CC:DD:EE:01",@"source":@"20:00:00:00:00:01",@"time":@(now-10),@"name":@"Unit1234",@"raw":@"09ff0102030405060708"};
    retired(@{@"add":@[ad]});XCTAssertEqual([[resolver valueForKey:@"remoteInfo"] count],0u);
    resolver.fakeConnection.advertisementHandler(@{@"add":@[ad]});
    NSDictionary *stored=[resolver valueForKey:@"remoteInfo"][@"AA:BB:CC:DD:EE:01"];
    XCTAssertEqualObjects(stored[@"time"],ad[@"time"]);XCTAssertEqualObjects(stored[@"passive_samples"],@1);
    resolver.fakeConnection.advertisementHandler(@{@"add":@[ad]});
    XCTAssertEqualObjects([resolver valueForKey:@"remoteInfo"][@"AA:BB:CC:DD:EE:01"][@"passive_samples"],@1);
    NSMutableDictionary *older=[ad mutableCopy];older[@"time"]=@(now-20);older[@"name"]=@"Wrong1234";
    resolver.fakeConnection.advertisementHandler(@{@"add":@[older]});
    XCTAssertEqualObjects([resolver valueForKey:@"remoteInfo"][@"AA:BB:CC:DD:EE:01"][@"name"],@"Unit1234");
    [resolver cancel];XCTAssertEqualObjects(resolver.fakeConnection.unsubscriptions,(@[@1,@2]));
}
- (NSMutableDictionary *)scannerDiagnosticsFixture {
    NSString *address=@"AA:BB:CC:DD:EE:01";
    NSMutableDictionary *scanner=[@{@"source":@"20:00:00:00:00:01",@"monotonic_time":@1000,
        @"discovered_device_timestamps":@{address:@999.5},
        @"raw_advertisement_data":@{address:@{@"__type":@"<class 'bytes'>",@"repr":@"b'\\t\\xff\\x01\\x02\\x03\\x04\\x05\\x06\\x07\\x08'"}},
        @"discovered_devices_and_advertisement_data":@[@{@"address":address,@"name":@"Unit1234",@"advertisement_data":@[@"Unit1234",@{},@{},@[@"1234"]]}]} mutableCopy];
    return scanner;
}
- (void)testScannerDiagnosticsPreserveNativeSourcePayloadAndObservationAge {
    NSDictionary *scanner=[self scannerDiagnosticsFixture];NSDictionary *envelope=@{@"data":@{@"manager":@{@"scanners":@[scanner]},@"unrelated":@"must not be retained"}};
    NSArray *rows=[HABLEIdentityEvidence nativeObservationsFromDiagnostics:envelope requestedAt:100000];XCTAssertEqual(rows.count,1u);
    XCTAssertEqualObjects(rows.firstObject[@"source"],@"20:00:00:00:00:01");XCTAssertEqualObjects(rows.firstObject[@"raw"],@"09ff0102030405060708");
    XCTAssertEqualWithAccuracy([rows.firstObject[@"time"] doubleValue],99999.5,0.001);XCTAssertNil(rows.firstObject[@"unrelated"]);
}
- (void)testScannerDiagnosticsRejectStaleFutureAndMalformedByteLiterals {
    NSMutableDictionary *scanner=[self scannerDiagnosticsFixture];NSString *address=@"AA:BB:CC:DD:EE:01";
    for(NSNumber *timestamp in @[@800,@1001]) {
        scanner[@"discovered_device_timestamps"]=@{address:timestamp};
        XCTAssertEqual([HABLEIdentityEvidence nativeObservationsFromDiagnostics:@{@"data":@{@"manager":@{@"scanners":@[scanner]}}} requestedAt:100000].count,0u);
    }
    scanner[@"discovered_device_timestamps"]=@{address:@999};
    for(NSString *literal in @[@"__import__('os')",@"b'\\xgg'",@"b'\\x1'",@"b'\\q'"]) {
        scanner[@"raw_advertisement_data"]=@{address:@{@"__type":@"<class 'bytes'>",@"repr":literal}};
        XCTAssertEqual([HABLEIdentityEvidence nativeObservationsFromDiagnostics:@{@"data":@{@"manager":@{@"scanners":@[scanner]}}} requestedAt:100000].count,0u);
    }
}
- (void)testSourceDiagnosticsImportIsBoundedAndRejectsProxyEcho {
    HABLETransportTestResolver *resolver=[HABLETransportTestResolver new];resolver.fakeConnection=[HABLEFakeIdentityConnection new];resolver.fakeDiagnostics=[HABLEFakeDiagnosticsClient new];resolver.currentScope=YES;
    [resolver loadRegistry:@[] entries:@[@{@"entry_id":@"bluetooth-entry",@"domain":@"bluetooth"}] excludingSource:@"02:00:00:00:00:01"];
    [resolver refreshNativeScannerDiagnostics];[resolver refreshNativeScannerDiagnostics];XCTAssertEqualObjects(resolver.fakeDiagnostics.paths,(@[@"diagnostics/config_entry/bluetooth-entry"]));
    NSDictionary *envelope=@{@"data":@{@"manager":@{@"scanners":@[[self scannerDiagnosticsFixture]]}}};
    resolver.fakeDiagnostics.pending(envelope,nil);XCTAssertEqual([[resolver valueForKey:@"remoteInfo"] count],1u);
    [resolver refreshNativeScannerDiagnostics];XCTAssertEqual(resolver.fakeDiagnostics.paths.count,1u);
    [[resolver valueForKey:@"remoteInfo"] removeAllObjects];[[resolver valueForKey:@"proxySources"] addObject:@"20:00:00:00:00:01"];
    [resolver setValue:@0 forKey:@"nextNativeDiagnostics"];[resolver refreshNativeScannerDiagnostics];resolver.fakeDiagnostics.pending(envelope,nil);
    XCTAssertEqual([[resolver valueForKey:@"remoteInfo"] count],0u);
    [resolver setValue:@0 forKey:@"nextNativeDiagnostics"];[resolver refreshNativeScannerDiagnostics];HAAPIResponseBlock old=resolver.fakeDiagnostics.pending;[resolver cancel];old(envelope,nil);
    XCTAssertEqual([[resolver valueForKey:@"remoteInfo"] count],0u);
}
- (void)testPacketUpdatesKeepFreshAnchorsWithoutRebuildingTheDeviceList {
    HABLEInventoryCountingResolver *r=[HABLEInventoryCountingResolver new];[r loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSMutableDictionary *ad=[@{@"address":@"AA:BB:CC:DD:EE:01",@"source":@"20:00:00:00:00:01",@"name":@"Unit1234",@"time":@(now-10),@"raw":@"09ff0102030405060708"} mutableCopy];
    [r observeAdvertisements:@[ad]];NSUInteger baseline=r.rebuilds;
    for(NSUInteger i=0;i<100;i++){ad[@"time"]=@(now-10+i*.1);ad[@"raw"]=[NSString stringWithFormat:@"09ff01020304050607%02lx",(unsigned long)i];[r observeAdvertisements:@[ad]];}
    XCTAssertEqual(r.rebuilds,baseline);
    NSDictionary *candidate=[r candidatesForObservation:@{@"identifier":@"unit",@"name":@"Unit1234",@"last_seen":@(now)}].firstObject;
    XCTAssertEqualObjects(candidate[@"native_anchor"][@"raw"],ad[@"raw"]);
    ad[@"name"]=@"Renamed1234";[r observeAdvertisements:@[ad]];XCTAssertEqual(r.rebuilds,baseline+1);XCTAssertEqualObjects(r.knownDevices.firstObject[@"name"],@"Renamed1234");
    ad[@"address"]=@"AA:BB:CC:DD:EE:02";[r observeAdvertisements:@[ad]];XCTAssertEqual(r.knownDevices.count,2u);
}
- (void)testPeerOnlyPassiveDevicesConvergeWithoutGattOrNativeScanner {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;NSMutableArray *resolvers=NSMutableArray.array,*observations=NSMutableArray.array;NSArray *sources=@[@"02:00:00:00:00:01",@"02:00:00:00:00:02"];
    for(NSUInteger i=0;i<2;i++) {
        HABLEIdentityResolver *r=[HABLEIdentityResolver new];[r loadRegistry:@[] entries:@[] excludingSource:sources[i]];[r setValue:[NSMutableSet setWithObject:sources[1-i]] forKey:@"proxySources"];
        NSMutableDictionary *o=[@{@"identifier":sources[i],@"local_address":sources[i],@"name":@"Display Model43",@"manufacturer_data":@"AQIDBAUGBwg=",@"service_uuids":@[],@"connectable":@NO} mutableCopy];
        for(NSUInteger j=0;j<4;j++){o[@"last_seen"]=@(now-30+j*10);[r recordObservation:o identifier:sources[i]];}
        [observations addObject:o];[resolvers addObject:r];XCTAssertNil([r automaticMatchForObservation:o]);
    }
    for(NSUInteger i=0;i<2;i++)[resolvers[i] observeInventory:@{@"schema":@1,@"source":sources[1-i],@"time":@(now),@"observations":[resolvers[1-i] localInventoryAtTime:now]} source:sources[1-i]];
    NSDictionary *a=[resolvers[0] automaticMatchForObservation:observations[0]],*b=[resolvers[1] automaticMatchForObservation:observations[1]];
    XCTAssertEqualObjects(a[@"method"],@"peer_passive_signature");XCTAssertEqualObjects(a[@"address"],b[@"address"]);
    [resolvers[0] rememberAutomaticMatch:a];XCTAssertEqual([[resolvers[0] valueForKey:@"localBindings"] count],0u);
    // A disappearing observer is not contradictory identity evidence.
    [[resolvers[0] valueForKey:@"peerInventories"] removeAllObjects];
    NSDictionary *continued=[resolvers[0] automaticMatchForObservation:observations[0]];
    XCTAssertEqualObjects(continued[@"address"],a[@"address"]);XCTAssertTrue([continued[@"evidence"] containsString:@"peer is unavailable"]);

    NSMutableDictionary *twin=[observations[0] mutableCopy];twin[@"identifier"]=@"twin";[resolvers[0] recordObservation:twin identifier:@"twin"];
    XCTAssertNil([resolvers[0] automaticMatchForObservation:observations[0]]);
    [resolvers[0] removeIdentifier:@"twin"];
    XCTAssertNil([resolvers[0] automaticMatchForObservation:observations[0]],@"A detected twin invalidates continuity even after it disappears");

    NSMutableDictionary *changed=[observations[0] mutableCopy];changed[@"manufacturer_data"]=@"AQIDBAUGBwk=";[resolvers[0] recordObservation:changed identifier:sources[0]];
    XCTAssertNil([resolvers[0] automaticMatchForObservation:changed]);
}
- (void)testPeerPassiveRejectsStaleTwinsAndConflictingIdentifiers {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;NSString *a=@"02:00:00:00:00:01",*b=@"02:00:00:00:00:02",*c=@"02:00:00:00:00:03";
    HABLEIdentityResolver *r=[HABLEIdentityResolver new];[r loadRegistry:@[] entries:@[] excludingSource:a];[r setValue:[NSMutableSet setWithArray:@[b,c]] forKey:@"proxySources"];
    NSMutableDictionary *o=[@{@"identifier":@"local",@"local_address":@"02:11:22:33:44:55",@"name":@"Display Model43",@"manufacturer_data":@"AQIDBAUGBwg=",@"service_uuids":@[]} mutableCopy];
    for(NSUInteger i=0;i<4;i++){o[@"last_seen"]=@(now-30+i*10);[r recordObservation:o identifier:@"local"];}
    NSMutableDictionary *row=[[[r localInventoryAtTime:now] firstObject] mutableCopy];row[@"local_address"]=@"02:22:33:44:55:66";row[@"last_seen"]=@(now-121);
    [r observeInventory:@{@"schema":@1,@"source":b,@"time":@(now),@"observations":@[row]} source:b];XCTAssertNil([r automaticMatchForObservation:o]);
    row[@"last_seen"]=@(now);[r observeInventory:@{@"schema":@1,@"source":b,@"time":@(now),@"observations":@[row]} source:b];XCTAssertNotNil([r automaticMatchForObservation:o]);
    [[r valueForKey:@"peerInventories"] removeAllObjects];[r setValue:@"different-account-scope" forKey:@"scope"];
    XCTAssertNil([r automaticMatchForObservation:o],@"Continuity cannot cross an account scope");
    [r setValue:nil forKey:@"scope"];[r observeInventory:@{@"schema":@1,@"source":b,@"time":@(now),@"observations":@[row]} source:b];XCTAssertNotNil([r automaticMatchForObservation:o]);

    NSMutableDictionary *twin=[row mutableCopy];twin[@"local_address"]=@"02:33:44:55:66:77";
    [r observeInventory:@{@"schema":@1,@"source":b,@"time":@(now),@"observations":@[row,twin]} source:b];XCTAssertNil([r automaticMatchForObservation:o]);
    [[r valueForKey:@"peerInventories"] removeAllObjects];row[@"fingerprints"]=[self stableIdentifierFields];
    NSDictionary *reads=[HABLEIdentityEvidence fingerprintsForValue:[NSJSONSerialization dataWithJSONObject:@{@"device":@{@"mac":@"00:11:22:33:44:66"}} options:0 error:nil] path:@"s/1234/c/5678"];
    twin[@"fingerprints"]=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:[HABLEIdentityEvidence mergeFingerprintReads:reads previous:@{} session:@"one" atTime:1] session:@"two" atTime:2];
    [r observeInventory:@{@"schema":@1,@"source":b,@"time":@(now),@"observations":@[row]} source:b];[r observeInventory:@{@"schema":@1,@"source":c,@"time":@(now),@"observations":@[twin]} source:c];
    XCTAssertNil([r automaticMatchForObservation:o]);XCTAssertTrue([[r evidenceForIdentifier:@"local"] containsString:@"conflicting identifier"]);
}
- (void)testPeerContinuityReloadRequiresScopePeripheralAndFreshMatchingData {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;id saved=[defaults objectForKey:@"ha_ble_peer_continuity_v1"];
    @try {
        NSString *source=@"02:00:00:00:00:01",*peer=@"02:00:00:00:00:02";NSTimeInterval now=NSDate.date.timeIntervalSince1970;
        HABLETransportTestResolver *(^receiver)(NSString *)=^HABLETransportTestResolver *(NSString *scope){
            HABLETransportTestResolver *r=[HABLETransportTestResolver new];r.fakeConnection=[HABLEFakeIdentityConnection new];r.currentScope=YES;
            [r loadRegistry:@[] entries:@[] excludingSource:source];[r setValue:@"http://continuity.invalid" forKey:@"sourceServer"];[r setValue:scope forKey:@"scope"];return r;
        };
        HABLETransportTestResolver *first=receiver(@"account-a");[first setValue:[NSMutableSet setWithObject:peer] forKey:@"proxySources"];
        NSMutableDictionary *o=[@{@"identifier":@"apple-peripheral",@"local_address":@"02:11:22:33:44:55",@"name":@"Display Model43",@"manufacturer_data":@"AQIDBAUGBwg=",@"service_uuids":@[]} mutableCopy];
        for(NSUInteger i=0;i<4;i++){o[@"last_seen"]=@(now-30+i*10);[first recordObservation:o identifier:o[@"identifier"]];}
        NSMutableDictionary *row=[[[first localInventoryAtTime:now] firstObject] mutableCopy];row[@"local_address"]=@"02:22:33:44:55:66";
        [first observeInventory:@{@"schema":@1,@"source":peer,@"time":@(now),@"observations":@[row]} source:peer];NSDictionary *match=[first automaticMatchForObservation:o];XCTAssertNotNil(match);
        NSDictionary *stored=[defaults dictionaryForKey:@"ha_ble_peer_continuity_v1"];XCTAssertNotNil(stored[@"entries"][@"apple-peripheral"]);XCTAssertNil(stored[@"entries"][@"apple-peripheral"][@"address"]);
        HABLETransportTestResolver *restarted=receiver(@"account-a");[restarted loadLocalBindings];[restarted recordObservation:o identifier:o[@"identifier"]];
        XCTAssertEqualObjects([restarted automaticMatchForObservation:o][@"address"],match[@"address"]);XCTAssertEqual([[restarted valueForKey:@"localBindings"] count],0u);
        HABLETransportTestResolver *other=receiver(@"account-b");[other loadLocalBindings];[other recordObservation:o identifier:o[@"identifier"]];XCTAssertNil([other automaticMatchForObservation:o]);
        HABLETransportTestResolver *newPeripheral=receiver(@"account-a");[newPeripheral loadLocalBindings];NSMutableDictionary *changed=[o mutableCopy];changed[@"identifier"]=@"different-apple-peripheral";
        for(NSUInteger i=0;i<4;i++){changed[@"last_seen"]=@(now-30+i*10);[newPeripheral recordObservation:changed identifier:changed[@"identifier"]];}
        XCTAssertNil([newPeripheral automaticMatchForObservation:changed]);
        changed=[o mutableCopy];changed[@"manufacturer_data"]=@"AQIDBAUGBwk=";[restarted recordObservation:changed identifier:changed[@"identifier"]];XCTAssertNil([restarted automaticMatchForObservation:changed]);
        XCTAssertNil([defaults dictionaryForKey:@"ha_ble_peer_continuity_v1"][@"entries"][@"apple-peripheral"]);
    } @finally {if(saved)[defaults setObject:saved forKey:@"ha_ble_peer_continuity_v1"];else[defaults removeObjectForKey:@"ha_ble_peer_continuity_v1"];}
}
- (void)testPeerInputIsolationForRestartValidation {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;id previous=[defaults objectForKey:@"HABLEIdentityIgnorePeerObservations"];
    @try {
        [defaults setBool:YES forKey:@"HABLEIdentityIgnorePeerObservations"];
        HABLEIdentityResolver *r=[HABLEIdentityResolver new];[r loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
        [r setValue:[NSMutableSet setWithObject:@"02:00:00:00:00:02"] forKey:@"proxySources"];
        NSDictionary *row=@{@"local_address":@"02:11:22:33:44:55",@"last_seen":@(NSDate.date.timeIntervalSince1970),@"profile":@{@"name":@"Display Model43",@"services":@[]},@"tokens":@[],@"fingerprints":@{}};
        [r observeInventory:@{@"schema":@1,@"source":@"02:00:00:00:00:02",@"time":@(NSDate.date.timeIntervalSince1970),@"observations":@[row]} source:@"02:00:00:00:00:02"];
        XCTAssertEqual([[r valueForKey:@"peerInventories"] count],0u);
        XCTAssertTrue([[r inventoryDiagnostics][@"peer_observations_disabled"] boolValue]);
    } @finally {if(previous)[defaults setObject:previous forKey:@"HABLEIdentityIgnorePeerObservations"];else[defaults removeObjectForKey:@"HABLEIdentityIgnorePeerObservations"];}
}
- (void)testConfiguredLocalAliasBecomesSharedGattIdentityWithoutChangingItsAddress {
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"device":@{@"mac":@"00:11:22:33:44:55",@"uuid":@"11111111-1111-4111-8111-111111111111"}} options:0 error:nil];
    NSDictionary *reads=[HABLEIdentityEvidence fingerprintsForValue:data path:@"s/1234/c/5678"],*once=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:@{} session:@"one" atTime:1],*fields=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:once session:@"two" atTime:2];
    NSString *localAddress=@"02:11:22:33:44:55";
    NSArray *devices=@[@{@"id":@"configured-local",@"name_by_user":@"Existing sensor",@"connections":@[@[@"bluetooth",localAddress]]}];
    NSDictionary *o=@{@"identifier":@"first-apple-uuid",@"local_address":localAddress,@"name":@"Unit",@"last_seen":@(NSDate.date.timeIntervalSince1970),@"gatt_fingerprints":fields};
    HABLEIdentityResolver *first=[HABLEIdentityResolver new];[first loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];[first recordObservation:o identifier:o[@"identifier"]];
    NSMutableDictionary *synthetic=[[first automaticMatchForObservation:o] mutableCopy];synthetic[@"schema"]=@2;synthetic[@"proof_id"]=@"earlier-synthetic";
    [first loadRegistry:devices entries:@[] excludingSource:@"02:00:00:00:00:01"];
    [first loadCatalog:@{@"schema":@2,@"bindings":@{synthetic[@"address"]:synthetic}}];
    NSMutableDictionary *preserved=[[first automaticMatchForObservation:o] mutableCopy];
    XCTAssertEqualObjects(preserved[@"address"],localAddress);XCTAssertEqualObjects(preserved[@"device_id"],@"configured-local");XCTAssertEqualObjects(preserved[@"method"],@"gatt_fingerprint");
    preserved[@"schema"]=@2;preserved[@"proof_id"]=@"preserved-local";
    HABLEIdentityResolver *joining=[HABLEIdentityResolver new];[joining loadRegistry:devices entries:@[] excludingSource:@"02:00:00:00:00:02"];
    [joining loadCatalog:@{@"schema":@2,@"bindings":@{synthetic[@"address"]:synthetic,localAddress:preserved}}];
    XCTAssertEqual(joining.knownDevices.count,1u,@"The configured local alias and compatible synthetic root form one canonical identity");
    NSDictionary *unread=@{@"identifier":@"unread",@"name":@"Unit",@"last_seen":@(NSDate.date.timeIntervalSince1970)};
    XCTAssertTrue([joining hasFingerprintProbeReferenceForObservation:unread]);
    [joining recordObservation:unread identifier:@"unread"];XCTAssertNil([joining automaticMatchForObservation:unread],@"A same-name catalog probe hint is not identity proof");
    XCTAssertFalse([joining hasFingerprintProbeReferenceForObservation:@{@"name":@"Unrelated"}]);
    NSString *uuidPath=@"s/1234/c/5678/json/device/uuid";
    NSDictionary *other=@{@"identifier":@"different-apple-uuid",@"local_address":@"02:66:77:88:99:AA",@"name":@"Unit",@"last_seen":@(NSDate.date.timeIntervalSince1970),@"gatt_fingerprints":@{uuidPath:once[uuidPath]}};
    [joining recordObservation:other identifier:other[@"identifier"]];
    XCTAssertEqualObjects([joining automaticMatchForObservation:other][@"address"],localAddress,@"A joining proxy can use a fresh secondary witness and retain the original HA device");
    [first loadRegistry:[devices arrayByAddingObject:@{@"id":@"duplicate-configured",@"connections":@[@[@"bluetooth",localAddress]]}] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    XCTAssertNil([first automaticMatchForObservation:o],@"Conflicting HA device ownership must not be silently selected");
}
- (void)testProvisionalNativeMatchCannotReplaceAnAlreadyConfiguredLocalAlias {
    HABLEIdentityResolver *resolver=[HABLEIdentityResolver new];NSString *local=@"02:11:22:33:44:55";
    [resolver loadRegistry:@[@{@"id":@"existing-local",@"connections":@[@[@"bluetooth",local]]}] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;NSDictionary *o=nil;
    for(NSUInteger i=0;i<4;i++)o=[self recordPassiveUnit:@"Unit1234" identifier:@"a" address:@"AA:BB:CC:DD:EE:01" resolver:resolver atTime:now-30+i*10];
    NSMutableDictionary *configured=[o mutableCopy];configured[@"local_address"]=local;
    [resolver recordObservation:configured identifier:@"a"];
    XCTAssertNil([resolver automaticMatchForObservation:configured]);
    XCTAssertTrue([[resolver evidenceForIdentifier:@"a"] containsString:@"Preserving the configured local address"]);
    XCTAssertEqual([[resolver valueForKey:@"catalog"] count],0u,@"Provisional similarity cannot become a published identity bridge");
}
- (void)testIndependentFingerprintRootsPoolFieldsAndChooseOneCanonicalAddress {
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"device":@{@"mac":@"00:11:22:33:44:55",@"uuid":@"11111111-1111-4111-8111-111111111111"}} options:0 error:nil];
    NSDictionary *reads=[HABLEIdentityEvidence fingerprintsForValue:data path:@"s/1234/c/5678"],*once=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:@{} session:@"one" atTime:1],*fields=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:once session:@"two" atTime:2];
    NSString *mac=@"s/1234/c/5678/json/device/mac",*uuid=@"s/1234/c/5678/json/device/uuid";
    NSMutableArray *bindings=NSMutableArray.array;
    for(NSUInteger i=0;i<2;i++) {
        HABLEIdentityResolver *r=[HABLEIdentityResolver new];[r loadRegistry:@[] entries:@[] excludingSource:i ? @"02:00:00:00:00:02" : @"02:00:00:00:00:01"];
        NSMutableDictionary *profile=[fields mutableCopy];if(i) {
            profile[mac]=once[mac];NSMutableDictionary *extra=[fields[uuid] mutableCopy];extra[@"sha256"]=[@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];profile[@"s/1234/c/5678/json/device/z_id"]=extra;
        }
        NSDictionary *o=@{@"identifier":@"local",@"name":@"Unit",@"last_seen":@(NSDate.date.timeIntervalSince1970),@"gatt_fingerprints":profile};[r recordObservation:o identifier:@"local"];
        NSMutableDictionary *binding=[[r automaticMatchForObservation:o] mutableCopy];binding[@"schema"]=@2;binding[@"proof_id"]=[NSString stringWithFormat:@"root-%lu",(unsigned long)i];[bindings addObject:binding];
    }
    XCTAssertNotEqualObjects(bindings[0][@"address"],bindings[1][@"address"]);
    NSDictionary *catalog=@{@"schema":@2,@"bindings":@{bindings[0][@"address"]:bindings[0],bindings[1][@"address"]:bindings[1]}};
    NSString *canonical=[@[bindings[0][@"address"],bindings[1][@"address"]] sortedArrayUsingSelector:@selector(compare:)].firstObject;
    for(NSString *path in @[mac,uuid]) {
        HABLEIdentityResolver *r=[HABLEIdentityResolver new];[r loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:03"];[r loadCatalog:catalog];
        XCTAssertEqual(r.knownDevices.count,1u);
        NSDictionary *o=@{@"identifier":@"reader",@"name":@"Unit",@"last_seen":@(NSDate.date.timeIntervalSince1970),@"gatt_fingerprints":@{path:once[path]}};[r recordObservation:o identifier:@"reader"];
        XCTAssertEqualObjects([r automaticMatchForObservation:o][@"address"],canonical);
    }
    HABLEIdentityResolver *registered=[HABLEIdentityResolver new];
    [registered loadRegistry:@[@{@"id":@"configured",@"name":@"Configured unit",@"connections":@[@[@"bluetooth",bindings[1][@"address"]]]}] entries:@[] excludingSource:@"02:00:00:00:00:03"];[registered loadCatalog:catalog];
    NSDictionary *o=@{@"identifier":@"reader",@"name":@"Unit",@"last_seen":@(NSDate.date.timeIntervalSince1970),@"gatt_fingerprints":fields};[registered recordObservation:o identifier:@"reader"];
    XCTAssertEqualObjects([registered automaticMatchForObservation:o][@"address"],bindings[1][@"address"]);
    HABLEIdentityResolver *firstConfigured=[HABLEIdentityResolver new];
    [firstConfigured loadRegistry:@[@{@"id":@"configured-first",@"connections":@[@[@"bluetooth",bindings[0][@"address"]]]}] entries:@[] excludingSource:@"02:00:00:00:00:04"];[firstConfigured loadCatalog:catalog];
    NSString *extraPath=@"s/1234/c/5678/json/device/z_id";NSDictionary *exclusive=@{@"identifier":@"exclusive-reader",@"name":@"Unit",@"last_seen":@(NSDate.date.timeIntervalSince1970),@"gatt_fingerprints":@{extraPath:bindings[1][@"fingerprint_profile"][extraPath]}};
    [firstConfigured recordObservation:exclusive identifier:@"exclusive-reader"];NSMutableDictionary *cached=[[firstConfigured automaticMatchForObservation:exclusive] mutableCopy];
    XCTAssertEqualObjects(cached[@"address"],bindings[0][@"address"]);XCTAssertNotNil(cached[@"canonical_origin_proof"]);
    cached[@"schema"]=@2;cached[@"proof_id"]=bindings[0][@"proof_id"];[firstConfigured valueForKey:@"localBindings"][@"exclusive-reader"]=cached;
    [firstConfigured loadCatalog:@{@"schema":@2,@"bindings":@{bindings[1][@"address"]:bindings[1]}}];
    XCTAssertEqualObjects([firstConfigured valueForKey:@"pendingPublications"][bindings[0][@"address"]],bindings[0],@"Repair the original proof, not a derived union");
    NSMutableDictionary *changed=[bindings[1] mutableCopy],*changedFields=[changed[@"fingerprint_profile"] mutableCopy],*changedMAC=[fields[mac] mutableCopy];
    changedMAC[@"sha256"]=[@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0];changedFields[mac]=changedMAC;changed[@"fingerprint_profile"]=changedFields;
    [firstConfigured loadCatalog:@{@"schema":@2,@"bindings":@{bindings[0][@"address"]:bindings[0],changed[@"address"]:changed}}];
    XCTAssertEqualObjects([firstConfigured automaticMatchForObservation:exclusive][@"address"],bindings[1][@"address"],@"A cached union cannot override new contradictory evidence");
    HABLEIdentityResolver *twoConfigured=[HABLEIdentityResolver new];
    [twoConfigured loadRegistry:@[@{@"id":@"one",@"connections":@[@[@"bluetooth",bindings[0][@"address"]]]},@{@"id":@"two",@"connections":@[@[@"bluetooth",bindings[1][@"address"]]]}] entries:@[] excludingSource:@"02:00:00:00:00:03"];
    [twoConfigured loadCatalog:catalog];[twoConfigured recordObservation:o identifier:@"reader"];
    XCTAssertEqual(twoConfigured.knownDevices.count,2u);XCTAssertNil([twoConfigured automaticMatchForObservation:o]);

}
- (void)testFingerprintReconciliationRejectsContradictoryTransitiveBridge {
    NSArray *values=@[@{@"a_id":@"11111111-1111-4111-8111-111111111111",@"b_id":@"44444444-4444-4444-8444-444444444444"},@{@"b_id":@"44444444-4444-4444-8444-444444444444",@"c_id":@"55555555-5555-4555-8555-555555555555"},@{@"a_id":@"33333333-3333-4333-8333-333333333333",@"c_id":@"55555555-5555-4555-8555-555555555555"}];
    NSMutableDictionary *bindings=NSMutableDictionary.dictionary;NSMutableArray *observations=NSMutableArray.array;
    for(NSUInteger i=0;i<values.count;i++) {
        NSDictionary *reads=[HABLEIdentityEvidence fingerprintsForValue:[NSJSONSerialization dataWithJSONObject:@{@"device":values[i]} options:0 error:nil] path:@"s/1234/c/5678"];
        NSDictionary *fields=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:[HABLEIdentityEvidence mergeFingerprintReads:reads previous:@{} session:@"one" atTime:1] session:@"two" atTime:2];
        HABLEIdentityResolver *r=[HABLEIdentityResolver new];[r loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
        NSDictionary *o=@{@"identifier":@"unit",@"name":@"Unit",@"last_seen":@(NSDate.date.timeIntervalSince1970),@"gatt_fingerprints":fields};[observations addObject:o];[r recordObservation:o identifier:@"unit"];
        NSMutableDictionary *proof=[[r automaticMatchForObservation:o] mutableCopy];proof[@"schema"]=@2;proof[@"proof_id"]=[NSString stringWithFormat:@"proof-%lu",(unsigned long)i];bindings[proof[@"address"]]=proof;
    }
    HABLEIdentityResolver *r=[HABLEIdentityResolver new];[r loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:09"];[r loadCatalog:@{@"schema":@2,@"bindings":bindings}];
    XCTAssertEqual(r.knownDevices.count,3u);[r recordObservation:observations[1] identifier:@"unit"];
    XCTAssertNil([r automaticMatchForObservation:observations[1]],@"An intermediate proof cannot hide disagreement between endpoints");
}
- (void)testOfflineCatalogConflictCannotReuseAnExistingFingerprintAddress {
    NSMutableArray *observations=NSMutableArray.array;NSArray *ids=@[@"11111111-1111-4111-8111-111111111111",@"22222222-2222-4222-8222-222222222222"];
    for(NSString *identity in ids) {
        NSDictionary *reads=[HABLEIdentityEvidence fingerprintsForValue:[NSJSONSerialization dataWithJSONObject:@{@"device":@{@"mac":@"00:11:22:33:44:55",@"z_uuid":identity}} options:0 error:nil] path:@"s/1234/c/5678"];
        NSDictionary *fields=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:[HABLEIdentityEvidence mergeFingerprintReads:reads previous:@{} session:@"one" atTime:1] session:@"two" atTime:2];
        [observations addObject:@{@"identifier":identity,@"name":@"Unit",@"last_seen":@(NSDate.date.timeIntervalSince1970),@"gatt_fingerprints":fields}];
    }
    HABLEIdentityResolver *a=[HABLEIdentityResolver new];[a loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];[a recordObservation:observations[0] identifier:ids[0]];
    NSMutableDictionary *proof=[[a automaticMatchForObservation:observations[0]] mutableCopy];proof[@"schema"]=@2;proof[@"proof_id"]=@"existing-catalog-proof";
    HABLEIdentityResolver *b=[HABLEIdentityResolver new];[b loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:02"];[b loadCatalog:@{@"schema":@2,@"bindings":@{proof[@"address"]:proof}}];[b recordObservation:observations[1] identifier:ids[1]];
    NSDictionary *match=[b automaticMatchForObservation:observations[1]];
    XCTAssertNotNil(match);XCTAssertNotEqualObjects(match[@"address"],proof[@"address"]);XCTAssertTrue([match[@"fingerprint_witness"][@"path"] hasSuffix:@"/z_uuid"]);
}
- (NSDictionary *)stableIdentifierFields {
    NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"device":@{@"mac":@"00:11:22:33:44:55"}} options:0 error:nil];
    NSDictionary *reads=[HABLEIdentityEvidence fingerprintsForValue:json path:@"s/1234/c/5678"];
    NSDictionary *first=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:@{} session:@"one" atTime:1];
    return [HABLEIdentityEvidence mergeFingerprintReads:reads previous:first session:@"two" atTime:2];
}
- (NSDictionary *)standardContextReadsForManufacturer:(NSString *)manufacturer model:(NSString *)model {
    NSString *prefix=@"s/0000180a-0000-1000-8000-00805f9b34fb#0/";NSMutableDictionary *reads=NSMutableDictionary.dictionary;
    [reads addEntriesFromDictionary:[HABLEIdentityEvidence fingerprintsForValue:[manufacturer dataUsingEncoding:NSUTF8StringEncoding] path:[prefix stringByAppendingString:@"00002a29-0000-1000-8000-00805f9b34fb#0"]]];
    [reads addEntriesFromDictionary:[HABLEIdentityEvidence fingerprintsForValue:[model dataUsingEncoding:NSUTF8StringEncoding] path:[prefix stringByAppendingString:@"00002a24-0000-1000-8000-00805f9b34fb#0"]]];
    return reads;
}
- (void)testStandardIdentifiersCreateSingleProxyIdentitiesButModelStringsDoNot {
    NSString *service=@"s/0000180a-0000-1000-8000-00805f9b34fb#0/";
    NSString *serial=[service stringByAppendingString:@"00002a25-0000-1000-8000-00805f9b34fb#0"],*system=[service stringByAppendingString:@"00002a23-0000-1000-8000-00805f9b34fb#0"],*model=[service stringByAppendingString:@"00002a24-0000-1000-8000-00805f9b34fb#0"];
    NSArray *paths=@[serial,system,model];NSData *data=[@"SN123456" dataUsingEncoding:NSUTF8StringEncoding];
    for(NSUInteger i=0;i<paths.count;i++) {
        NSMutableDictionary *reads=[[HABLEIdentityEvidence fingerprintsForValue:data path:paths[i]] mutableCopy];if(i==0)[reads addEntriesFromDictionary:[self standardContextReadsForManufacturer:@"Example Manufacturer" model:@"Model-A"]];
        NSDictionary *first=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:@{} session:@"first" atTime:1];XCTAssertFalse([HABLEIdentityEvidence isIdentifierFingerprint:first[paths[i]] path:paths[i]]);
        NSDictionary *fields=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:first session:@"second" atTime:2];
        HABLEIdentityResolver *resolver=[HABLEIdentityResolver new];[resolver loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
        NSDictionary *o=@{@"identifier":@"unit",@"name":@"Unit",@"last_seen":@(NSDate.date.timeIntervalSince1970),@"gatt_fingerprints":fields};
        [resolver recordObservation:o identifier:@"unit"];NSDictionary *match=[resolver automaticMatchForObservation:o];
        if(i<2){XCTAssertNotNil(match);XCTAssertEqualObjects(match[@"fingerprint_witness"][@"format"],i==0 ? @"gatt_serial" : @"gatt_system_id");}
        else XCTAssertNil(match);
    }
    for(NSString *placeholder in @[@"unknown",@"00000000",@"serial number"])XCTAssertEqual([HABLEIdentityEvidence fingerprintsForValue:[placeholder dataUsingEncoding:NSUTF8StringEncoding] path:serial].count,0u);
    XCTAssertEqual([HABLEIdentityEvidence fingerprintsForValue:[NSData dataWithBytes:"\0\0\0\0\0\0\0\0" length:8] path:system].count,0u);
    NSString *wrongService=[serial stringByReplacingOccurrencesOfString:@"0000180a" withString:@"00001234"];
    NSDictionary *forged=@{@"format":@"gatt_serial",@"length":@8,@"sessions":@2,@"stable_across_sessions":@YES,@"varying":@NO};
    XCTAssertFalse([HABLEIdentityEvidence isIdentifierFingerprint:forged path:wrongService]);
}
- (void)testSerialNumbersAreScopedByManufacturerAndModel {
    NSString *path=@"s/0000180a-0000-1000-8000-00805f9b34fb#0/00002a25-0000-1000-8000-00805f9b34fb#0";
    HABLEIdentityResolver *r=[HABLEIdentityResolver new];[r loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];NSMutableArray *observations=NSMutableArray.array,*addresses=NSMutableArray.array;
    for(NSUInteger i=0;i<3;i++) {
        NSMutableDictionary *reads=[[HABLEIdentityEvidence fingerprintsForValue:[@"SN123456" dataUsingEncoding:NSUTF8StringEncoding] path:path] mutableCopy];
        [reads addEntriesFromDictionary:[self standardContextReadsForManufacturer:i==1 ? @"Other Manufacturer" : @"Example Manufacturer" model:i==2 ? @"Model-B" : @"Model-A"]];
        NSDictionary *once=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:@{} session:@"one" atTime:1],*fields=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:once session:@"two" atTime:2];
        NSString *identifier=[NSString stringWithFormat:@"device-%lu",(unsigned long)i];NSDictionary *o=@{@"identifier":identifier,@"name":@"Unit",@"last_seen":@(NSDate.date.timeIntervalSince1970),@"gatt_fingerprints":fields};[observations addObject:o];[r recordObservation:o identifier:identifier];
    }
    for(NSDictionary *o in observations){NSDictionary *match=[r automaticMatchForObservation:o];XCTAssertNotNil(match);if(match)[addresses addObject:match[@"address"]];}
    XCTAssertEqual([NSSet setWithArray:addresses].count,3u);
    NSDictionary *good=[r automaticMatchForObservation:observations[0]];
    for(NSDictionary *corruption in @[@{@"sessions":NSNull.null},@{@"length":@0},@{@"varying":NSNull.null}]) {
        NSMutableDictionary *bad=[good mutableCopy];bad[@"schema"]=@2;bad[@"proof_id"]=@"invalid-context";
        NSMutableDictionary *profile=[bad[@"fingerprint_profile"] mutableCopy];
        NSString *manufacturer=[path stringByReplacingOccurrencesOfString:@"00002a25" withString:@"00002a29"];
        NSMutableDictionary *value=[profile[manufacturer] mutableCopy];[value addEntriesFromDictionary:corruption];profile[manufacturer]=value;bad[@"fingerprint_profile"]=profile;
        HABLEIdentityResolver *receiver=[HABLEIdentityResolver new];[receiver loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:09"];
        [receiver loadCatalog:@{@"schema":@2,@"bindings":@{bad[@"address"]:bad}}];XCTAssertEqual(receiver.knownDevices.count,0u);
    }

    HABLEIdentityResolver *missing=[HABLEIdentityResolver new];[missing loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:02"];
    NSMutableDictionary *o=[observations[0] mutableCopy];o[@"gatt_fingerprints"]=@{path:o[@"gatt_fingerprints"][path]};
    XCTAssertNil([missing automaticMatchForObservation:o]);
}
- (void)testJoiningProxyCanUseASecondaryVerifiedIdentifierWithoutChangingCanonicalAddress {
    NSString *serial=@"s/0000180a-0000-1000-8000-00805f9b34fb#0/00002a25-0000-1000-8000-00805f9b34fb#0",*system=@"s/0000180a-0000-1000-8000-00805f9b34fb#0/00002a23-0000-1000-8000-00805f9b34fb#0";
    NSMutableDictionary *reads=NSMutableDictionary.dictionary;NSData *data=[@"SN123456" dataUsingEncoding:NSUTF8StringEncoding];
    for(NSString *path in @[serial,system])[reads addEntriesFromDictionary:[HABLEIdentityEvidence fingerprintsForValue:data path:path]];[reads addEntriesFromDictionary:[self standardContextReadsForManufacturer:@"Example Manufacturer" model:@"Model-A"]];
    NSDictionary *once=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:@{} session:@"one" atTime:1],*twice=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:once session:@"two" atTime:2];
    HABLEIdentityResolver *a=[HABLEIdentityResolver new];[a loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    NSDictionary *o=@{@"identifier":@"a",@"name":@"Unit",@"last_seen":@(NSDate.date.timeIntervalSince1970),@"gatt_fingerprints":twice};[a recordObservation:o identifier:@"a"];
    NSDictionary *initial=[a automaticMatchForObservation:o];XCTAssertEqualObjects(initial[@"fingerprint_witness"][@"path"],system);
    NSMutableDictionary *binding=[initial mutableCopy];binding[@"schema"]=@2;binding[@"proof_id"]=@"multi-field-proof";
    HABLEIdentityResolver *b=[HABLEIdentityResolver new];[b loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:02"];[b loadCatalog:@{@"schema":@2,@"bindings":@{binding[@"address"]:binding}}];
    NSMutableDictionary *joined=[o mutableCopy];joined[@"identifier"]=@"b";NSMutableDictionary *partial=[once mutableCopy];[partial removeObjectForKey:system];joined[@"gatt_fingerprints"]=partial;[b recordObservation:joined identifier:@"b"];
    NSDictionary *match=[b automaticMatchForObservation:joined];XCTAssertEqualObjects(match[@"address"],initial[@"address"]);XCTAssertEqualObjects(match[@"fingerprint_witness"][@"path"],system);XCTAssertEqualObjects(match[@"fingerprint_match_witness"][@"path"],serial);
    NSMutableDictionary *twin=[joined mutableCopy];twin[@"identifier"]=@"twin";[b recordObservation:twin identifier:@"twin"];
    XCTAssertNil([b automaticMatchForObservation:joined]);
}
- (void)testSingleProxyFingerprintIdentitySurvivesReloadAndASecondProxyJoining {
    NSDictionary *fields=[self stableIdentifierFields];NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    HABLEIdentityResolver *first=[HABLEIdentityResolver new];[first loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    NSDictionary *observation=@{@"identifier":@"first-apple-uuid",@"name":@"Unit",@"last_seen":@(now),@"gatt_fingerprints":fields};
    [first recordObservation:observation identifier:observation[@"identifier"]];NSDictionary *match=[first automaticMatchForObservation:observation];
    XCTAssertEqualObjects(match[@"identity_kind"],@"observed_shared");XCTAssertEqualObjects(match[@"supporting_sources"],(@[@"02:00:00:00:00:01"]));XCTAssertNotEqualObjects(match[@"address"],@"00:11:22:33:44:55");
    NSMutableDictionary *binding=[match mutableCopy];binding[@"schema"]=@2;binding[@"proof_id"]=@"single-source-read-proof";
    NSDictionary *catalog=@{@"schema":@2,@"bindings":@{match[@"address"]:binding}};
    for(NSString *source in @[@"02:00:00:00:00:01",@"02:00:00:00:00:02"]) {
        HABLEIdentityResolver *receiver=[HABLEIdentityResolver new];[receiver loadRegistry:@[] entries:@[] excludingSource:source];[receiver loadCatalog:catalog];
        NSMutableDictionary *fresh=[observation mutableCopy];fresh[@"identifier"]=@"different-apple-uuid";NSMutableDictionary *oneRead=NSMutableDictionary.dictionary;
        for(NSString *path in fields){NSMutableDictionary *value=[fields[path] mutableCopy];value[@"sessions"]=@1;value[@"stable_across_sessions"]=@NO;oneRead[path]=value;}
        fresh[@"gatt_fingerprints"]=oneRead;[receiver recordObservation:fresh identifier:fresh[@"identifier"]];
        XCTAssertEqualObjects([receiver automaticMatchForObservation:fresh][@"address"],match[@"address"]);
    }
    NSMutableDictionary *twin=[observation mutableCopy];twin[@"identifier"]=@"twin";[first recordObservation:twin identifier:@"twin"];
    XCTAssertNil([first automaticMatchForObservation:observation]);
}
- (void)testConflictingPeerFieldsCannotCreateTheSameSingleSourceIdentity {
    NSMutableArray *observations=NSMutableArray.array,*resolvers=NSMutableArray.array;
    NSArray *sources=@[@"02:00:00:00:00:01",@"02:00:00:00:00:02"],*uuids=@[@"11111111-1111-4111-8111-111111111111",@"22222222-2222-4222-8222-222222222222"];
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    for(NSUInteger i=0;i<2;i++) {
        NSDictionary *reads=[HABLEIdentityEvidence fingerprintsForValue:[NSJSONSerialization dataWithJSONObject:@{@"device":@{@"mac":@"00:11:22:33:44:55",@"z_uuid":uuids[i]}} options:0 error:nil] path:@"s/1234/c/5678"];
        NSDictionary *fields=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:[HABLEIdentityEvidence mergeFingerprintReads:reads previous:@{} session:@"first" atTime:now-1] session:@"second" atTime:now];
        NSDictionary *o=@{@"identifier":sources[i],@"local_address":sources[i],@"name":@"Unit",@"last_seen":@(now),@"gatt_fingerprints":fields};[observations addObject:o];
        HABLEIdentityResolver *r=[HABLEIdentityResolver new];[r loadRegistry:@[] entries:@[] excludingSource:sources[i]];[r setValue:[NSMutableSet setWithObject:sources[1-i]] forKey:@"proxySources"];[r recordObservation:o identifier:sources[i]];[resolvers addObject:r];
    }
    for(NSUInteger i=0;i<2;i++)[(HABLEIdentityResolver *)resolvers[i] observeInventory:@{@"schema":@1,@"source":sources[1-i],@"time":@(now),@"observations":[resolvers[1-i] localInventoryAtTime:now]} source:sources[1-i]];
    NSDictionary *a=[resolvers[0] automaticMatchForObservation:observations[0]],*b=[resolvers[1] automaticMatchForObservation:observations[1]];
    XCTAssertNotNil(a);XCTAssertNotNil(b);XCTAssertNotEqualObjects(a[@"address"],b[@"address"]);
    XCTAssertTrue([a[@"fingerprint_witness"][@"path"] hasSuffix:@"/z_uuid"]);XCTAssertTrue([b[@"fingerprint_witness"][@"path"] hasSuffix:@"/z_uuid"]);
}
- (void)testPeerOnlyIdentifierFingerprintCreatesOneSharedSyntheticIdentity {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;NSDictionary *fields=[self stableIdentifierFields];
    HABLEIdentityResolver *a=[HABLEIdentityResolver new],*b=[HABLEIdentityResolver new];
    [a loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];[b loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:02"];
    [a setValue:[NSMutableSet setWithObject:@"02:00:00:00:00:02"] forKey:@"proxySources"];[b setValue:[NSMutableSet setWithObject:@"02:00:00:00:00:01"] forKey:@"proxySources"];
    NSDictionary *oa=@{@"identifier":@"a",@"local_address":@"02:11:22:33:44:55",@"name":@"Unit",@"last_seen":@(now),@"gatt_fingerprints":fields};
    NSMutableDictionary *ob=[oa mutableCopy];ob[@"identifier"]=@"b";ob[@"local_address"]=@"02:22:33:44:55:66";
    [a recordObservation:oa identifier:@"a"];[b recordObservation:ob identifier:@"b"];
    XCTAssertEqual([[a automaticMatchForObservation:oa][@"supporting_sources"] count],1u);
    [a observeInventory:@{@"schema":@1,@"source":@"02:00:00:00:00:02",@"time":@(now),@"observations":[b localInventoryAtTime:now]} source:@"02:00:00:00:00:02"];
    [b observeInventory:@{@"schema":@1,@"source":@"02:00:00:00:00:01",@"time":@(now),@"observations":[a localInventoryAtTime:now]} source:@"02:00:00:00:00:01"];
    NSDictionary *ma=[a automaticMatchForObservation:oa],*mb=[b automaticMatchForObservation:ob];
    XCTAssertEqualObjects(ma[@"identity_kind"],@"observed_shared");XCTAssertEqualObjects(ma[@"address"],mb[@"address"]);XCTAssertNotEqualObjects(ma[@"address"],@"00:11:22:33:44:55");
    NSMutableDictionary *binding=[ma mutableCopy];binding[@"schema"]=@2;binding[@"proof_id"]=@"verified-peer-proof";
    HABLEIdentityResolver *fresh=[HABLEIdentityResolver new];[fresh loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:03"];
    [fresh loadCatalog:@{@"schema":@2,@"bindings":@{ma[@"address"]:binding}}];
    NSMutableDictionary *oneRead=[oa mutableCopy];NSMutableDictionary *singleFields=NSMutableDictionary.dictionary;
    for(NSString *path in fields){NSMutableDictionary *value=[fields[path] mutableCopy];value[@"sessions"]=@1;value[@"stable_across_sessions"]=@NO;singleFields[path]=value;}
    oneRead[@"gatt_fingerprints"]=singleFields;
    XCTAssertEqualObjects(([fresh automaticMatchForObservation:oneRead][@"address"]),ma[@"address"]);
    NSMutableDictionary *twin=[ob mutableCopy];twin[@"local_address"]=@"02:33:44:55:66:77";twin[@"identifier"]=@"twin";[b recordObservation:twin identifier:@"twin"];
    [a observeInventory:@{@"schema":@1,@"source":@"02:00:00:00:00:02",@"time":@(now),@"observations":[b localInventoryAtTime:now]} source:@"02:00:00:00:00:02"];
    XCTAssertNil([a automaticMatchForObservation:oa]);XCTAssertTrue([[a evidenceForIdentifier:@"a"] containsString:@"Ambiguous"]);
}
- (void)testConflictingStrongIdentifiersCannotBeOutvotedByAnotherMatchingField {
    NSDictionary *fields=[self stableIdentifierFields];NSString *path=fields.allKeys.firstObject;
    NSMutableDictionary *a=[fields mutableCopy],*b=[fields mutableCopy];NSMutableDictionary *changed=[fields[path] mutableCopy];changed[@"sha256"]=[@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0];
    a[@"s/1234/c/5678/json/device/othermac"]=fields[path];b[@"s/1234/c/5678/json/device/othermac"]=changed;
    XCTAssertTrue([HABLEIdentityEvidence identifierFingerprints:a conflictWith:b]);
}
- (void)testContextAddressesAndSingleSessionValuesAreNotIdentifierProof {
    NSDictionary *reads=[HABLEIdentityEvidence fingerprintsForValue:[NSJSONSerialization dataWithJSONObject:@{@"wifi":@{@"bssid":@"00:11:22:33:44:55"},@"device":@{@"uuid":@"00000000-0000-0000-0000-000000000000"}} options:0 error:nil] path:@"attribute"];
    NSDictionary *first=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:@{} session:@"one" atTime:1];
    NSDictionary *stable=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:first session:@"two" atTime:2];
    for(NSString *path in stable)XCTAssertFalse([HABLEIdentityEvidence isIdentifierFingerprint:stable[path] path:path]);
    NSDictionary *identifiers=[self stableIdentifierFields];NSString *path=identifiers.allKeys.firstObject;NSMutableDictionary *single=[identifiers[path] mutableCopy];single[@"sessions"]=@1;
    XCTAssertFalse([HABLEIdentityEvidence isIdentifierFingerprint:single path:path]);
}
- (void)testUnregisteredPeerInventoryIsSharedButNotPromotedToVerifiedIdentity {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    HABLEIdentityResolver *sender=[HABLEIdentityResolver new];[sender loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    NSDictionary *observation=@{@"identifier":@"local",@"local_address":@"02:11:22:33:44:55",@"name":@"Unregistered unit",@"last_seen":@(now)};
    [sender recordObservation:observation identifier:@"local"];
    NSArray *inventory=[sender localInventoryAtTime:now];XCTAssertEqual(inventory.count,1u);XCTAssertNil(inventory[0][@"address"]);
    HABLEIdentityResolver *receiver=[HABLEIdentityResolver new];[receiver loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:02"];
    [receiver setValue:[NSMutableSet setWithArray:@[@"02:00:00:00:00:01",@"02:00:00:00:00:03"]] forKey:@"proxySources"];
    NSMutableDictionary *row=[inventory[0] mutableCopy];row[@"address"]=@"00:11:22:33:44:55";row[@"proof_id"]=@"unverified-claim";
    for(NSString *source in @[@"02:00:00:00:00:01",@"02:00:00:00:00:03"])[receiver observeInventory:@{@"schema":@1,@"source":source,@"time":@(now),@"observations":@[row]} source:source];
    NSArray *peers=[receiver peerObservationsForObservation:observation];XCTAssertEqual(peers.count,2u);
    for(NSDictionary *peer in peers)XCTAssertNil(peer[@"address"]);
    XCTAssertTrue([receiver hasKnownIdentityForObservation:observation]);XCTAssertNil([receiver automaticMatchForObservation:observation]);
}
- (void)testInventoryRejectsUnknownSourcesStaleRowsAndMalformedFingerprints {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;HABLEIdentityResolver *r=[HABLEIdentityResolver new];
    [r loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    NSDictionary *o=@{@"name":@"Unit",@"service_uuids":@[@"1234"]};
    NSMutableDictionary *row=[@{@"local_address":@"02:11:22:33:44:55",@"last_seen":@(now),@"profile":@{@"name":@"Unit",@"services":@[@"1234"]},@"fingerprints":@{@"path":@{@"sha256":@"invalid",@"length":@16,@"sessions":NSNull.null}}} mutableCopy];
    NSDictionary *value=@{@"schema":@1,@"source":@"02:00:00:00:00:02",@"time":@(now),@"observations":@[row]};
    [r observeInventory:value source:@"02:00:00:00:00:02"];XCTAssertEqual([r peerObservationsForObservation:o].count,0u);
    [r setValue:[NSMutableSet setWithObject:@"02:00:00:00:00:02"] forKey:@"proxySources"];
    row[@"last_seen"]=@(now-121);[r observeInventory:value source:@"02:00:00:00:00:02"];XCTAssertEqual([r peerObservationsForObservation:o].count,0u);
    row[@"last_seen"]=@(now);[r observeInventory:value source:@"02:00:00:00:00:02"];
    XCTAssertEqual([r peerObservationsForObservation:o].count,1u);XCTAssertEqual([[r peerObservationsForObservation:o][0][@"fingerprints"] count],0u);
}
- (void)testStructuredFingerprintsSeparateChangingFieldsAndExcludeCredentials {
    NSDictionary *a=@{@"identity":@{@"id":@"unit-a"},@"rssi":@(-50),@"wifi":@{@"password":@"private",@"client_token":@"private",@"ssid":@"network"}};
    NSMutableDictionary *b=[a mutableCopy];b[@"rssi"]=@(-60);
    NSDictionary *first=[HABLEIdentityEvidence fingerprintsForValue:[NSJSONSerialization dataWithJSONObject:a options:0 error:nil] path:@"characteristic"];
    NSDictionary *second=[HABLEIdentityEvidence fingerprintsForValue:[NSJSONSerialization dataWithJSONObject:b options:0 error:nil] path:@"characteristic"];
    XCTAssertNil(first[@"characteristic"]);XCTAssertNil(first[@"characteristic/json/wifi/password"]);XCTAssertNil(first[@"characteristic/json/wifi/client_token"]);
    XCTAssertEqualObjects(first[@"characteristic/json/identity/id"],second[@"characteristic/json/identity/id"]);
    XCTAssertNotEqualObjects(first[@"characteristic/json/rssi"],second[@"characteristic/json/rssi"]);
    XCTAssertFalse([[first description] containsString:@"unit-a"]);
    NSDictionary *history=[HABLEIdentityEvidence mergeFingerprintReads:first previous:@{} session:@"one" atTime:1];
    history=[HABLEIdentityEvidence mergeFingerprintReads:second previous:history session:@"two" atTime:2];
    XCTAssertTrue([history[@"characteristic/json/identity/id"][@"stable_across_sessions"] boolValue]);
    XCTAssertTrue([history[@"characteristic/json/rssi"][@"varying"] boolValue]);
}
- (void)testOpaqueFingerprintsRequireSeparateSessionsAndRememberVariation {
    NSDictionary *reads=@{@"service/characteristic":@{@"sha256":@"hash-a",@"length":@16}};
    NSDictionary *first=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:@{} session:@"one" atTime:1];
    XCTAssertFalse([first[@"service/characteristic"][@"stable_across_sessions"] boolValue]);
    NSDictionary *replay=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:first session:@"one" atTime:2];
    XCTAssertEqualObjects(replay,first);
    NSDictionary *stable=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:first session:@"two" atTime:3];
    XCTAssertTrue([stable[@"service/characteristic"][@"stable_across_sessions"] boolValue]);
    NSDictionary *changed=[HABLEIdentityEvidence mergeFingerprintReads:@{@"service/characteristic":@{@"sha256":@"hash-b",@"length":@16}} previous:stable session:@"three" atTime:4];
    XCTAssertTrue([changed[@"service/characteristic"][@"varying"] boolValue]);
    NSDictionary *again=[HABLEIdentityEvidence mergeFingerprintReads:reads previous:changed session:@"four" atTime:5];
    XCTAssertFalse([again[@"service/characteristic"][@"stable_across_sessions"] boolValue]);
    XCTAssertEqualObjects([HABLEIdentityEvidence mergeFingerprintReads:@{} previous:again session:@"five" atTime:6],again);
}
- (void)testAutomaticImportStartsPersistentSubscriptionsAndLoadsHADiscoveryMetadata {
    HABLETransportTestResolver *resolver=[HABLETransportTestResolver new];resolver.fakeConnection=[HABLEFakeIdentityConnection new];resolver.currentScope=YES;
    XCTestExpectation *done=[self expectationWithDescription:@"automatic import"];
    [resolver refreshExcludingSource:@"02:00:00:00:00:01" completion:^(NSError *error){XCTAssertNil(error);[done fulfill];}];
    [self waitForExpectationsWithTimeout:4 handler:nil];
    XCTAssertTrue(([resolver.fakeConnection.subscriptions containsObject:@"bluetooth/subscribe_advertisements"]));
    XCTAssertTrue(([resolver.fakeConnection.subscriptions containsObject:@"frontend/subscribe_system_data"]));
    XCTAssertTrue(([resolver hasKnownIdentityForObservation:@{@"name":@"Sample unit",@"service_uuids":@[@"1234"]}]));
    XCTAssertFalse(([resolver hasKnownIdentityForObservation:@{@"name":@"Sample unit",@"service_uuids":@[@"9999"]}]));
    resolver.fakeConnection.registryHandler(@{});XCTAssertTrue((resolver.needsRegistryRefresh));
}
- (void)testChangedAccountStopsAnOutstandingImport {
    HABLETransportTestResolver *resolver=[HABLETransportTestResolver new];resolver.fakeConnection=[HABLEFakeIdentityConnection new];resolver.fakeConnection.delayUser=YES;resolver.currentScope=YES;
    [resolver refreshExcludingSource:@"02:00:00:00:00:01" completion:^(NSError *error){XCTFail(@"A cancelled account scope must not complete a new import");}];
    resolver.currentScope=NO;resolver.fakeConnection.pendingUser(@{@"id":@"old-user"},nil);
    XCTAssertEqual(resolver.fakeConnection.commands.count,1u);
}
- (void)testACommonStaticChannelCannotHideConflictingPayloads {
    XCTAssertFalse(([HABLEIdentityEvidence tokens:@[@"m:AQIDBA==",@"s:1234:AAAAAA=="] agreeWith:@[@"m:BQYHCA==",@"s:1234:AAAAAA=="]]));
}
- (void)testShiftedSequencesAreNotAcceptedAsClockAligned {
    HABLEIdentityEvidence *engine=[HABLEIdentityEvidence new];NSTimeInterval start=NSDate.date.timeIntervalSince1970-75;
    for(NSUInteger i=0;i<16;i++) {NSDictionary *o=[self observation:i+100 at:start+i*3.5];[engine recordLocal:o identifier:@"one" atTime:start+i*3.5];[engine recordRemoteTokens:[HABLEIdentityEvidence tokensForObservation:o] address:@"00:11:22:33:44:55" source:@"native" atTime:start+i*3.5+10];}
    XCTAssertFalse(([[engine correlationForIdentifier:@"one" address:@"00:11:22:33:44:55" now:NSDate.date.timeIntervalSince1970][@"qualified"] boolValue]));
}

- (NSDictionary *)observation:(NSUInteger)value at:(NSTimeInterval)at {
    uint8_t bytes[]={(uint8_t)value,(uint8_t)(value>>8),0x12,0x34};
    return @{@"identifier":@"local-one",@"name":@"s",@"manufacturer_data":[[NSData dataWithBytes:bytes length:4] base64EncodedStringWithOptions:0],@"service_uuids":@[@"1234"],@"last_seen":@(at)};
}
- (void)fill:(HABLEIdentityEvidence *)engine local:(NSString *)identifier address:(NSString *)address offset:(NSInteger)offset {
    NSTimeInterval start=NSDate.date.timeIntervalSince1970-55;
    for(NSUInteger i=0;i<16;i++) {
        NSDictionary *observation=[self observation:i+100 at:start+i*3.5];
        [engine recordLocal:observation identifier:identifier atTime:start+i*3.5];
        [engine recordRemoteTokens:[HABLEIdentityEvidence tokensForObservation:[self observation:i+100+offset at:0]] address:address source:@"native" atTime:start+i*3.5+.2];
    }
}
- (void)testAlternatingLayoutsDoNotDiluteTheChangingChannel {
    HABLEIdentityEvidence *engine=[HABLEIdentityEvidence new];NSTimeInterval start=NSDate.date.timeIntervalSince1970-55;
    uint8_t fixed[20]={1,2,3,4,5,6,7,8};
    for(NSUInteger i=0;i<16;i++) {
        NSDictionary *value=[self observation:100+i at:start+i*3.5];
        [engine recordLocal:value identifier:@"one" atTime:start+i*3.5];
        [engine recordLocal:@{@"manufacturer_data":[[NSData dataWithBytes:fixed length:sizeof(fixed)] base64EncodedStringWithOptions:0]} identifier:@"one" atTime:start+i*3.5+1];
        [engine recordRemoteTokens:[HABLEIdentityEvidence tokensForObservation:value] address:@"00:11:22:33:44:55" source:@"native" atTime:start+i*3.5+.2];
    }
    XCTAssertTrue(([[engine correlationForIdentifier:@"one" address:@"00:11:22:33:44:55" now:NSDate.date.timeIntervalSince1970][@"qualified"] boolValue]));
}
- (void)testPeerBackfillPreservesOriginalObservationTimes {
    HABLEIdentityEvidence *producer=[HABLEIdentityEvidence new],*consumer=[HABLEIdentityEvidence new];NSTimeInterval start=NSDate.date.timeIntervalSince1970-800;
    for(NSUInteger i=0;i<16;i++) {NSDictionary *o=[self observation:100+i at:start+i*50];[producer recordLocal:o identifier:@"bound" atTime:start+i*50];[consumer recordLocal:o identifier:@"new" atTime:start+i*50+.3];}
    NSArray *events=[producer recentLocalEventsForIdentifier:@"bound" now:NSDate.date.timeIntervalSince1970];XCTAssertEqual(events.count,16u);
    for(NSDictionary *event in events)[consumer recordRemoteTokens:event[@"tokens"] address:@"00:11:22:33:44:55" source:@"peer" atTime:[event[@"time"] doubleValue] lastSeen:[event[@"last_seen"] doubleValue]];
    XCTAssertTrue(([[consumer correlationForIdentifier:@"new" address:@"00:11:22:33:44:55" now:NSDate.date.timeIntervalSince1970][@"qualified"] boolValue]));
}
- (void)testShortPayloadSequencesAreGenericEvidence {
    HABLEIdentityEvidence *engine=[HABLEIdentityEvidence new];[self fill:engine local:@"one" address:@"00:11:22:33:44:55" offset:0];
    XCTAssertTrue(([[engine correlationForIdentifier:@"one" address:@"00:11:22:33:44:55" now:NSDate.date.timeIntervalSince1970][@"qualified"] boolValue]));
}
- (void)testRecurringSameLengthPacketFamiliesDoNotDiluteCorroboratedChanges {
    HABLEIdentityEvidence *engine=[HABLEIdentityEvidence new];NSTimeInterval start=NSDate.date.timeIntervalSince1970-80;
    for(NSUInteger i=0;i<12;i++) {
        uint8_t bytes[]={0xa1,(uint8_t)i,0x32,0x45,0x56};
        NSDictionary *o=@{@"manufacturer_data":[[NSData dataWithBytes:bytes length:5] base64EncodedStringWithOptions:0]};
        [engine recordLocal:o identifier:@"local" atTime:start+i*6];
        [engine recordRemoteTokens:[HABLEIdentityEvidence tokensForObservation:o] address:@"00:11:22:33:44:55" source:@"native" atTime:start+i*6+.2];
        uint8_t auxiliary[]={0xb2,0x11,0x22,0x33,0x44};
        [engine recordLocal:@{@"manufacturer_data":[[NSData dataWithBytes:auxiliary length:5] base64EncodedStringWithOptions:0]} identifier:@"local" atTime:start+i*6+1];
    }
    XCTAssertTrue(([[engine correlationForIdentifier:@"local" address:@"00:11:22:33:44:55" now:NSDate.date.timeIntervalSince1970][@"qualified"] boolValue]));
}
- (void)testLearnedPacketFamiliesStillRejectContradictoryComparablePayloads {
    HABLEIdentityEvidence *engine=[HABLEIdentityEvidence new];NSTimeInterval start=NSDate.date.timeIntervalSince1970-80;
    for(NSUInteger i=0;i<12;i++) {
        uint8_t bytes[]={0xa1,(uint8_t)i,0x32,0x45,0x56};
        NSDictionary *o=@{@"manufacturer_data":[[NSData dataWithBytes:bytes length:5] base64EncodedStringWithOptions:0]};
        [engine recordLocal:o identifier:@"local" atTime:start+i*6];
        [engine recordRemoteTokens:[HABLEIdentityEvidence tokensForObservation:o] address:@"00:11:22:33:44:55" source:@"native" atTime:start+i*6+.2];
        uint8_t auxiliary[]={0xb2,0x11,0x22,0x33,0x44};
        [engine recordLocal:@{@"manufacturer_data":[[NSData dataWithBytes:auxiliary length:5] base64EncodedStringWithOptions:0]} identifier:@"local" atTime:start+i*6+1];
        uint8_t contradictory[]={0xb2,0x99,0x88,0x77,0x66};
        NSDictionary *other=@{@"manufacturer_data":[[NSData dataWithBytes:contradictory length:5] base64EncodedStringWithOptions:0]};
        [engine recordRemoteTokens:[HABLEIdentityEvidence tokensForObservation:other] address:@"00:11:22:33:44:55" source:@"native" atTime:start+i*6+1.2];
    }
    XCTAssertFalse(([[engine correlationForIdentifier:@"local" address:@"00:11:22:33:44:55" now:NSDate.date.timeIntervalSince1970][@"qualified"] boolValue]));
}
- (void)testDifferentReadingsDoNotMatch {
    HABLEIdentityEvidence *engine=[HABLEIdentityEvidence new];[self fill:engine local:@"one" address:@"00:11:22:33:44:55" offset:1000];
    XCTAssertFalse(([[engine correlationForIdentifier:@"one" address:@"00:11:22:33:44:55" now:NSDate.date.timeIntervalSince1970][@"qualified"] boolValue]));
}
- (void)testStaticReadingsAndRepeatedSnapshotsAreNotIdentity {
    HABLEIdentityEvidence *engine=[HABLEIdentityEvidence new];NSTimeInterval start=NSDate.date.timeIntervalSince1970-55;
    for(NSUInteger i=0;i<16;i++) {
        NSDictionary *o=[self observation:100 at:start+i*3.5];[engine recordLocal:o identifier:@"one" atTime:start+i*3.5];
        [engine recordRemoteTokens:[HABLEIdentityEvidence tokensForObservation:o] address:@"00:11:22:33:44:55" source:@"native" atTime:start+i*3.5];
    }
    XCTAssertFalse(([[engine correlationForIdentifier:@"one" address:@"00:11:22:33:44:55" now:NSDate.date.timeIntervalSince1970][@"qualified"] boolValue]));
}
- (void)testIndistinguishableLocalDevicesAreAmbiguous {
    HABLEIdentityEvidence *engine=[HABLEIdentityEvidence new];[self fill:engine local:@"one" address:@"00:11:22:33:44:55" offset:0];[self fill:engine local:@"two" address:@"00:11:22:33:44:55" offset:0];
    XCTAssertTrue(([engine hasCompetingLocalIdentifier:@"one" address:@"00:11:22:33:44:55" now:NSDate.date.timeIntervalSince1970]));
}
- (void)testStaleEvidenceIsRejected {
    HABLEIdentityEvidence *engine=[HABLEIdentityEvidence new];[self fill:engine local:@"one" address:@"00:11:22:33:44:55" offset:0];
    XCTAssertFalse(([[engine correlationForIdentifier:@"one" address:@"00:11:22:33:44:55" now:NSDate.date.timeIntervalSince1970+180][@"qualified"] boolValue]));
}
- (void)testRawAndCoreBluetoothPayloadsNormalizeIdentically {
    uint8_t raw[]={5,0xff,0x11,0x22,0x33,0x44};NSData *payload=[NSData dataWithBytes:raw+2 length:4];
    XCTAssertEqualObjects([HABLEIdentityEvidence tokensForRawAdvertisement:[NSData dataWithBytes:raw length:sizeof(raw)]],[HABLEIdentityEvidence tokensForObservation:@{@"manufacturer_data":[payload base64EncodedStringWithOptions:0]}]);
    XCTAssertEqual([HABLEIdentityEvidence tokensForRawAdvertisement:[NSData dataWithBytes:raw length:4]].count,0u);
}
- (void)testKnownUUIDCanBeRecognizedInsideAnOpaquePayload {
    uint8_t bytes[]={0xab,0xcd,0x00,0x00,0x12,0x34,0x00,0x00,0x10,0x00,0x80,0x00,0x00,0x80,0x5f,0x9b,0x34,0xfb,0xef};
    NSDictionary *o=@{@"manufacturer_data":[[NSData dataWithBytes:bytes length:sizeof(bytes)] base64EncodedStringWithOptions:0]};
    XCTAssertTrue(([HABLEIdentityEvidence observation:o containsUUID:@"1234"]));
    XCTAssertFalse(([HABLEIdentityEvidence observation:o containsUUID:@"9999"]));
}
- (void)testEmbeddedAddressNeedsNoVendorLookup {
    uint8_t bytes[]={0xde,0xad,0x00,0x11,0x22,0x33,0x44,0x55,0xbe,0xef};
    NSDictionary *observation=@{@"manufacturer_data":[[NSData dataWithBytes:bytes length:sizeof(bytes)] base64EncodedStringWithOptions:0]};
    XCTAssertTrue(([HABLEIdentityEvidence observation:observation containsAddress:@"00:11:22:33:44:55"]));
    XCTAssertFalse(([HABLEIdentityEvidence observation:observation containsAddress:@"00:11:22:33:44:66"]));
    XCTAssertTrue(([HABLEIdentityEvidence observation:@{@"system_id":@"001122FFFE334455"} containsAddress:@"00:11:22:33:44:55"]));
}
- (HABLEIdentityResolver *)resolver {
    HABLEIdentityResolver *r=[HABLEIdentityResolver new];
    [r loadRegistry:@[@{@"id":@"sensor",@"name":@"Room climate",@"serial_number":@"SN-901827",@"connections":@[@[@"bluetooth",@"00:11:22:33:44:55"]],@"identifiers":@[@[@"arbitrary_integration",@"UNIT-901827"]]}] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    return r;
}
- (void)testAddressCorroborationAllowsExtensionsButRejectsChangedPrefixesAndConflicts {
    uint8_t bytes[]={0x34,0x12,0,0x11,0x22,0x33,0x44,0x55,0x99,0xaa};
    NSData *base=[NSData dataWithBytes:bytes length:sizeof(bytes)];NSMutableData *extended=[base mutableCopy];[extended appendData:[@"extension" dataUsingEncoding:NSUTF8StringEncoding]];
    NSArray *shortTokens=[HABLEIdentityEvidence tokensForObservation:@{@"manufacturer_data":[base base64EncodedStringWithOptions:0]}];
    NSArray *longTokens=[HABLEIdentityEvidence tokensForObservation:@{@"manufacturer_data":[extended base64EncodedStringWithOptions:0]}];
    XCTAssertTrue(([HABLEIdentityEvidence tokens:longTokens corroborateAddress:@"00:11:22:33:44:55" withTokens:shortTokens]));
    XCTAssertTrue(([HABLEIdentityEvidence tokens:shortTokens corroborateAddress:@"00:11:22:33:44:55" withTokens:longTokens]));
    XCTAssertFalse(([HABLEIdentityEvidence tokens:longTokens corroborateAddress:@"00:11:22:33:44:66" withTokens:shortTokens]));
    ((uint8_t *)extended.mutableBytes)[9]^=1;
    NSArray *changed=[HABLEIdentityEvidence tokensForObservation:@{@"manufacturer_data":[extended base64EncodedStringWithOptions:0]}];
    XCTAssertFalse(([HABLEIdentityEvidence tokens:changed corroborateAddress:@"00:11:22:33:44:55" withTokens:shortTokens]));
    XCTAssertFalse(([HABLEIdentityEvidence tokens:[longTokens arrayByAddingObject:@"s:1234:4:AQIDBA=="] corroborateAddress:@"00:11:22:33:44:55" withTokens:[shortTokens arrayByAddingObject:@"s:1234:4:BQYHCA=="]]));
}
- (void)testObservedAddressCanMatchWithoutAnyHADeviceRegistration {
    HABLEIdentityResolver *r=[HABLEIdentityResolver new];
    [r loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    NSDictionary *ad=@{@"address":@"00:11:22:33:44:55",@"source":@"AA:BB:CC:DD:EE:FF",@"name":@"Unregistered appliance",@"service_uuids":@[@"1234"],@"time":@(NSDate.date.timeIntervalSince1970),@"raw":@"0bff341200112233445599aa"};
    [r observeAdvertisements:@[ad]];
    uint8_t bytes[]={0x34,0x12,0,0x11,0x22,0x33,0x44,0x55,0x99,0xaa};
    NSDictionary *o=@{@"identifier":@"local",@"name":@"Unregistered appliance",@"service_uuids":@[@"1234"],@"manufacturer_data":[[NSData dataWithBytes:bytes length:sizeof(bytes)] base64EncodedStringWithOptions:0]};
    NSDictionary *match=[r automaticMatchForObservation:o];
    XCTAssertEqualObjects(match[@"address"],@"00:11:22:33:44:55");
    XCTAssertEqualObjects(match[@"identity_kind"],@"observed_native");
    NSMutableDictionary *binding=[match mutableCopy];binding[@"schema"]=@2;binding[@"proof_id"]=@"observed-proof";
    HABLEIdentityResolver *peer=[HABLEIdentityResolver new];[peer loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:02"];
    [peer loadCatalog:@{@"schema":@2,@"bindings":@{@"00:11:22:33:44:55":binding}}];
    XCTAssertEqualObjects(([peer automaticMatchForObservation:o][@"address"]),@"00:11:22:33:44:55");
    bytes[9]=0xbb;NSMutableDictionary *different=[o mutableCopy];different[@"manufacturer_data"]=[[NSData dataWithBytes:bytes length:sizeof(bytes)] base64EncodedStringWithOptions:0];
    XCTAssertNil([peer automaticMatchForObservation:different]);
    // Once this Apple peripheral is verified, a different packet layout must
    // not revoke its binding. A new peer still needs the corroboration above.
    [peer setValue:[@{@"local":binding} mutableCopy] forKey:@"localBindings"];
    different[@"manufacturer_data"]=[[@"another packet layout" dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    XCTAssertEqualObjects(([peer automaticMatchForObservation:different][@"address"]),@"00:11:22:33:44:55");
    NSMutableDictionary *localTwin=[o mutableCopy];localTwin[@"identifier"]=@"other-local";localTwin[@"last_seen"]=@(NSDate.date.timeIntervalSince1970);
    NSMutableData *extended=[NSMutableData dataWithBytes:bytes length:sizeof(bytes)];((uint8_t *)extended.mutableBytes)[9]=0xaa;[extended appendData:[@"extra" dataUsingEncoding:NSUTF8StringEncoding]];
    localTwin[@"manufacturer_data"]=[extended base64EncodedStringWithOptions:0];[r recordObservation:localTwin identifier:@"other-local"];
    XCTAssertNil([r automaticMatchForObservation:o]);[r removeIdentifier:@"other-local"];
    NSMutableDictionary *second=[ad mutableCopy];second[@"address"]=@"00:11:22:33:44:66";[r observeAdvertisements:@[second]];
    XCTAssertNil([r automaticMatchForObservation:o]);
    XCTAssertTrue(([[r evidenceForIdentifier:@"local"] hasPrefix:@"Ambiguous:"]));
}
- (void)testSerialIdentityDoesNotDependOnManufacturer {
    HABLEIdentityResolver *r=[self resolver];NSDictionary *m=[r automaticMatchForObservation:@{@"identifier":@"local",@"name":@"Anything",@"serial_number":@"SN-901827"}];
    XCTAssertEqualObjects(m[@"address"],@"00:11:22:33:44:55");
}
- (void)testDuplicateStandardIdentifiersReportExplicitAmbiguity {
    HABLEIdentityResolver *r=[HABLEIdentityResolver new];
    [r loadRegistry:@[
        @{@"id":@"one",@"serial_number":@"SN-901827",@"connections":@[@[@"bluetooth",@"00:11:22:33:44:55"]]},
        @{@"id":@"two",@"serial_number":@"SN-901827",@"connections":@[@[@"bluetooth",@"00:11:22:33:44:66"]]}
    ] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    XCTAssertNil(([r automaticMatchForObservation:@{@"identifier":@"local",@"serial_number":@"SN-901827"}]));
    XCTAssertTrue(([[r evidenceForIdentifier:@"local"] hasPrefix:@"Ambiguous:"]));
}
- (void)testGenericSharedRecordRequiresCurrentRegistryAndProofSchema {
    HABLEIdentityResolver *r=[self resolver];NSDictionary *binding=@{@"schema":@2,@"address":@"00:11:22:33:44:55",@"device_id":@"sensor",@"method":@"serial",@"unit_identifier":@"SN-901827",@"proof_id":@"proof-one",@"profile":@{},@"lineage":@[]};
    [r loadCatalog:@{@"schema":@2,@"bindings":@{@"00:11:22:33:44:55":binding}}];
    XCTAssertEqual([[r valueForKey:@"catalog"] count],1u);
    NSMutableDictionary *invalid=[binding mutableCopy];invalid[@"device_id"]=@"other-device";
    [r loadCatalog:@{@"schema":@2,@"bindings":@{@"00:11:22:33:44:55":invalid}}];XCTAssertEqual([[r valueForKey:@"catalog"] count],0u);
}
- (void)testCatalogReconciliationRepublishesMissingProofWithoutOverwritingConflicts {
    HABLEIdentityResolver *r=[self resolver];
    NSDictionary *binding=@{@"schema":@2,@"address":@"00:11:22:33:44:55",@"device_id":@"sensor",@"method":@"serial",@"unit_identifier":@"SN-901827",@"proof_id":@"proof-one",@"profile":@{},@"lineage":@[]};
    [r setValue:[@{@"local":binding} mutableCopy] forKey:@"localBindings"];
    [r loadCatalog:@{@"schema":@2,@"bindings":@{}}];
    XCTAssertEqualObjects(([r valueForKey:@"pendingPublications"][@"00:11:22:33:44:55"]),binding);
    [[r valueForKey:@"pendingPublications"] removeAllObjects];
    NSMutableDictionary *other=[binding mutableCopy];other[@"proof_id"]=@"different-proof";
    [r loadCatalog:@{@"schema":@2,@"bindings":@{@"00:11:22:33:44:55":other}}];
    XCTAssertEqual([[r valueForKey:@"pendingPublications"] count],0u);
    XCTAssertEqualObjects(([r valueForKey:@"catalog"][@"00:11:22:33:44:55"][@"proof_id"]),@"different-proof");
}
- (void)testDerivedPeerCannotFeedItsAncestor {
    HABLEIdentityResolver *r=[self resolver];NSDictionary *binding=@{@"schema":@2,@"address":@"00:11:22:33:44:55",@"device_id":@"sensor",@"method":@"serial",@"unit_identifier":@"SN-901827",@"proof_id":@"proof-one",@"profile":@{},@"lineage":@[]};
    [r loadCatalog:@{@"schema":@2,@"bindings":@{@"00:11:22:33:44:55":binding}}];
    NSDictionary *record=@{@"address":@"00:11:22:33:44:55",@"proof_id":@"proof-one",@"lineage":@[@"02:00:00:00:00:01"],@"time":@(NSDate.date.timeIntervalSince1970),@"tokens":@[@"m:ABEiMw=="]};
    [r observePeer:@{@"schema":@2,@"source":@"02:00:00:00:00:02",@"time":@(NSDate.date.timeIntervalSince1970),@"records":@[record]} source:@"02:00:00:00:00:02"];
    XCTAssertEqual([[r valueForKey:@"remoteInfo"] count],0u);
}
@end
