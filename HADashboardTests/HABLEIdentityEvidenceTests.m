#import <XCTest/XCTest.h>
#import "HABLEIdentityEvidence.h"
#import "HABLEIdentityResolver.h"
#import "HAConnectionManager.h"

@interface HABLEIdentityResolver (GenericTests)
- (void)loadRegistry:(NSArray *)devices entries:(NSArray *)entries excludingSource:(NSString *)source;
- (void)observeAdvertisements:(NSArray *)advertisements;
- (void)loadCatalog:(id)value;
- (void)observePeer:(id)value source:(NSString *)source;
- (HAConnectionManager *)connection;
- (BOOL)sourceIsCurrent;
@end
@interface HABLEFakeIdentityConnection : NSObject
@property (nonatomic, getter=isConnected) BOOL connected;
@property (nonatomic) BOOL delayUser;
@property (nonatomic, copy) void (^pendingUser)(id,NSError *);
@property (nonatomic, strong) NSMutableArray *commands;
@property (nonatomic, strong) NSMutableArray *subscriptions;
@property (nonatomic, copy) void (^registryHandler)(NSDictionary *);
@end
@implementation HABLEFakeIdentityConnection
- (instancetype)init { if((self=[super init])){_connected=YES;_commands=NSMutableArray.array;_subscriptions=NSMutableArray.array;}return self; }
- (void)sendCommand:(NSDictionary *)command completion:(void (^)(id,NSError *))completion {
    [self.commands addObject:command];NSString *type=command[@"type"];
    if([type isEqual:@"auth/current_user"]){if(self.delayUser)self.pendingUser=completion;else completion(@{@"id":@"test-user"},nil);}
    else if([type isEqual:@"config_entries/get"])completion(@[@{@"entry_id":@"sensor-entry",@"domain":@"arbitrary_integration"}],nil);
    else if([type isEqual:@"config/device_registry/list"])completion(@[@{@"id":@"sensor",@"name":@"Room",@"connections":@[@[@"bluetooth",@"00:11:22:33:44:55"]],@"config_entries":@[@"sensor-entry"]}],nil);
    else if([type isEqual:@"manifest/list"])completion(@[@{@"domain":@"arbitrary_integration",@"bluetooth":@[@{@"local_name":@"Sample*",@"service_uuid":@"1234",@"connectable":@NO}]}],nil);
    else completion(@{@"value":NSNull.null},nil);
}
- (NSInteger)subscribeWithCommand:(NSDictionary *)command handler:(void (^)(NSDictionary *))handler { [self.subscriptions addObject:command[@"type"]];return self.subscriptions.count; }
- (NSInteger)subscribeToEventType:(NSString *)type handler:(void (^)(NSDictionary *))handler { self.registryHandler=handler;[self.subscriptions addObject:type];return self.subscriptions.count; }
- (void)unsubscribeFromEventWithId:(NSInteger)identifier {}
@end
@interface HABLETransportTestResolver : HABLEIdentityResolver
@property (nonatomic, strong) HABLEFakeIdentityConnection *fakeConnection;
@property (nonatomic) BOOL currentScope;
@end
@implementation HABLETransportTestResolver
- (HAConnectionManager *)connection { return (HAConnectionManager *)self.fakeConnection; }
- (BOOL)sourceIsCurrent { return self.currentScope; }
@end
@interface HABLEIdentityEvidenceTests : XCTestCase
@end
@implementation HABLEIdentityEvidenceTests
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
- (void)testSerialIdentityDoesNotDependOnManufacturer {
    HABLEIdentityResolver *r=[self resolver];NSDictionary *m=[r automaticMatchForObservation:@{@"identifier":@"local",@"name":@"Anything",@"serial_number":@"SN-901827"}];
    XCTAssertEqualObjects(m[@"address"],@"00:11:22:33:44:55");
}
- (void)testGenericSharedRecordRequiresCurrentRegistryAndProofSchema {
    HABLEIdentityResolver *r=[self resolver];NSDictionary *binding=@{@"schema":@2,@"address":@"00:11:22:33:44:55",@"device_id":@"sensor",@"method":@"serial",@"unit_identifier":@"SN-901827",@"proof_id":@"proof-one",@"profile":@{},@"lineage":@[]};
    [r loadCatalog:@{@"schema":@2,@"bindings":@{@"00:11:22:33:44:55":binding}}];
    XCTAssertEqual([[r valueForKey:@"catalog"] count],1u);
    NSMutableDictionary *invalid=[binding mutableCopy];invalid[@"device_id"]=@"other-device";
    [r loadCatalog:@{@"schema":@2,@"bindings":@{@"00:11:22:33:44:55":invalid}}];XCTAssertEqual([[r valueForKey:@"catalog"] count],0u);
}
- (void)testDerivedPeerCannotFeedItsAncestor {
    HABLEIdentityResolver *r=[self resolver];NSDictionary *binding=@{@"schema":@2,@"address":@"00:11:22:33:44:55",@"device_id":@"sensor",@"method":@"serial",@"unit_identifier":@"SN-901827",@"proof_id":@"proof-one",@"profile":@{},@"lineage":@[]};
    [r loadCatalog:@{@"schema":@2,@"bindings":@{@"00:11:22:33:44:55":binding}}];
    NSDictionary *record=@{@"address":@"00:11:22:33:44:55",@"proof_id":@"proof-one",@"lineage":@[@"02:00:00:00:00:01"],@"time":@(NSDate.date.timeIntervalSince1970),@"tokens":@[@"m:ABEiMw=="]};
    [r observePeer:@{@"schema":@2,@"source":@"02:00:00:00:00:02",@"time":@(NSDate.date.timeIntervalSince1970),@"records":@[record]} source:@"02:00:00:00:00:02"];
    XCTAssertEqual([[r valueForKey:@"remoteInfo"] count],0u);
}
@end
