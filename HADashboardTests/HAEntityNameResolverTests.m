#import <XCTest/XCTest.h>
#import "HAEntityNameResolver.h"
#import "HAConnectionManager.h"

/// processDeviceRegistry: is an internal method (declared only in the .m file)
/// that builds deviceNamesByDeviceId. Redeclare it here so the test can call
/// it directly rather than via performSelector:, without exposing it as
/// public API in the production header.
@interface HAConnectionManager (HAEntityNameResolverTesting)
- (void)processDeviceRegistry:(id)result;
@end

@interface HAEntityNameResolverTests : XCTestCase
@end

@implementation HAEntityNameResolverTests

- (HAEntityNameRegistryContext *)fullContext {
    return [HAEntityNameRegistryContext
        contextWithEntityAreaMap:@{@"light.bedroom": @"area_bedroom",
                                    @"light.noprefix": @"area_bedroom",
                                    @"light.justdevice": @"area_bedroom"}
                        areaNames:@{@"area_bedroom": @"Bedroom"}
                  entityDeviceMap:@{@"light.bedroom": @"device_abc",
                                     @"light.noprefix": @"device_abc",
                                     @"light.justdevice": @"device_abc"}
                      deviceNames:@{@"device_abc": @"Lamp"}
               floorNamesByAreaId:@{@"area_bedroom": @"Upstairs"}
              entityRegistryNames:@{
                  // Has the device name as a leading prefix — should be stripped.
                  @"light.bedroom": @"Lamp Brightness",
                  // Does not start with the device name — used as-is.
                  @"light.noprefix": @"Reading Light",
                  // Is just the device name (plus separators) — no name of its own.
                  @"light.justdevice": @"Lamp",
              }];
}

#pragma mark - Plain string

