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
