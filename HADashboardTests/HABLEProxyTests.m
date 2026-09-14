#import <XCTest/XCTest.h>
#import "HABLEProto.h"
#import "HABLEProxyManager.h"
#import "HABLEProxyRegistration.h"
#import "HABLEAPIServer.h"
#import "HAAPIClient.h"
#import "HABLEIdentityResolver.h"
#import "HABLEIdentityEvidence.h"
#import <CoreBluetooth/CoreBluetooth.h>

@interface HABLEIdentityResolver (IdentityTestAccess)
- (void)loadRegistry:(NSArray *)devices entries:(NSArray *)entries excludingSource:(NSString *)source;
- (void)observeAdvertisements:(NSArray *)advertisements;
@end

@interface HAAPIClient (RetryTestAccess)
- (void)refreshAfterUnauthorized:(void (^)(NSString *, NSError *))completion;
@end
@interface HABLEProxyRegistration (PermissionTestAccess)
+ (BOOL)isAdministratorInfo:(id)value;
@end

static NSUInteger HABLERejectedRequestCount;
@interface HABLERejectingHTTPProtocol : NSURLProtocol
@end
@implementation HABLERejectingHTTPProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"ble-auth-test.invalid"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSUInteger count; @synchronized([HABLERejectingHTTPProtocol class]) { count = ++HABLERejectedRequestCount; }
    // Bound the fixture itself so the old infinite retry loop fails promptly.
    NSInteger status = count <= 2 ? 401 : 429;
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

@interface HABLERefreshingAPIClient : HAAPIClient
@property NSUInteger refreshCount;
@end
@implementation HABLERefreshingAPIClient
- (void)refreshAfterUnauthorized:(void (^)(NSString *, NSError *))completion {
    self.refreshCount++; completion(@"replacement-test-token", nil);
}
@end

@interface HABLEProxyManager (ProtocolTestAccess)
- (void)updateAutomaticRegistrationWithIntegrationEnabled:(BOOL)enabled connected:(BOOL)connected context:(NSString *)context;
- (void)registerWithHomeAssistantAutomatically:(BOOL)automatic;
- (BOOL)matchIdentifier:(NSString *)identifier;
- (void)finishOperation:(id)session error:(NSUInteger)error;
- (void)discoveryPartDone:(id)session;
- (NSTimeInterval)identityProbeIntervalForObservation:(NSDictionary *)observation;
- (void)probePendingIdentity;
- (void)finishIdentity:(id)session error:(NSString *)message;
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error;
- (void)updateIdentityResolution;
- (void)flushIdentityAdvertisements;
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisement RSSI:(NSNumber *)RSSI;
- (BOOL)forwardRepeatedAdvertisementForIdentifier:(NSString *)identifier previous:(NSMutableDictionary *)previous name:(NSString *)name connectable:(BOOL)connectable manufacturer:(NSData *)manufacturer advertisedServices:(NSArray *)advertisedServices services:(NSDictionary *)services rssi:(NSNumber *)RSSI nowEpoch:(NSTimeInterval)nowEpoch;
- (void)deviceRequest:(NSDictionary *)fields connection:(HABLEAPIConnection *)connection;
- (void)bleServer:(HABLEAPIServer *)server receivedType:(NSUInteger)type data:(NSData *)data connection:(HABLEAPIConnection *)connection;
@end

@interface HABLEDiscoveryPolicyProxy : HABLEProxyManager
@end
@implementation HABLEDiscoveryPolicyProxy
- (void)updateIdentityResolution {} // The test controls when HA evidence arrives.
@end
@interface HABLEObservedPeripheral : NSObject
@property (nonatomic, strong) NSUUID *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray *services;
@end
@implementation HABLEObservedPeripheral
@end

@interface HABLEFingerprintPolicyProxy : HABLEProxyManager
@property NSUInteger pumps;
@end
@implementation HABLEFingerprintPolicyProxy
- (void)pump:(id)session { self.pumps++; }
@end

@interface HABLEFailingProbeProxy : HABLEProxyManager
@property NSUInteger inspections;
@property NSString *inspectedIdentifier;
@end
@implementation HABLEFailingProbeProxy
- (void)inspectIdentifier:(NSString *)identifier completion:(void (^)(NSDictionary *,NSError *))completion {self.inspections++;self.inspectedIdentifier=identifier;completion(nil,[NSError errorWithDomain:@"test" code:1 userInfo:nil]);}
@end
@interface HABLEProbeHintResolver : HABLEIdentityResolver
@end
@implementation HABLEProbeHintResolver
- (BOOL)hasFingerprintProbeReferenceForObservation:(NSDictionary *)observation {return [observation[@"reference_available"] boolValue];}
@end
@interface HABLEExistingMatchResolver : HABLEIdentityResolver
@end
@implementation HABLEExistingMatchResolver
- (NSDictionary *)automaticMatchForObservation:(NSDictionary *)observation {return @{@"automatic_match":@YES,@"method":@"passive_signature"};}
@end
@interface HABLERegistrationPolicyProxy : HABLEProxyManager
@property NSUInteger registrationAttempts;
@end
@implementation HABLERegistrationPolicyProxy
- (void)registerWithHomeAssistantAutomatically:(BOOL)automatic {
    XCTAssertTrue(automatic);
    self.registrationAttempts++;
    [self setValue:@(CFAbsoluteTimeGetCurrent() + 60) forKey:@"nextRegistrationAttempt"];
}
@end

@interface HABLECancellableRegistration : HABLEProxyRegistration
@property NSUInteger cancellations;
@end
@implementation HABLECancellableRegistration
- (void)cancel { self.cancellations++; [super cancel]; }
@end

@interface HABLECountingResolver : HABLEIdentityResolver
@property NSUInteger classifications;
@end
@implementation HABLECountingResolver
- (BOOL)hasKnownIdentityForObservation:(NSDictionary *)observation { self.classifications++; return YES; }
@end
@interface HABLECapturingServer : HABLEAPIServer
@property (nonatomic) NSUInteger responseType;
@property (nonatomic, strong) NSData *responseData;
@property (nonatomic, strong) HABLEAPIConnection *recipient;
@property (nonatomic, strong) NSMutableArray<NSData *> *capturedAdvertisements;
@end
@implementation HABLECapturingServer
- (BOOL)broadcastAdvertisement:(NSData *)data {
    if (!self.capturedAdvertisements) self.capturedAdvertisements = [NSMutableArray array];
    [self.capturedAdvertisements addObject:[data copy]]; return YES;
}
- (void)sendType:(NSUInteger)type data:(NSData *)data to:(HABLEAPIConnection *)connection {
    self.responseType = type; self.responseData = data; self.recipient = connection;
}
@end