- (void)testResolve_plainString_isTrimmedAndReturned {
    NSString *result = [HAEntityNameResolver resolveNameValue:@"  Living Room  "
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertEqualObjects(result, @"Living Room");
}

- (void)testResolve_emptyString_returnsNil {
    NSString *result = [HAEntityNameResolver resolveNameValue:@"   "
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertNil(result);
}

#pragma mark - Each supported type

- (void)testResolve_area_resolvesAreaName {
    NSString *result = [HAEntityNameResolver resolveNameValue:@{@"type": @"area"}
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertEqualObjects(result, @"Bedroom");
}

- (void)testResolve_device_resolvesDeviceName {
    NSString *result = [HAEntityNameResolver resolveNameValue:@{@"type": @"device"}
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertEqualObjects(result, @"Lamp");
}

- (void)testResolve_floor_resolvesFloorName {
    NSString *result = [HAEntityNameResolver resolveNameValue:@{@"type": @"floor"}
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertEqualObjects(result, @"Upstairs");
}

- (void)testResolve_text_returnsLiteralText {
    NSString *result = [HAEntityNameResolver resolveNameValue:@{@"type": @"text", @"text": @"Front Door"}
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertEqualObjects(result, @"Front Door");
}

- (void)testResolve_entity_returnsNilByDesign {
    // Requesting the entity's own name is equivalent to no override; the
    // caller is expected to fall back to its normal entity display name.
    NSString *result = [HAEntityNameResolver resolveNameValue:@{@"type": @"entity"}
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertNil(result);
}

#pragma mark - Array form

- (void)testResolve_arrayOfTwoItems_joinsWithSpace {
    NSString *result = [HAEntityNameResolver resolveNameValue:@[@{@"type": @"area"}, @{@"type": @"device"}]
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertEqualObjects(result, @"Bedroom Lamp");
}

- (void)testResolve_arrayWithOneUnresolvedItem_dropsIt {
    NSString *result = [HAEntityNameResolver resolveNameValue:@[@{@"type": @"floor"}, @{@"type": @"something_future"}]
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertEqualObjects(result, @"Upstairs");
}

- (void)testResolve_arrayAllUnresolved_returnsNil {
    // "light.unregistered" has no entityRegistryNames entry, so the "entity"
    // item can't be resolved either — same as "something_future".
    NSString *result = [HAEntityNameResolver resolveNameValue:@[@{@"type": @"entity"}, @{@"type": @"something_future"}]
                                                     forEntityId:@"light.unregistered"
                                                         context:[self fullContext]];
    XCTAssertNil(result);
}

#pragma mark - Array form: explicit "entity" item (joins the entity's own name)

- (void)testResolve_arrayAreaAndEntity_joinsAreaAndStrippedEntityName {
    // device "Lamp" + registry name "Lamp Brightness" => entity part "Brightness".
    NSString *result = [HAEntityNameResolver resolveNameValue:@[@{@"type": @"area"}, @{@"type": @"entity"}]
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertEqualObjects(result, @"Bedroom Brightness");
}

- (void)testResolve_arrayDeviceAndEntity_withDevicePrefix_stripsPrefix {
    // device "Lamp" + registry name "Lamp Brightness" => "Lamp" + "Brightness".
    NSString *result = [HAEntityNameResolver resolveNameValue:@[@{@"type": @"device"}, @{@"type": @"entity"}]
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertEqualObjects(result, @"Lamp Brightness");
}

- (void)testResolve_arrayDeviceAndEntity_withoutDevicePrefix_usesRegistryNameAsIs {
    // device "Lamp" + registry name "Reading Light" (no "Lamp" prefix) => unchanged.
    NSString *result = [HAEntityNameResolver resolveNameValue:@[@{@"type": @"device"}, @{@"type": @"entity"}]
                                                     forEntityId:@"light.noprefix"
                                                         context:[self fullContext]];
    XCTAssertEqualObjects(result, @"Lamp Reading Light");
}

- (void)testResolve_singleItemEntity_stillFallsBackToNil {
    // A bare {"type": "entity"} — whether as the plain object form or a
    // one-item array — must behave exactly like the no-name case: nil, so
    // the caller falls back to its own entity display name. HA's own join
    // rule for the entity's *own* name (with device-prefix stripping) only
    // kicks in inside a multi-item array.
    NSString *singleObject = [HAEntityNameResolver resolveNameValue:@{@"type": @"entity"}
                                                           forEntityId:@"light.bedroom"
                                                               context:[self fullContext]];
    XCTAssertNil(singleObject);
}

- (void)testResolve_arrayWithOnlyEntity_stillFallsBackToNil {
    NSArray *nameValue = @[@{@"type": @"entity"}];
    NSString *result = [HAEntityNameResolver resolveNameValue:nameValue
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertNil(result);
}

- (void)testResolve_arrayDeviceAndEntity_entityNameIsJustDeviceName_dropsEntityPart {
    // registry name "Lamp" equals the device name — the entity has no name
    // of its own, so only the device part survives the join.
    NSString *result = [HAEntityNameResolver resolveNameValue:@[@{@"type": @"device"}, @{@"type": @"entity"}]
                                                     forEntityId:@"light.justdevice"
                                                         context:[self fullContext]];
    XCTAssertEqualObjects(result, @"Lamp");
}

- (void)testResolve_emptyArray_returnsNil {
    NSString *result = [HAEntityNameResolver resolveNameValue:@[]
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertNil(result);
}

#pragma mark - Unknown type

- (void)testResolve_unknownType_degradesToNil {
    NSString *result = [HAEntityNameResolver resolveNameValue:@{@"type": @"parent_device"}
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertNil(result);
}

- (void)testResolve_missingType_degradesToNil {
    NSString *result = [HAEntityNameResolver resolveNameValue:@{@"not_type": @"area"}
                                                     forEntityId:@"light.bedroom"
                                                         context:[self fullContext]];
    XCTAssertNil(result);
}

#pragma mark - Nonsense values (never crash)

- (void)testResolve_number_doesNotCrashAndReturnsNil {
    __block NSString *result = nil;
    XCTAssertNoThrow(result = [HAEntityNameResolver resolveNameValue:@42
                                                            forEntityId:@"light.bedroom"
                                                                context:[self fullContext]]);
    XCTAssertNil(result);
}

- (void)testResolve_boolean_doesNotCrashAndReturnsNil {
    __block NSString *result = nil;
    XCTAssertNoThrow(result = [HAEntityNameResolver resolveNameValue:@(YES)
                                                            forEntityId:@"light.bedroom"
                                                                context:[self fullContext]]);
    XCTAssertNil(result);
}

- (void)testResolve_nestedArray_doesNotCrashAndDegradesThatSlot {
    __block NSString *result = nil;
    NSArray *nameValue = @[@[@"nested"], @{@"type": @"area"}];
    XCTAssertNoThrow(result = [HAEntityNameResolver resolveNameValue:nameValue
                                                            forEntityId:@"light.bedroom"
                                                                context:[self fullContext]]);
    XCTAssertEqualObjects(result, @"Bedroom");
}

- (void)testResolve_dictWithNonStringText_doesNotCrash {
    __block NSString *result = nil;
    NSDictionary *nameValue = @{@"type": @"text", @"text": @99};
    XCTAssertNoThrow(result = [HAEntityNameResolver resolveNameValue:nameValue
                                                            forEntityId:@"light.bedroom"
                                                                context:[self fullContext]]);
    XCTAssertNil(result);
}

- (void)testResolve_nilEntityId_doesNotCrash {
    __block NSString *result = nil;
    XCTAssertNoThrow(result = [HAEntityNameResolver resolveNameValue:@{@"type": @"area"}
                                                            forEntityId:nil
                                                                context:[self fullContext]]);
    XCTAssertNil(result);
}

- (void)testResolve_nilContext_doesNotCrash {
    __block NSString *result = nil;
    XCTAssertNoThrow(result = [HAEntityNameResolver resolveNameValue:@{@"type": @"area"}
                                                            forEntityId:@"light.bedroom"
                                                                context:nil]);
    XCTAssertNil(result);
}

#pragma mark - No registry data

- (void)testResolve_emptyContext_degradesToNilForRegistryTypes {
    HAEntityNameRegistryContext *empty = [HAEntityNameRegistryContext emptyContext];
    XCTAssertNil([HAEntityNameResolver resolveNameValue:@{@"type": @"area"} forEntityId:@"light.bedroom" context:empty]);
    XCTAssertNil([HAEntityNameResolver resolveNameValue:@{@"type": @"device"} forEntityId:@"light.bedroom" context:empty]);
    XCTAssertNil([HAEntityNameResolver resolveNameValue:@{@"type": @"floor"} forEntityId:@"light.bedroom" context:empty]);
}

#pragma mark - Device registry: NSNull name_by_user robustness

/// The device registry entry's "name_by_user" is JSON null when the user
/// hasn't renamed the device. HAConnectionManager must fall back to "name"
/// rather than storing NSNull as the device's display name.
- (void)testDeviceRegistry_nullNameByUser_fallsBackToName {
    HAConnectionManager *conn = [[HAConnectionManager alloc] init];
    NSArray *devices = @[
        @{@"id": @"device_abc", @"name_by_user": [NSNull null], @"name": @"Bedroom Lamp"}
    ];
    XCTAssertNoThrow({
        [conn processDeviceRegistry:devices];
    });
    XCTAssertEqualObjects(conn.deviceNamesByDeviceId[@"device_abc"], @"Bedroom Lamp");
}

- (void)testDeviceRegistry_stringNameByUser_takesPriorityOverName {
    HAConnectionManager *conn = [[HAConnectionManager alloc] init];
    NSArray *devices = @[
        @{@"id": @"device_abc", @"name_by_user": @"My Lamp", @"name": @"Bedroom Lamp"}
    ];
    [conn processDeviceRegistry:devices];
    XCTAssertEqualObjects(conn.deviceNamesByDeviceId[@"device_abc"], @"My Lamp");
}

- (void)testDeviceRegistry_nullNameByUserAndNullName_omitsDevice {
    HAConnectionManager *conn = [[HAConnectionManager alloc] init];
    NSArray *devices = @[
        @{@"id": @"device_abc", @"name_by_user": [NSNull null], @"name": [NSNull null]}
    ];
    XCTAssertNoThrow({
        [conn processDeviceRegistry:devices];
    });
    XCTAssertNil(conn.deviceNamesByDeviceId[@"device_abc"]);
}

@end
