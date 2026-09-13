#import <XCTest/XCTest.h>
#import "HABLEProto.h"
#import "HABLEProxyManager.h"
#import "HABLEProxyRegistration.h"
#import "HABLEAPIServer.h"

@interface HABLEProxyManager (ProtocolTestAccess)
- (void)deviceRequest:(NSDictionary *)fields connection:(HABLEAPIConnection *)connection;
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