@interface HABLEFastPathCountingProxy : HABLEDiscoveryPolicyProxy
@property NSUInteger fastHits;
@end
@implementation HABLEFastPathCountingProxy
- (BOOL)forwardRepeatedAdvertisementForIdentifier:(NSString *)identifier previous:(NSMutableDictionary *)previous name:(NSString *)name connectable:(BOOL)connectable manufacturer:(NSData *)manufacturer advertisedServices:(NSArray *)advertisedServices services:(NSDictionary *)services rssi:(NSNumber *)RSSI nowEpoch:(NSTimeInterval)nowEpoch {
    BOOL hit = [super forwardRepeatedAdvertisementForIdentifier:identifier previous:previous name:name connectable:connectable manufacturer:manufacturer advertisedServices:advertisedServices services:services rssi:RSSI nowEpoch:nowEpoch];
    if (hit) self.fastHits++;
    return hit;
}
@end
static NSDictionary *HABLEFieldsExceptRssi(NSData *packet) {
    NSMutableDictionary *fields = [HABLEDecode(packet) mutableCopy];
    [fields removeObjectForKey:@3];
    return fields;
}
@interface HABLEProxyTests : XCTestCase
@end
@implementation HABLEProxyTests
- (void)testFailedFingerprintReadPreservesRemainingReads {
    HABLEFingerprintPolicyProxy *manager=[HABLEFingerprintPolicyProxy new];id session=[NSClassFromString(@"HABLEPeripheralSession") new];
    [session setValue:@{@"type":@73,@"fields":@{@2:@[@1]}} forKey:@"pending"];
    [session setValue:[@[@{@"type":@73}] mutableCopy] forKey:@"operations"];
    [session setValue:[@{@1:@"path"} mutableCopy] forKey:@"identityReadPaths"];
    [session setValue:NSMutableDictionary.dictionary forKey:@"identityValues"];
    [session setValue:[^(NSDictionary *v,NSError *e){} copy] forKey:@"identityCompletion"];
    [manager finishOperation:session error:14];
    XCTAssertNil([session valueForKey:@"pending"]);XCTAssertEqual(manager.pumps,1u);
    XCTAssertEqual([[session valueForKey:@"operations"] count],1u);
    XCTAssertEqualObjects(([session valueForKey:@"identityValues"][@"gatt_read_errors"][@"path"]),@14);
}
- (void)testExistingMatchDoesNotDiscardRemainingIdentityReads {
    HABLEFingerprintPolicyProxy *proxy=[HABLEFingerprintPolicyProxy new];[proxy setValue:@YES forKey:@"identitiesReady"];[proxy setValue:[HABLEExistingMatchResolver new] forKey:@"identityResolver"];
    HABLEObservedPeripheral *peripheral=[HABLEObservedPeripheral new];peripheral.identifier=NSUUID.UUID;
    CBMutableCharacteristic *serial=[[CBMutableCharacteristic alloc] initWithType:[CBUUID UUIDWithString:@"2A25"] properties:CBCharacteristicPropertyRead value:[@"Unit123456" dataUsingEncoding:NSUTF8StringEncoding] permissions:CBAttributePermissionsReadable];
    id session=[NSClassFromString(@"HABLEPeripheralSession") new];[session setValue:peripheral forKey:@"peripheral"];[session setValue:@1 forKey:@"address"];
    [session setValue:[@{@1:serial} mutableCopy] forKey:@"handles"];[session setValue:@{@"type":@73,@"fields":@{@2:@[@1]}} forKey:@"pending"];
    [session setValue:[@[@{@"type":@73,@"fields":@{@2:@[@2]}}] mutableCopy] forKey:@"operations"];
    [session setValue:[@{@1:@"serial_number"} mutableCopy] forKey:@"identityFields"];[session setValue:[@{@1:@"s/180A/c/2A25"} mutableCopy] forKey:@"identityReadPaths"];
    [session setValue:NSMutableDictionary.dictionary forKey:@"identityValues"];[session setValue:[^(NSDictionary *v,NSError *e){} copy] forKey:@"identityCompletion"];
    [proxy valueForKey:@"sessions"][@1]=session;
    [proxy peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:serial error:nil];
    XCTAssertEqual([[session valueForKey:@"operations"] count],1u,@"Manufacturer/model context and later contradictions must still be collected");
    XCTAssertEqualObjects([session valueForKey:@"identityValues"][@"serial_number"],@"Unit123456");XCTAssertEqual(proxy.pumps,1u);
}
- (void)testFingerprintVerificationRevisitIsBounded {
    HABLEProxyManager *manager=[HABLEProxyManager new];
    NSDictionary *fingerprints=@{@"path":@{@"sessions":@1}};
    XCTAssertEqual(([manager identityProbeIntervalForObservation:@{@"gatt_fingerprints":fingerprints,@"gatt_probe_attempts":@1}]),60);
    XCTAssertEqual(([manager identityProbeIntervalForObservation:@{@"gatt_fingerprints":fingerprints,@"gatt_probe_attempts":@2}]),3600);
}
- (void)testFailedVerificationDoesNotRetryEveryMinuteForever {
    HABLEFailingProbeProxy *manager=[HABLEFailingProbeProxy new];NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    [manager setValue:@YES forKey:@"identitiesReady"];[manager setValue:[HABLECountingResolver new] forKey:@"identityResolver"];
    NSDictionary *observation=@{@"identifier":@"failed-probe",@"connectable":@YES,@"last_seen":@(now),@"first_seen":@(now-120),@"rssi":@(-50),@"gatt_probe_attempts":@1,@"gatt_fingerprints":@{@"path":@{@"sessions":@1}}};
    [manager setValue:[@{@"failed-probe":observation} mutableCopy] forKey:@"observations"];
    for(NSUInteger i=0;i<3;i++) {
        [manager setValue:@0 forKey:@"nextIdentityProbeAt"];
        [manager valueForKey:@"identityProbeTimes"][@"failed-probe"]=@(now-61);
        [manager probePendingIdentity];
    }
    XCTAssertEqual(manager.inspections,2u);
}
- (void)testRecentManualReadAndCachedWeakProbeAreNotRepeatedAfterRestart {
    HABLEFailingProbeProxy *manager=[HABLEFailingProbeProxy new];NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    [manager setValue:@YES forKey:@"identitiesReady"];[manager setValue:[HABLECountingResolver new] forKey:@"identityResolver"];
    NSMutableDictionary *observation=[@{@"identifier":@"recent",@"connectable":@YES,@"last_seen":@(now),@"first_seen":@(now-120),@"rssi":@(-50),@"identification_read_at":@(now),@"gatt_probe_attempts":@1,@"gatt_fingerprints":@{@"path":@{@"sessions":@1}}} mutableCopy];
    [manager setValue:[@{@"recent":observation} mutableCopy] forKey:@"observations"];
    [manager probePendingIdentity];XCTAssertEqual(manager.inspections,0u);
    observation[@"identification_read_at"]=@(now-120);observation[@"gatt_probe_attempts"]=@2;
    [manager probePendingIdentity];XCTAssertEqual(manager.inspections,0u);
    observation[@"gatt_fingerprints"]=@{@"path":@{@"sessions":@2,@"kind":@"json_scalar"}};
    [manager probePendingIdentity];XCTAssertEqual(manager.inspections,1u,@"Old structured data needs one bounded format-aware refresh");
}
- (void)testFingerprintDiscoveryOnlyQueuesBoundedReadableCharacteristics {
    HABLEFingerprintPolicyProxy *manager=[HABLEFingerprintPolicyProxy new];id session=[NSClassFromString(@"HABLEPeripheralSession") new];
    HABLEObservedPeripheral *peripheral=[HABLEObservedPeripheral new];peripheral.identifier=NSUUID.UUID;
    CBMutableService *service=[[CBMutableService alloc] initWithType:[CBUUID UUIDWithString:@"1234"] primary:YES];NSMutableArray *chars=NSMutableArray.array;
    for(NSUInteger i=0;i<20;i++)[chars addObject:[[CBMutableCharacteristic alloc] initWithType:[CBUUID UUIDWithString:[NSString stringWithFormat:@"%04X",(unsigned)(0xC300+i)]] properties:CBCharacteristicPropertyRead value:nil permissions:CBAttributePermissionsReadable]];
    [chars addObject:[[CBMutableCharacteristic alloc] initWithType:[CBUUID UUIDWithString:@"A100"] properties:CBCharacteristicPropertyWrite value:nil permissions:CBAttributePermissionsWriteable]];
    service.characteristics=chars;peripheral.services=@[service];
    [session setValue:peripheral forKey:@"peripheral"];[session setValue:@1 forKey:@"address"];[session setValue:@1 forKey:@"discoveryWork"];[session setValue:@1 forKey:@"nextHandle"];[session setValue:@YES forKey:@"preparingConnection"];
    for(NSString *key in @[@"handles",@"handleIDs",@"identityValues",@"identityFields",@"identityReadPaths"])[session setValue:NSMutableDictionary.dictionary forKey:key];
    [session setValue:NSMutableArray.array forKey:@"operations"];[session setValue:[^(NSDictionary *v,NSError *e){} copy] forKey:@"identityCompletion"];
    id saved=[NSUserDefaults.standardUserDefaults objectForKey:@"ha_ble_proxy_handle_tables"];
    [manager discoveryPartDone:session];
    XCTAssertEqual([[session valueForKey:@"operations"] count],16u);
    XCTAssertEqualObjects(([session valueForKey:@"identityValues"][@"gatt_readable_characteristic_count"]),@20);
    XCTAssertEqualObjects(([session valueForKey:@"identityValues"][@"gatt_reads_truncated"]),@YES);
    for(NSDictionary *operation in [session valueForKey:@"operations"]) {
        XCTAssertEqualObjects(operation[@"type"],@73);
        CBCharacteristic *c=[session valueForKey:@"handles"][@(HABLEInteger(operation[@"fields"],2))];XCTAssertTrue((c.properties & CBCharacteristicPropertyRead)!=0);
    }
    if(saved)[NSUserDefaults.standardUserDefaults setObject:saved forKey:@"ha_ble_proxy_handle_tables"];else[NSUserDefaults.standardUserDefaults removeObjectForKey:@"ha_ble_proxy_handle_tables"];
}
- (void)testPartialIdentityReadsSurviveALaterSessionFailure {
    id saved=[NSUserDefaults.standardUserDefaults objectForKey:@"ha_ble_proxy_identity_metadata"];
    @try {
        HABLEProxyManager *proxy=[HABLEProxyManager new];HABLEObservedPeripheral *peripheral=[HABLEObservedPeripheral new];peripheral.identifier=NSUUID.UUID;
        NSString *identifier=peripheral.identifier.UUIDString;[proxy valueForKey:@"observations"][identifier]=NSMutableDictionary.dictionary;
        NSData *value=[@"{\"device\":{\"mac\":\"00:11:22:33:44:55\"}}" dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *reads=[HABLEIdentityEvidence fingerprintsForValue:value path:@"s/1234/c/5678"];
        for(NSUInteger i=0;i<2;i++) {
            id session=[NSClassFromString(@"HABLEPeripheralSession") new];[session setValue:peripheral forKey:@"peripheral"];
            [session setValue:[@{@"gatt_probe_session":[NSString stringWithFormat:@"partial-%lu",(unsigned long)i],@"gatt_fingerprint_reads":reads} mutableCopy] forKey:@"identityValues"];
            __block BOOL returned=NO;
            [session setValue:[^(NSDictionary *identity,NSError *error){returned=YES;XCTAssertNotNil(error);XCTAssertNotNil(identity);XCTAssertEqualObjects(identity[@"identification_complete"],@NO);} copy] forKey:@"identityCompletion"];
            [proxy finishIdentity:session error:@"A later operation timed out"];XCTAssertTrue(returned);
        }
        NSDictionary *fields=[proxy valueForKey:@"observations"][identifier][@"gatt_fingerprints"];
        NSDictionary *field=fields[@"s/1234/c/5678/json/device/mac"];
        XCTAssertEqualObjects(field[@"sessions"],@2);XCTAssertTrue([field[@"stable_across_sessions"] boolValue]);
        id empty=[NSClassFromString(@"HABLEPeripheralSession") new];[empty setValue:peripheral forKey:@"peripheral"];
        [empty setValue:[@{@"gatt_probe_session":@"empty-failure",@"gatt_fingerprint_reads":@{}} mutableCopy] forKey:@"identityValues"];
        [empty setValue:[^(NSDictionary *identity,NSError *error){XCTAssertNil(identity);XCTAssertNotNil(error);} copy] forKey:@"identityCompletion"];
        [proxy finishIdentity:empty error:@"Connection failed before any read"];
        XCTAssertEqualObjects([proxy valueForKey:@"observations"][identifier][@"gatt_fingerprints"],fields,@"An empty failed session cannot add stability evidence or erase prior reads");
    } @finally {if(saved)[NSUserDefaults.standardUserDefaults setObject:saved forKey:@"ha_ble_proxy_identity_metadata"];else[NSUserDefaults.standardUserDefaults removeObjectForKey:@"ha_ble_proxy_identity_metadata"];}
}
- (void)testStandaloneUnknownConnectableDeviceEntersTheBoundedProbeQueue {
    HABLEFailingProbeProxy *proxy=[HABLEFailingProbeProxy new];[proxy setValue:@YES forKey:@"identitiesReady"];
    HABLEIdentityResolver *resolver=[HABLEIdentityResolver new];[resolver loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];[proxy setValue:resolver forKey:@"identityResolver"];
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSMutableDictionary *observation=[@{@"identifier":@"unregistered-unit",@"name":@"Unregistered unit",@"connectable":@YES,@"first_seen":@(now-120),@"last_seen":@(now),@"rssi":@-50} mutableCopy];
    [proxy valueForKey:@"observations"][@"unregistered-unit"]=observation;
    XCTAssertFalse([resolver hasKnownIdentityForObservation:observation]);
    [proxy probePendingIdentity];XCTAssertEqual(proxy.inspections,1u);
    [proxy probePendingIdentity];XCTAssertEqual(proxy.inspections,1u,@"Discovery without a reference must still respect the cooldown");
    [proxy setValue:@0 forKey:@"nextIdentityProbeAt"];[proxy valueForKey:@"identityProbeTimes"][@"unregistered-unit"]=@(now-4000);observation[@"connectable"]=@NO;
    [proxy probePendingIdentity];XCTAssertEqual(proxy.inspections,1u);
}
- (void)testProbeQueuePrioritizesSharedFingerprintReferencesWithinExistingBudgets {
    HABLEFailingProbeProxy *proxy=[HABLEFailingProbeProxy new];[proxy setValue:@YES forKey:@"identitiesReady"];[proxy setValue:[HABLEProbeHintResolver new] forKey:@"identityResolver"];
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;NSMutableDictionary *rows=[proxy valueForKey:@"observations"];
    for(NSString *identifier in @[@"strong-unknown",@"weak-reference"])rows[identifier]=[@{@"identifier":identifier,@"connectable":@YES,@"first_seen":@(now-120),@"last_seen":@(now),@"rssi":[identifier isEqual:@"weak-reference"] ? @-96 : @-40,@"reference_available":@([identifier isEqual:@"weak-reference"])} mutableCopy];
    rows[@"weak-reference"][@"last_seen"]=@(now-45);
    [proxy probePendingIdentity];XCTAssertEqualObjects(proxy.inspectedIdentifier,@"weak-reference");
    XCTAssertEqualObjects([proxy valueForKey:@"lastIdentityProbe"][@"result"],@"failed");
    XCTAssertNotNil([proxy valueForKey:@"lastIdentityProbe"][@"error"]);
    NSDictionary *diagnostic=[[proxy devices] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"identifier == %@",@"weak-reference"]].firstObject;
    XCTAssertEqualObjects(diagnostic[@"identity_probe_attempts"],@1);XCTAssertGreaterThan([diagnostic[@"identity_probe_at"] doubleValue],now-1);
    [proxy probePendingIdentity];XCTAssertEqual(proxy.inspections,1u,@"A reference does not bypass the global cooldown");
    [proxy setValue:@0 forKey:@"nextIdentityProbeAt"];[proxy probePendingIdentity];
    XCTAssertEqualObjects(proxy.inspectedIdentifier,@"strong-unknown",@"Cooling-down references must not starve unknown standalone devices");
    XCTAssertEqual([[proxy valueForKey:@"automaticMappings"] count],0u,@"Probe scheduling is not an identity match");
    [proxy valueForKey:@"identityProbeTimes"][@"weak-reference"]=@0;[proxy setValue:@0 forKey:@"nextIdentityProbeAt"];rows[@"weak-reference"][@"last_seen"]=@(now-61);
    [proxy probePendingIdentity];XCTAssertEqual(proxy.inspections,2u,@"Even a referenced device must have been observed within one minute");
    rows[@"weak-reference"][@"last_seen"]=@(now-45);rows[@"weak-reference"][@"reference_available"]=@NO;
    [proxy probePendingIdentity];XCTAssertEqual(proxy.inspections,2u,@"The extended reception window does not apply to unknown devices");
}
- (void)testProvisionalMappingsRemainEligibleForBoundedIdentityProbes {
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    for(NSString *method in @[@"passive_signature",@"peer_passive_signature",@"gatt_fingerprint",@"confirmed"]) {
        HABLEFailingProbeProxy *proxy=[HABLEFailingProbeProxy new];[proxy setValue:@YES forKey:@"identitiesReady"];
        [proxy valueForKey:@"observations"][@"unit"]=[@{@"identifier":@"unit",@"connectable":@YES,@"first_seen":@(now-120),@"last_seen":@(now),@"rssi":@-50} mutableCopy];
        [proxy valueForKey:@"automaticMappings"][@"unit"]=@{@"method":method,@"address":@"02:11:22:33:44:55"};
        [proxy probePendingIdentity];BOOL provisional=[@[@"passive_signature",@"peer_passive_signature"] containsObject:method];
        XCTAssertEqual(proxy.inspections,provisional ? 1u : 0u);
        [proxy setValue:@0 forKey:@"nextIdentityProbeAt"];[proxy probePendingIdentity];XCTAssertEqual(proxy.inspections,provisional ? 1u : 0u,@"Provisional mappings must still obey the per-device retry budget");
    }
}
- (void)testSingleProxyForwardsStableAliasAfterBoundedLearningWithoutAReference {
    HABLEObservedPeripheral *peripheral=[HABLEObservedPeripheral new];peripheral.identifier=NSUUID.UUID;peripheral.name=@"Unit1234";
    NSDictionary *advertisement=@{CBAdvertisementDataLocalNameKey:@"Unit1234",CBAdvertisementDataManufacturerDataKey:[NSData dataWithBytes:"12345678" length:8]};
    uint64_t firstAddress=0;
    // Both a failed import and a loaded integration with no resolvable unit
    // reference must keep the transport usable. Recreating the manager models
    // a restart with the same persisted installation identity.
    for(NSNumber *ready in @[@NO,@YES]) {
        HABLEDiscoveryPolicyProxy *proxy=[HABLEDiscoveryPolicyProxy new];[proxy setValue:@YES forKey:@"running"];[proxy setValue:ready forKey:@"identitiesReady"];[proxy setValue:[HABLECountingResolver new] forKey:@"identityResolver"];
        HABLECapturingServer *server=[[HABLECapturingServer alloc] initWithName:@"test" address:@"02:00:00:00:00:01" key:[NSMutableData dataWithLength:32]];[proxy setValue:server forKey:@"server"];
        [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:advertisement RSSI:@-50];XCTAssertEqual(server.capturedAdvertisements.count,0u);
        NSString *identifier=peripheral.identifier.UUIDString;
        [proxy valueForKey:@"observations"][identifier][@"first_seen"]=@(NSDate.date.timeIntervalSince1970-61);
        [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:advertisement RSSI:@-50];
        XCTAssertEqual(server.capturedAdvertisements.count,2u);
        NSDictionary *packet=HABLEDecode(server.capturedAdvertisements.lastObject);uint64_t address=HABLEInteger(packet,1);XCTAssertNotEqual(address,0u);XCTAssertEqual(HABLEInteger(packet,7),1u);
        if(firstAddress)XCTAssertEqual(address,firstAddress);else firstAddress=address;
        XCTAssertNil([proxy valueForKey:@"observations"][identifier][@"identity_pending"]);XCTAssertEqual([[proxy valueForKey:@"automaticMappings"] count],0u);
        XCTAssertEqual([[proxy valueForKey:@"pendingIdentityAdvertisements"] count],0u);
    }
}
- (void)testSingleProxyAliasesSurvivePayloadChangesWithoutMergingIdenticalTwins {
    HABLEDiscoveryPolicyProxy *proxy=[HABLEDiscoveryPolicyProxy new];
    [proxy setValue:@YES forKey:@"running"];[proxy setValue:@YES forKey:@"identitiesReady"];
    HABLEIdentityResolver *resolver=[HABLEIdentityResolver new];
    [resolver loadRegistry:@[] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    [proxy setValue:resolver forKey:@"identityResolver"];
    HABLECapturingServer *server=[[HABLECapturingServer alloc] initWithName:@"test" address:@"02:00:00:00:00:01" key:[NSMutableData dataWithLength:32]];
    [proxy setValue:server forKey:@"server"];
    NSMutableArray *peripherals=NSMutableArray.array;NSMutableArray *addresses=NSMutableArray.array;
    for(NSUInteger unit=0;unit<2;unit++) {
        HABLEObservedPeripheral *peripheral=[HABLEObservedPeripheral new];peripheral.identifier=NSUUID.UUID;peripheral.name=@"Unit1234";[peripherals addObject:peripheral];
        for(NSUInteger sample=0;sample<3;sample++) {
            uint8_t bytes[]={0x34,0x12,1,2,3,4,5,(uint8_t)sample};
            NSDictionary *ad=@{CBAdvertisementDataLocalNameKey:@"Unit1234",CBAdvertisementDataManufacturerDataKey:[NSData dataWithBytes:bytes length:sizeof(bytes)]};
            [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-50];
            [proxy valueForKey:@"observations"][peripheral.identifier.UUIDString][@"first_seen"]=@(NSDate.date.timeIntervalSince1970-61);
            [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-50];
            uint64_t address=HABLEInteger(HABLEDecode(server.capturedAdvertisements.lastObject),1);
            if(sample==0)[addresses addObject:@(address)];else XCTAssertEqual(address,[addresses[unit] unsignedLongLongValue],@"Changing measurements must not change a standalone local alias");
        }
    }
    XCTAssertNotEqualObjects(addresses[0],addresses[1],@"Identical names and advertisements cannot collapse two peripherals on a sole receiver");
    XCTAssertEqual([[proxy valueForKey:@"automaticMappings"] count],0u);
}
- (void)testDiscoveryBurstDoesNotRescanThePendingRegistryBeforeImport {
    HABLEDiscoveryPolicyProxy *proxy=[HABLEDiscoveryPolicyProxy new];HABLECountingResolver *resolver=[HABLECountingResolver new];
    [proxy setValue:resolver forKey:@"identityResolver"];[proxy setValue:@YES forKey:@"running"];
    uint8_t bytes[]={1,2,3,4};NSDictionary *ad=@{CBAdvertisementDataLocalNameKey:@"opaque",CBAdvertisementDataManufacturerDataKey:[NSData dataWithBytes:bytes length:4]};
    for(NSUInteger i=0;i<200;i++) {
        HABLEObservedPeripheral *peripheral=[HABLEObservedPeripheral new];peripheral.identifier=NSUUID.UUID;peripheral.name=@"opaque";
        [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-50];
    }
    [proxy flushIdentityAdvertisements];
    XCTAssertEqual(resolver.classifications,0u,@"Pending import must not perform registry scans for every buffered packet");
}

- (void)testRemovingManualAssociationCannotPromoteAFriendlyNameIntoAnAddressMatch {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id saved = [defaults objectForKey:@"ha_ble_proxy_address_mapping"];
    HABLEIdentityResolver *resolver = [[HABLEIdentityResolver alloc] init];
    [resolver loadRegistry:@[@{@"id":@"meter", @"name":@"Generic meter", @"name_by_user":@"Bedroom", @"connections":@[@[@"bluetooth", @"00:11:22:33:44:55"]]}] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    HABLEProxyManager *proxy = [[HABLEProxyManager alloc] init];
    [proxy setValue:resolver forKey:@"identityResolver"]; [proxy setValue:@YES forKey:@"identitiesReady"];
    NSMutableDictionary *observation = [@{@"name":@"Generic meter", @"identity":@"user_associated_mac", @"address":@"00:11:22:33:44:55"} mutableCopy];
    [proxy setValue:[@{@"local-id":observation} mutableCopy] forKey:@"observations"];
    [proxy setValue:[@{@"local-id":@"00:11:22:33:44:55"} mutableCopy] forKey:@"mappings"];
    [proxy matchIdentifier:@"local-id"]; XCTAssertEqualObjects(observation[@"ha_name"], @"Bedroom");
    XCTAssertTrue([proxy setRealAddress:@"" forIdentifier:@"local-id" error:nil]);
    [proxy matchIdentifier:@"local-id"];
    XCTAssertNotEqualObjects(observation[@"address"], @"00:11:22:33:44:55");
    XCTAssertEqualObjects(observation[@"identity"], @"local_alias");
    if (saved) [defaults setObject:saved forKey:@"ha_ble_proxy_address_mapping"]; else [defaults removeObjectForKey:@"ha_ble_proxy_address_mapping"];
}
- (void)testOriginalLocalAliasSurvivesCanonicalAddressRewriting {
    HABLEDiscoveryPolicyProxy *proxy=[HABLEDiscoveryPolicyProxy new];[proxy setValue:@YES forKey:@"running"];
    HABLEObservedPeripheral *peripheral=[HABLEObservedPeripheral new];peripheral.identifier=NSUUID.UUID;peripheral.name=@"Unit";
    NSDictionary *ad=@{CBAdvertisementDataLocalNameKey:@"Unit"};
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@(-50)];
    NSString *local=[proxy valueForKey:@"observations"][peripheral.identifier.UUIDString][@"local_address"];
    XCTAssertEqual(local.length,17u);
    [proxy valueForKey:@"mappings"][peripheral.identifier.UUIDString]=@"00:11:22:33:44:55";
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@(-50)];
    NSDictionary *current=[proxy valueForKey:@"observations"][peripheral.identifier.UUIDString];
    XCTAssertEqualObjects(current[@"address"],@"00:11:22:33:44:55");XCTAssertEqualObjects(current[@"local_address"],local);XCTAssertNotEqualObjects(current[@"address"],local);
}
- (void)testPublishedAddressesKeepTheirIdentityAndUseHAFriendlyNames {
    HABLEIdentityResolver *resolver = [[HABLEIdentityResolver alloc] init];
    [resolver loadRegistry:@[@{@"id":@"meter", @"name":@"Raw meter name", @"name_by_user":@"Bedroom climate", @"connections":@[@[@"bluetooth", @"00:11:22:33:44:55"]]}] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    HABLEProxyManager *proxy = [[HABLEProxyManager alloc] init];
    [proxy setValue:resolver forKey:@"identityResolver"]; [proxy setValue:@YES forKey:@"identitiesReady"];
    NSMutableDictionary *observation = [@{@"name":@"Raw meter name", @"identity":@"user_associated_mac", @"address":@"00:11:22:33:44:55"} mutableCopy];
    [proxy setValue:[@{@"local-id":observation} mutableCopy] forKey:@"observations"];
    [proxy setValue:[@{@"local-id":@"00:11:22:33:44:55"} mutableCopy] forKey:@"mappings"];
    [proxy matchIdentifier:@"local-id"];
    XCTAssertEqualObjects(observation[@"ha_name"], @"Bedroom climate");
    XCTAssertEqualObjects(observation[@"identity"], @"user_associated_mac");
    [observation removeObjectForKey:@"ha_name"];
    [proxy matchIdentifier:@"local-id"];
    XCTAssertEqualObjects(observation[@"ha_name"], @"Bedroom climate", @"Fresh advertisements retain the cached friendly name");
}
- (void)testGattSerialOnlyLinksAnUnambiguousRegisteredAddress {
    HABLEIdentityResolver *resolver = [[HABLEIdentityResolver alloc] init];
    NSDictionary *first = @{@"id":@"sensor-one", @"name":@"Room Sensor", @"serial_number":@"SN-123456", @"connections":@[@[@"bluetooth", @"00:11:22:33:44:55"]]};
    [resolver loadRegistry:@[first] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    NSDictionary *observation = @{@"identity":@"local_alias", @"serial_number":@"SN-123456", @"name":@"Room Sensor"};
    XCTAssertEqualObjects([resolver automaticMatchForObservation:observation][@"address"], @"00:11:22:33:44:55");
    NSMutableDictionary *second = [first mutableCopy]; second[@"id"] = @"sensor-two"; second[@"connections"] = @[@[@"bluetooth", @"00:11:22:33:44:66"]];
    [resolver loadRegistry:@[first, second] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    XCTAssertNil([resolver automaticMatchForObservation:observation], @"Duplicate serial numbers cannot identify one device");
}
- (void)testRegistrationFollowsIntegrationToggleAndWaitsForConnectivity {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id saved = [defaults objectForKey:@"ha_ble_proxy_auto_register"];
    [defaults removeObjectForKey:@"ha_ble_proxy_auto_register"];
    HABLERegistrationPolicyProxy *proxy = [[HABLERegistrationPolicyProxy alloc] init];
    [proxy setValue:@YES forKey:@"running"];
    [proxy updateAutomaticRegistrationWithIntegrationEnabled:NO connected:YES context:@"server-one"];
    [proxy updateAutomaticRegistrationWithIntegrationEnabled:YES connected:NO context:@"server-one"];
    XCTAssertEqual(proxy.registrationAttempts, 0u);
    [proxy updateAutomaticRegistrationWithIntegrationEnabled:YES connected:YES context:@"server-one"];
    XCTAssertEqual(proxy.registrationAttempts, 1u);
    [proxy updateAutomaticRegistrationWithIntegrationEnabled:YES connected:YES context:@"server-one"];
    XCTAssertEqual(proxy.registrationAttempts, 1u, @"Failures must respect the retry delay");
    [proxy setValue:@0 forKey:@"nextRegistrationAttempt"];
    [proxy setValue:@"server-one" forKey:@"registeredContext"];
    [proxy updateAutomaticRegistrationWithIntegrationEnabled:YES connected:YES context:@"server-one"];
    XCTAssertEqual(proxy.registrationAttempts, 1u, @"Successful setup must not repeat every tick");
    [proxy updateAutomaticRegistrationWithIntegrationEnabled:YES connected:YES context:@"server-two"];
    XCTAssertEqual(proxy.registrationAttempts, 2u, @"A different account or proxy address needs setup");
    if (saved) [defaults setObject:saved forKey:@"ha_ble_proxy_auto_register"];
}
- (void)testTurningIntegrationOffCancelsAutomaticButNotManualSetup {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id saved = [defaults objectForKey:@"ha_ble_proxy_auto_register"];
    [defaults removeObjectForKey:@"ha_ble_proxy_auto_register"];
    HABLERegistrationPolicyProxy *proxy = [[HABLERegistrationPolicyProxy alloc] init];
    HABLECancellableRegistration *registration = [[HABLECancellableRegistration alloc] init];
    [proxy setValue:registration forKey:@"registration"];
    [proxy setValue:@YES forKey:@"integrationRegistrationWasEnabled"];
    [proxy setValue:@YES forKey:@"automaticRegistrationInFlight"];
    [proxy updateAutomaticRegistrationWithIntegrationEnabled:NO connected:YES context:@"server"];
    XCTAssertEqual(registration.cancellations, 1u);
    [proxy updateAutomaticRegistrationWithIntegrationEnabled:NO connected:YES context:@"server"];
    XCTAssertEqual(registration.cancellations, 1u, @"Manual setup must stay independent of the integration toggle");
    if (saved) [defaults setObject:saved forKey:@"ha_ble_proxy_auto_register"];
}
- (void)checkRejectedRequestWithTextResponse:(BOOL)text {
    HABLERejectedRequestCount = 0;
    [NSURLProtocol registerClass:[HABLERejectingHTTPProtocol class]];
    HABLERefreshingAPIClient *client = [[HABLERefreshingAPIClient alloc] initWithBaseURL:[NSURL URLWithString:@"https://ble-auth-test.invalid/api/"] token:@"original-test-token" requestTimeoutInterval:1 resourceTimeoutInterval:2];
    [[client valueForKey:@"session"] invalidateAndCancel];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.protocolClasses = @[[HABLERejectingHTTPProtocol class]];
    [client setValue:[NSURLSession sessionWithConfiguration:configuration] forKey:@"session"];
    XCTestExpectation *done = [self expectationWithDescription:@"Unauthorized request completes after one retry"];
    HAAPIResponseBlock completion = ^(id result, NSError *error) {
        XCTAssertNil(result); XCTAssertEqual(error.code, (NSInteger)401); [done fulfill];
    };
    if (text) [client renderTemplate:@"{{ 1 }}" completion:completion];
    else [client postJSONAtPath:@"probe" body:@{} completion:completion];
    [self waitForExpectationsWithTimeout:3 handler:nil];
    XCTAssertEqual(HABLERejectedRequestCount, (NSUInteger)2);
    XCTAssertEqual(client.refreshCount, (NSUInteger)1);
    [client cancelAllRequests]; [NSURLProtocol unregisterClass:[HABLERejectingHTTPProtocol class]];
}
- (void)testJSONAuthenticationRetryIsBounded { [self checkRejectedRequestWithTextResponse:NO]; }
- (void)testTemplateAuthenticationRetryIsBounded { [self checkRejectedRequestWithTextResponse:YES]; }
- (void)testAutomaticSetupRequiresAnAdministrator {
    XCTAssertTrue([HABLEProxyRegistration isAdministratorInfo:@{@"is_admin":@YES}]);
    for (id value in @[@{@"is_admin":@NO}, @{@"is_admin":@"true"}, @{}, @[]]) XCTAssertFalse([HABLEProxyRegistration isAdministratorInfo:value]);
    XCTAssertFalse([HABLEProxyRegistration isAdministratorInfo:nil]);
}
- (void)testClientCanUnsubscribeFromAdvertisements {
    HABLEProxyManager *manager = [[HABLEProxyManager alloc] init];
    HABLEAPIConnection *client = [[HABLEAPIConnection alloc] init];
    [manager bleServer:nil receivedType:66 data:[NSData data] connection:client];
    XCTAssertTrue(client.advertisements);
    [manager bleServer:nil receivedType:87 data:[NSData data] connection:client];
    XCTAssertFalse(client.advertisements);
}
- (void)testServiceUUIDsAcceptHAFormatsAndRejectAddresses {
    NSString *expected = @"0000fcd2-0000-1000-8000-00805f9b34fb";
    for (NSString *value in @[@"FCD2", @"0xfcd2", @"0000FCD2", @"0000FCD200001000800000805F9B34FB", expected]) XCTAssertEqualObjects(HABLECanonicalUUID(value), expected);
    for (id value in @[@"AA:BB:CC:DD:EE:FF", @"not-a-uuid", @"0000fcd2/0000/1000/8000/00805f9b34fb", @123]) XCTAssertNil(HABLECanonicalUUID(value));
    XCTAssertNil(HABLECanonicalUUID(nil));
}
- (void)testServiceFiltersRejectPartialUpdatesAndReset {
    HABLEProxyManager *manager = [[HABLEProxyManager alloc] init]; [manager reset];
    XCTAssertTrue(([manager setAdditionalScanServiceUUIDs:@[@"FCD2", @"0000fcd2-0000-1000-8000-00805f9b34fb"] error:nil]));
    XCTAssertEqual(manager.additionalScanServiceUUIDs.count, (NSUInteger)1);
    NSArray *before = manager.additionalScanServiceUUIDs;
    XCTAssertFalse(([manager setAdditionalScanServiceUUIDs:@[@"FD3D", @"invalid"] error:nil]));
    XCTAssertEqualObjects(manager.additionalScanServiceUUIDs, before);
    manager.scanMode = HABLEScanModeServices;
    [manager reset];
    XCTAssertEqual(manager.scanMode, HABLEScanModeAutomatic);
    XCTAssertEqual(manager.scanServiceUUIDs.count, (NSUInteger)0);
}
- (void)testDisconnectOfUnknownDeviceAcknowledgesConnectionState {
    HABLEProxyManager *manager = [[HABLEProxyManager alloc] init];
    HABLECapturingServer *server = [[HABLECapturingServer alloc] initWithName:@"test" address:@"02:00:00:00:00:01" key:[NSMutableData dataWithLength:32]];
    [manager setValue:server forKey:@"server"];
    HABLEAPIConnection *client = [[HABLEAPIConnection alloc] init];
    [manager deviceRequest:@{@1:@[@0x020000000099ULL], @2:@[@1]} connection:client];
    XCTAssertEqual(server.responseType, (NSUInteger)69);
    XCTAssertEqual(server.recipient, client);
    NSDictionary *response = HABLEDecode(server.responseData);
    XCTAssertEqual(HABLEInteger(response, 1), 0x020000000099ULL);
    XCTAssertEqual(HABLEInteger(response, 2), (uint64_t)0);
    XCTAssertEqual(HABLEInteger(response, 4), (uint64_t)0);
}
- (void)testForeignClientCannotClaimOrDisconnectAnOwnedDevice {
    HABLEProxyManager *manager = [[HABLEProxyManager alloc] init];
    HABLECapturingServer *server = [[HABLECapturingServer alloc] initWithName:@"test" address:@"02:00:00:00:00:01" key:[NSMutableData dataWithLength:32]];
    [manager setValue:server forKey:@"server"];
    HABLEAPIConnection *owner = [[HABLEAPIConnection alloc] init], *other = [[HABLEAPIConnection alloc] init];
    id session = [[NSClassFromString(@"HABLEPeripheralSession") alloc] init];
    NSNumber *address = @0x020000000099ULL;
    [session setValue:address forKey:@"address"]; [session setValue:owner forKey:@"owner"];
    NSMutableDictionary *sessions = [manager valueForKey:@"sessions"]; sessions[address] = session;
    for (NSNumber *operation in @[@5, @1]) {
        server.responseType = 0;
        [manager deviceRequest:@{@1:@[address], @2:@[operation]} connection:other];
        XCTAssertEqual(server.responseType, (NSUInteger)69);
        XCTAssertEqual(server.recipient, other);
        XCTAssertNotEqual(HABLEInteger(HABLEDecode(server.responseData), 4), (uint64_t)0);
        XCTAssertEqual(sessions[address], session);
    }
}
- (void)testExistingHomeAssistantEntryUpdatesAreSuccessful {
    XCTAssertTrue([HABLEProxyRegistration isSuccessfulExistingEntryReason:@"already_configured"]);
    XCTAssertTrue([HABLEProxyRegistration isSuccessfulExistingEntryReason:@"already_configured_updates"]);
    XCTAssertFalse([HABLEProxyRegistration isSuccessfulExistingEntryReason:@"invalid_auth"]);
    XCTAssertFalse([HABLEProxyRegistration isSuccessfulExistingEntryReason:nil]);
}
- (void)testSetupKeyCannotBeSentToNonlocalHTTP {
    for (NSString *value in @[@"http://example.com", @"http://8.8.8.8", @"http://192.168.1.1.example.com", @"http:relative", @"ftp://192.168.1.1"]) {
        XCTAssertFalse([HABLEProxyRegistration isSetupURLAllowed:[NSURL URLWithString:value]], @"%@", value);
    }
    XCTAssertFalse([HABLEProxyRegistration isSetupURLAllowed:nil]);
    for (NSString *value in @[@"https://example.com", @"http://192.168.1.1:8123", @"http://10.0.0.2", @"http://172.16.0.1", @"http://127.0.0.1", @"http://homeassistant.local", @"http://[fd00::1]:8123", @"http://[::1]"]) {
        XCTAssertTrue([HABLEProxyRegistration isSetupURLAllowed:[NSURL URLWithString:value]], @"%@", value);
    }
}
- (void)testMalformedAndOverflowingProtobufIsRejected {
    uint8_t overflow[] = {8,255,255,255,255,255,255,255,255,255,2};
    uint8_t truncated[] = {10,8,1,2};
    uint8_t invalidTag[] = {0};
    XCTAssertNil(HABLEDecode([NSData dataWithBytes:overflow length:sizeof(overflow)]));
    XCTAssertNil(HABLEDecode([NSData dataWithBytes:truncated length:sizeof(truncated)]));
    XCTAssertNil(HABLEDecode([NSData dataWithBytes:invalidTag length:sizeof(invalidTag)]));
}
- (void)testProtobufPreservesAddressAndBinaryValues {
    NSMutableData *data = [NSMutableData data];
    HABLEPutInteger(data, 1, 0xF0123456789AULL);
    HABLEPutInteger(data, 9, UINT64_MAX);
    uint8_t bytes[] = {0,255,128,3}; NSData *value = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    HABLEPutBytes(data, 3, value);
    NSDictionary *decoded = HABLEDecode(data);
    XCTAssertEqual(HABLEInteger(decoded, 1), 0xF0123456789AULL);
    XCTAssertEqual(HABLEInteger(decoded, 9), UINT64_MAX);
    XCTAssertEqualObjects(HABLEBytes(decoded, 3), value);
}
- (void)testAddressAssociationRequiresAnUnambiguousAddressFormat {
    uint64_t address = 0;
    XCTAssertTrue(HABLEParseAddress(@"02:ab:cd:12:34:56", &address));
    XCTAssertEqualObjects(HABLEAddressString(address), @"02:AB:CD:12:34:56");
    for (NSString *value in @[@"00:00:00:00:00:00", @"FF:FF:FF:FF:FF:FF", @"GG:00:00:00:00:01", @"1:2:3:4:5:6", @"not-a-device"]) XCTAssertFalse(HABLEParseAddress(value, NULL));
}
- (void)testResetRevokesTheProxyKeyAndDiagnosticsNeverContainIt {
    // Run in the dedicated validation bundle/simulator, not the user's live app.
    HABLEProxyManager *manager = [HABLEProxyManager sharedManager];
    NSString *first = [manager encryptionKey];
    XCTAssertNotNil(first);
    if (!first) return;
    NSData *json = [NSJSONSerialization dataWithJSONObject:manager.diagnostics options:0 error:nil];
    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    XCTAssertEqual([text rangeOfString:first].location, NSNotFound);
    [manager reset];
    XCTAssertFalse(manager.enabled);
    XCTAssertFalse(manager.running);
    XCTAssertFalse([first isEqualToString:[manager encryptionKey]], @"Reset must revoke the old proxy key");
    [manager reset];
}

- (void)testIdenticalRepeatAdvertisementSkipsRegistryMatchingWithEqualBytes {
    HABLEFastPathCountingProxy *proxy = [HABLEFastPathCountingProxy new];
    [proxy setValue:@YES forKey:@"running"]; [proxy setValue:@YES forKey:@"identitiesReady"];
    HABLECountingResolver *resolver = [HABLECountingResolver new];
    [proxy setValue:resolver forKey:@"identityResolver"];
    HABLECapturingServer *server = [[HABLECapturingServer alloc] initWithName:@"test" address:@"02:00:00:00:00:01" key:[NSMutableData dataWithLength:32]];
    [proxy setValue:server forKey:@"server"];
    HABLEObservedPeripheral *peripheral = [HABLEObservedPeripheral new]; peripheral.identifier = NSUUID.UUID; peripheral.name = @"Unit";
    uint8_t bytes[] = {0x34, 0x12, 9, 8, 7};
    NSDictionary *ad = @{CBAdvertisementDataLocalNameKey:@"Unit", CBAdvertisementDataManufacturerDataKey:[NSData dataWithBytes:bytes length:sizeof(bytes)]};
    NSString *identifier = peripheral.identifier.UUIDString;
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-50];
    XCTAssertEqual(server.capturedAdvertisements.count, 0u);
    [proxy valueForKey:@"observations"][identifier][@"first_seen"] = @(NSDate.date.timeIntervalSince1970 - 61);
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-55];
    XCTAssertEqual(server.capturedAdvertisements.count, 2u);
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-60];
    XCTAssertEqual(server.capturedAdvertisements.count, 3u);
    XCTAssertEqual(proxy.fastHits, 1u, @"Only the third packet repeats settled state");
    XCTAssertEqualObjects([proxy valueForKey:@"fastAdvertisements"], @1);
    XCTAssertEqualObjects([proxy valueForKey:@"slowAdvertisements"], @2);
    XCTAssertEqual(resolver.classifications, 1u, @"The repeat must not rescan the registry");
    NSDictionary *second = HABLEDecode(server.capturedAdvertisements[1]);
    NSDictionary *third = HABLEDecode(server.capturedAdvertisements[2]);
    XCTAssertEqual(HABLEInteger(second, 1), HABLEInteger(third, 1));
    XCTAssertEqual(HABLEInteger(second, 7), HABLEInteger(third, 7));
    XCTAssertEqual(HABLEInteger(second, 3), 109u, @"zigzag(-55)");
    XCTAssertEqual(HABLEInteger(third, 3), 119u, @"zigzag(-60)");
    XCTAssertEqualObjects(HABLEFieldsExceptRssi(server.capturedAdvertisements[1]), HABLEFieldsExceptRssi(server.capturedAdvertisements[2]));
    XCTAssertEqualObjects([proxy valueForKey:@"observations"][identifier][@"rssi"], @-60);
    XCTAssertEqualObjects([resolver valueForKey:@"localObservations"][identifier][@"rssi"], @-55, @"Identical repeats must not rewrite the evidence record");
}
- (void)testChangedManufacturerPayloadTakesTheSlowPath {
    HABLEFastPathCountingProxy *proxy = [HABLEFastPathCountingProxy new];
    [proxy setValue:@YES forKey:@"running"]; [proxy setValue:@YES forKey:@"identitiesReady"];
    HABLECountingResolver *resolver = [HABLECountingResolver new];
    [proxy setValue:resolver forKey:@"identityResolver"];
    HABLECapturingServer *server = [[HABLECapturingServer alloc] initWithName:@"test" address:@"02:00:00:00:00:01" key:[NSMutableData dataWithLength:32]];
    [proxy setValue:server forKey:@"server"];
    HABLEObservedPeripheral *peripheral = [HABLEObservedPeripheral new]; peripheral.identifier = NSUUID.UUID; peripheral.name = @"Unit";
    NSString *identifier = peripheral.identifier.UUIDString;
    uint8_t first[] = {0x34, 0x12, 1};
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:@{CBAdvertisementDataLocalNameKey:@"Unit", CBAdvertisementDataManufacturerDataKey:[NSData dataWithBytes:first length:sizeof(first)]} RSSI:@-50];
    [proxy valueForKey:@"observations"][identifier][@"first_seen"] = @(NSDate.date.timeIntervalSince1970 - 61);
    uint8_t second[] = {0x34, 0x12, 2};
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:@{CBAdvertisementDataLocalNameKey:@"Unit", CBAdvertisementDataManufacturerDataKey:[NSData dataWithBytes:second length:sizeof(second)]} RSSI:@-55];
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:@{CBAdvertisementDataLocalNameKey:@"Unit", CBAdvertisementDataManufacturerDataKey:[NSData dataWithBytes:second length:sizeof(second)]} RSSI:@-60];
    XCTAssertEqual(server.capturedAdvertisements.count, 3u);
    XCTAssertEqual(proxy.fastHits, 1u);
    XCTAssertEqual(resolver.classifications, 1u);
    XCTAssertNotEqualObjects(HABLEFieldsExceptRssi(server.capturedAdvertisements[0]), HABLEFieldsExceptRssi(server.capturedAdvertisements[1]));
    XCTAssertEqualObjects(HABLEFieldsExceptRssi(server.capturedAdvertisements[1]), HABLEFieldsExceptRssi(server.capturedAdvertisements[2]));
}
- (void)testRssiVarintWideningFallsBackWithoutLosingAccuracy {
    HABLEFastPathCountingProxy *proxy = [HABLEFastPathCountingProxy new];
    [proxy setValue:@YES forKey:@"running"]; [proxy setValue:@YES forKey:@"identitiesReady"];
    [proxy setValue:[HABLECountingResolver new] forKey:@"identityResolver"];
    HABLECapturingServer *server = [[HABLECapturingServer alloc] initWithName:@"test" address:@"02:00:00:00:00:01" key:[NSMutableData dataWithLength:32]];
    [proxy setValue:server forKey:@"server"];
    HABLEObservedPeripheral *peripheral = [HABLEObservedPeripheral new]; peripheral.identifier = NSUUID.UUID; peripheral.name = @"Unit";
    NSString *identifier = peripheral.identifier.UUIDString;
    uint8_t bytes[] = {0x34, 0x12, 1};
    NSDictionary *ad = @{CBAdvertisementDataLocalNameKey:@"Unit", CBAdvertisementDataManufacturerDataKey:[NSData dataWithBytes:bytes length:sizeof(bytes)]};
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-50];
    [proxy valueForKey:@"observations"][identifier][@"first_seen"] = @(NSDate.date.timeIntervalSince1970 - 61);
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-60];
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-70];
    XCTAssertEqual(server.capturedAdvertisements.count, 3u);
    XCTAssertEqual(proxy.fastHits, 0u, @"-60 (one varint byte) to -70 (two bytes) must rebuild");
    XCTAssertEqual(HABLEInteger(HABLEDecode(server.capturedAdvertisements[1]), 3), 119u);
    XCTAssertEqual(HABLEInteger(HABLEDecode(server.capturedAdvertisements[2]), 3), 139u);
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-71];
    XCTAssertEqual(server.capturedAdvertisements.count, 4u);
    XCTAssertEqual(proxy.fastHits, 1u, @"Same varint width resumes the fast path");
    XCTAssertEqual(HABLEInteger(HABLEDecode(server.capturedAdvertisements[3]), 3), 141u, @"zigzag(-71)");
}
- (void)testManualMappingChangeEmitsNewAddressThenResumesFastPath {
    HABLEFastPathCountingProxy *proxy = [HABLEFastPathCountingProxy new];
    [proxy setValue:@YES forKey:@"running"]; [proxy setValue:@YES forKey:@"identitiesReady"];
    HABLECountingResolver *resolver = [HABLECountingResolver new];
    [proxy setValue:resolver forKey:@"identityResolver"];
    HABLECapturingServer *server = [[HABLECapturingServer alloc] initWithName:@"test" address:@"02:00:00:00:00:01" key:[NSMutableData dataWithLength:32]];
    [proxy setValue:server forKey:@"server"];
    HABLEObservedPeripheral *peripheral = [HABLEObservedPeripheral new]; peripheral.identifier = NSUUID.UUID; peripheral.name = @"Unit";
    NSString *identifier = peripheral.identifier.UUIDString;
    uint8_t bytes[] = {0x34, 0x12, 1};
    NSDictionary *ad = @{CBAdvertisementDataLocalNameKey:@"Unit", CBAdvertisementDataManufacturerDataKey:[NSData dataWithBytes:bytes length:sizeof(bytes)]};
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-50];
    [proxy valueForKey:@"observations"][identifier][@"first_seen"] = @(NSDate.date.timeIntervalSince1970 - 61);
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-60];
    uint64_t aliasAddress = HABLEInteger(HABLEDecode(server.capturedAdvertisements.lastObject), 1);
    [proxy valueForKey:@"mappings"][identifier] = @"00:11:22:33:44:55";
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-70];
    XCTAssertEqual(proxy.fastHits, 0u, @"A mapping change must leave the fast path");
    XCTAssertEqual(HABLEInteger(HABLEDecode(server.capturedAdvertisements.lastObject), 1), 0x001122334455u);
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-71];
    XCTAssertEqual(proxy.fastHits, 1u);
    XCTAssertEqual(HABLEInteger(HABLEDecode(server.capturedAdvertisements.lastObject), 1), 0x001122334455u);
    XCTAssertNotEqual(HABLEInteger(HABLEDecode(server.capturedAdvertisements.lastObject), 1), aliasAddress);
    XCTAssertEqual(resolver.classifications, 1u);
}
- (void)testHeldPacketsQueueCachedBytesAndReleaseTogether {
    HABLEFastPathCountingProxy *proxy = [HABLEFastPathCountingProxy new];
    [proxy setValue:@YES forKey:@"running"]; [proxy setValue:@YES forKey:@"identitiesReady"];
    HABLECountingResolver *resolver = [HABLECountingResolver new];
    [proxy setValue:resolver forKey:@"identityResolver"];
    HABLECapturingServer *server = [[HABLECapturingServer alloc] initWithName:@"test" address:@"02:00:00:00:00:01" key:[NSMutableData dataWithLength:32]];
    [proxy setValue:server forKey:@"server"];
    HABLEObservedPeripheral *peripheral = [HABLEObservedPeripheral new]; peripheral.identifier = NSUUID.UUID; peripheral.name = @"Unit";
    NSString *identifier = peripheral.identifier.UUIDString;
    uint8_t bytes[] = {0x34, 0x12, 1};
    NSDictionary *ad = @{CBAdvertisementDataLocalNameKey:@"Unit", CBAdvertisementDataManufacturerDataKey:[NSData dataWithBytes:bytes length:sizeof(bytes)]};
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-50];
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-60];
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-61];
    XCTAssertEqual(server.capturedAdvertisements.count, 0u);
    XCTAssertEqual([[proxy valueForKey:@"pendingIdentityAdvertisements"] count], 3u);
    XCTAssertEqual(proxy.fastHits, 2u);
    XCTAssertEqual(resolver.classifications, 3u, @"Held repeats re-verify at most on the five-second budget");
    [proxy valueForKey:@"observations"][identifier][@"first_seen"] = @(NSDate.date.timeIntervalSince1970 - 61);
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-71];
    XCTAssertEqual(server.capturedAdvertisements.count, 4u, @"Grace expiry releases the held queue plus the current packet");
    uint64_t address = HABLEInteger(HABLEDecode(server.capturedAdvertisements.lastObject), 1);
    for (NSData *data in server.capturedAdvertisements) XCTAssertEqual(HABLEInteger(HABLEDecode(data), 1), address);
}
- (void)testActiveConnectionSlotForcesTheSlowPath {
    HABLEFastPathCountingProxy *proxy = [HABLEFastPathCountingProxy new];
    [proxy setValue:@YES forKey:@"running"]; [proxy setValue:@YES forKey:@"identitiesReady"];
    [proxy setValue:[HABLECountingResolver new] forKey:@"identityResolver"];
    HABLECapturingServer *server = [[HABLECapturingServer alloc] initWithName:@"test" address:@"02:00:00:00:00:01" key:[NSMutableData dataWithLength:32]];
    [proxy setValue:server forKey:@"server"];
    HABLEObservedPeripheral *peripheral = [HABLEObservedPeripheral new]; peripheral.identifier = NSUUID.UUID; peripheral.name = @"Unit";
    NSString *identifier = peripheral.identifier.UUIDString;
    uint8_t bytes[] = {0x34, 0x12, 1};
    NSDictionary *ad = @{CBAdvertisementDataLocalNameKey:@"Unit", CBAdvertisementDataManufacturerDataKey:[NSData dataWithBytes:bytes length:sizeof(bytes)]};
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-50];
    [proxy valueForKey:@"observations"][identifier][@"first_seen"] = @(NSDate.date.timeIntervalSince1970 - 61);
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-55];
    XCTAssertEqual(proxy.fastHits, 0u);
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-60];
    XCTAssertEqual(proxy.fastHits, 1u);
    [proxy valueForKey:@"sessions"][@1] = [NSObject new];
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-61];
    XCTAssertEqual(proxy.fastHits, 1u, @"Any live connection slot must disable the fast path");
    XCTAssertEqual(server.capturedAdvertisements.count, 4u);
    [[proxy valueForKey:@"sessions"] removeAllObjects];
    [proxy centralManager:nil didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:ad RSSI:@-62];
    XCTAssertEqual(proxy.fastHits, 2u);
    XCTAssertEqual(HABLEInteger(HABLEDecode(server.capturedAdvertisements.lastObject), 3), 123u, @"zigzag(-62)");
}
@end
