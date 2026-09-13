#import <XCTest/XCTest.h>
#import "HABLEProto.h"
#import "HABLEProxyManager.h"
#import "HABLEProxyRegistration.h"
#import "HABLEAPIServer.h"
#import "HAAPIClient.h"
#import "HABLEIdentityResolver.h"

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
- (void)deviceRequest:(NSDictionary *)fields connection:(HABLEAPIConnection *)connection;
- (void)bleServer:(HABLEAPIServer *)server receivedType:(NSUInteger)type data:(NSData *)data connection:(HABLEAPIConnection *)connection;
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

@interface HABLECapturingServer : HABLEAPIServer
@property (nonatomic) NSUInteger responseType;
@property (nonatomic, strong) NSData *responseData;
@property (nonatomic, strong) HABLEAPIConnection *recipient;
@end
@implementation HABLECapturingServer
- (void)sendType:(NSUInteger)type data:(NSData *)data to:(HABLEAPIConnection *)connection {
    self.responseType = type; self.responseData = data; self.recipient = connection;
}
@end

@interface HABLEProxyTests : XCTestCase
@end
@implementation HABLEProxyTests
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
- (void)testPublishedAddressesKeepTheirIdentityAndUseHAFriendlyNames {
    HABLEIdentityResolver *resolver = [[HABLEIdentityResolver alloc] init];
    [resolver loadRegistry:@[@{@"id":@"meter", @"name":@"Raw meter name", @"name_by_user":@"Bedroom climate", @"connections":@[@[@"bluetooth", @"00:11:22:33:44:55"]]}] entries:@[] excludingSource:@"02:00:00:00:00:01"];
    HABLEProxyManager *proxy = [[HABLEProxyManager alloc] init];
    [proxy setValue:resolver forKey:@"identityResolver"]; [proxy setValue:@YES forKey:@"identitiesReady"];
    NSMutableDictionary *observation = [@{@"name":@"Raw meter name", @"identity":@"switchbot_advertised_mac", @"address":@"00:11:22:33:44:55"} mutableCopy];
    [proxy setValue:[@{@"local-id":observation} mutableCopy] forKey:@"observations"];
    [proxy setValue:[@{@"local-id":@"00:11:22:33:44:55"} mutableCopy] forKey:@"advertisedAddresses"];
    [proxy matchIdentifier:@"local-id"];
    XCTAssertEqualObjects(observation[@"ha_name"], @"Bedroom climate");
    XCTAssertEqualObjects(observation[@"identity"], @"switchbot_advertised_mac");
    [observation removeObjectForKey:@"ha_name"];
    [proxy matchIdentifier:@"local-id"];
    XCTAssertEqualObjects(observation[@"ha_name"], @"Bedroom climate", @"Fresh advertisements retain the cached friendly name");
}
- (HABLEIdentityResolver *)poolIdentityResolver {
    HABLEIdentityResolver *resolver = [[HABLEIdentityResolver alloc] init];
    [resolver loadRegistry:@[
        @{@"id":@"pool", @"name":@"B201ABCDEF", @"manufacturer":@"Blue Riiot", @"identifiers":@[@[@"blue_connect", @"B201ABCDEF"]], @"connections":@[], @"config_entries":@[@"pool-entry"]},
        @{@"id":@"app-proxy", @"manufacturer":@"ha-dashboard", @"connections":@[@[@"mac", @"02:00:00:00:00:01"]], @"config_entries":@[@"app-entry"]},
        @{@"id":@"native-adapter", @"connections":@[@[@"bluetooth", @"00:00:00:00:00:01"]], @"config_entries":@[@"adapter-entry"]}
    ] entries:@[@{@"domain":@"bluetooth", @"entry_id":@"adapter-entry"}] excludingSource:@"02:00:00:00:00:02"];
    return resolver;
}
- (NSDictionary *)poolAdvertisementWithAddress:(NSString *)address source:(NSString *)source {
    return @{@"name":@"B201ABCDEF", @"address":address, @"source":source, @"manufacturer_data":@{@"305":@"0102030405060708090a0b"}, @"service_uuids":@[]};
}
- (NSDictionary *)poolObservation {
    const uint8_t bytes[] = {0x31, 0x01, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11};
    return @{@"name":@"B201ABCDEF", @"identity":@"local_alias", @"address":@"02:00:00:00:00:03", @"manufacturer_data":[[NSData dataWithBytes:bytes length:sizeof(bytes)] base64EncodedStringWithOptions:0], @"service_uuids":@[]};
}
- (void)testIdentityImportsIntegrationIDWithoutRegistryAddressAndRejectsProxyAliases {
    HABLEIdentityResolver *resolver = [self poolIdentityResolver];
    XCTAssertEqual(resolver.knownDevices.count, 1u);
    XCTAssertEqualObjects(resolver.knownDevices.firstObject[@"address"], @"");
    [resolver observeAdvertisements:@[[self poolAdvertisementWithAddress:@"02:00:00:00:00:03" source:@"02:00:00:00:00:01"]]];
    XCTAssertNil([resolver automaticMatchForObservation:[self poolObservation]], @"Another app proxy must never establish a real address");
    [resolver observeAdvertisements:@[[self poolAdvertisementWithAddress:@"00:11:22:33:44:55" source:@"00:00:00:00:00:01"]]];
    NSDictionary *match = [resolver automaticMatchForObservation:[self poolObservation]];
    XCTAssertEqualObjects(match[@"address"], @"00:11:22:33:44:55", @"Independent native adapters must remain valid evidence");
}
- (void)testIdentityNeverAutomaticallyMatchesNamesOrMeasurementsAlone {
    HABLEIdentityResolver *resolver = [self poolIdentityResolver];
    [resolver observeAdvertisements:@[[self poolAdvertisementWithAddress:@"00:11:22:33:44:55" source:@"00:00:00:00:00:01"]]];
    NSMutableDictionary *observation = [[self poolObservation] mutableCopy];
    observation[@"manufacturer_data"] = @"";
    XCTAssertNil([resolver automaticMatchForObservation:observation]);
    observation = [[self poolObservation] mutableCopy]; observation[@"name"] = @"Pool Sensor";
    XCTAssertNil([resolver automaticMatchForObservation:observation]);
    [observation removeObjectForKey:@"name"];
    XCTAssertNil([resolver automaticMatchForObservation:observation]);
}
- (void)testConflictingIndependentAddressesRequireConfirmation {
    HABLEIdentityResolver *resolver = [self poolIdentityResolver];
    [resolver observeAdvertisements:@[
        [self poolAdvertisementWithAddress:@"00:11:22:33:44:55" source:@"00:00:00:00:00:01"],
        [self poolAdvertisementWithAddress:@"00:11:22:33:44:66" source:@"00:00:00:00:00:01"]
    ]];
    XCTAssertNil([resolver automaticMatchForObservation:[self poolObservation]]);
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
