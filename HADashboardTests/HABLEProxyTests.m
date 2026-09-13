#import <XCTest/XCTest.h>
#import "HABLEProto.h"
#import "HABLEProxyManager.h"
#import "HABLEProxyRegistration.h"
#import "HABLEAPIServer.h"
#import "HAAPIClient.h"
#import "HABLEIdentityResolver.h"
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
- (void)matchIdentifier:(NSString *)identifier;
- (void)finishOperation:(id)session error:(NSUInteger)error;
- (void)discoveryPartDone:(id)session;
- (NSTimeInterval)identityProbeIntervalForObservation:(NSDictionary *)observation;
- (void)probePendingIdentity;
- (void)updateIdentityResolution;
- (void)flushIdentityAdvertisements;
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisement RSSI:(NSNumber *)RSSI;
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
@end
@implementation HABLEFailingProbeProxy
- (void)inspectIdentifier:(NSString *)identifier completion:(void (^)(NSDictionary *,NSError *))completion {self.inspections++;completion(nil,[NSError errorWithDomain:@"test" code:1 userInfo:nil]);}
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
@end
