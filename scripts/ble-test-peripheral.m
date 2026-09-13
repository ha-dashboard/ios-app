// A temporary, public-CoreBluetooth GATT fixture for physical proxy tests.
// Kept outside the shipping app. Run only during the explicit BLE test session.
#import <AppKit/AppKit.h>
#import <CoreBluetooth/CoreBluetooth.h>

@interface HABLETestPeripheral : NSObject <CBPeripheralManagerDelegate, NSApplicationDelegate>
@property (strong) CBPeripheralManager *manager;
@property (strong) CBMutableCharacteristic *characteristic;
@property (strong) CBUUID *serviceUUID;
@property (strong) NSData *value;
@property (copy) NSString *receiptPath;
@property (strong) NSMutableArray *events;
@property BOOL pendingNotification;
@property (strong) NSWindow *window;
@end
@implementation HABLETestPeripheral
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (void)applicationDidFinishLaunching:(NSNotification *)notification { [self.window makeKeyAndOrderFront:nil]; }
- (void)record:(NSString *)kind data:(NSData *)data {
    NSMutableDictionary *event = [@{@"event":kind, @"time":@([[NSDate date] timeIntervalSince1970])} mutableCopy];
    if (data) event[@"data_hex"] = [data description];
    [self.events addObject:event];
    NSDictionary *receipt = @{@"fixture":@"HA Proxy Test", @"process_id":@([NSProcessInfo processInfo].processIdentifier), @"service_uuid":self.serviceUUID.UUIDString,
        @"characteristic_uuid":self.characteristic.UUID.UUIDString ?: @"", @"events":self.events};
    NSData *json = [NSJSONSerialization dataWithJSONObject:receipt options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:self.receiptPath atomically:YES];
}
- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    [self record:[NSString stringWithFormat:@"state_%ld", (long)peripheral.state] data:nil];
    if (peripheral.state != CBManagerStatePoweredOn) return;
    self.characteristic = [[CBMutableCharacteristic alloc] initWithType:[CBUUID UUIDWithString:@"F2A80102-4F23-4D65-935E-11C071AFFE01"] properties:CBCharacteristicPropertyRead | CBCharacteristicPropertyWrite | CBCharacteristicPropertyNotify value:nil permissions:CBAttributePermissionsReadable | CBAttributePermissionsWriteable];
    CBMutableService *service = [[CBMutableService alloc] initWithType:self.serviceUUID primary:YES]; service.characteristics = @[self.characteristic];
    [peripheral addService:service];
}
- (void)peripheralManager:(CBPeripheralManager *)manager didAddService:(CBService *)service error:(NSError *)error {
    [self record:error ? @"service_error" : @"service_added" data:nil];
    if (!error) [manager startAdvertising:@{CBAdvertisementDataLocalNameKey:@"HA Proxy Test", CBAdvertisementDataServiceUUIDsKey:@[self.serviceUUID]}];
}
- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)manager error:(NSError *)error { [self record:error ? @"advertise_error" : @"advertising" data:nil]; }
- (void)peripheralManager:(CBPeripheralManager *)manager didReceiveReadRequest:(CBATTRequest *)request {
    if (![request.characteristic.UUID isEqual:self.characteristic.UUID]) { [manager respondToRequest:request withResult:CBATTErrorAttributeNotFound]; return; }
    if (request.offset > self.value.length) { [manager respondToRequest:request withResult:CBATTErrorInvalidOffset]; return; }
    request.value = [self.value subdataWithRange:NSMakeRange(request.offset, self.value.length - request.offset)];
    [manager respondToRequest:request withResult:CBATTErrorSuccess]; [self record:@"read" data:request.value];
}
- (void)peripheralManager:(CBPeripheralManager *)manager didReceiveWriteRequests:(NSArray<CBATTRequest *> *)requests {
    for (CBATTRequest *request in requests) {
        if (![request.characteristic.UUID isEqual:self.characteristic.UUID] || request.offset || request.value.length > 128) { [manager respondToRequest:requests.firstObject withResult:CBATTErrorInvalidAttributeValueLength]; return; }
    }
    for (CBATTRequest *request in requests) { self.value = request.value; [self record:@"write" data:request.value]; }
    [manager respondToRequest:requests.firstObject withResult:CBATTErrorSuccess];
    self.pendingNotification = ![manager updateValue:self.value forCharacteristic:self.characteristic onSubscribedCentrals:nil];
    if (!self.pendingNotification) [self record:@"notification_sent" data:self.value];
}
- (void)peripheralManager:(CBPeripheralManager *)manager central:(CBCentral *)central didSubscribeToCharacteristic:(CBCharacteristic *)characteristic { [self record:@"subscribed" data:nil]; }
- (void)peripheralManager:(CBPeripheralManager *)manager central:(CBCentral *)central didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic { [self record:@"unsubscribed" data:nil]; }
- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)manager {
    if (self.pendingNotification) { self.pendingNotification = ![manager updateValue:self.value forCharacteristic:self.characteristic onSubscribedCentrals:nil]; if (!self.pendingNotification) [self record:@"notification_sent" data:self.value]; }
}
@end
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        [NSApplication sharedApplication];
        HABLETestPeripheral *fixture = [[HABLETestPeripheral alloc] init];
        fixture.receiptPath = @(argv[1]); fixture.events = [NSMutableArray array];
        fixture.serviceUUID = [CBUUID UUIDWithNSUUID:[NSUUID UUID]];
        fixture.value = [@"HA-BLE-FIXTURE" dataUsingEncoding:NSUTF8StringEncoding];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; [NSApp setDelegate:fixture];
        fixture.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 180) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        fixture.window.title = @"HA Proxy Test · Bluetooth peripheral";
        NSTextField *label = [NSTextField wrappingLabelWithString:[NSString stringWithFormat:@"Temporary BLE test peripheral\n\nService: %@\n\nAccepts test reads, writes and notifications. Close this window to stop it.", fixture.serviceUUID.UUIDString]];
        label.frame = NSMakeRect(20, 20, 480, 140); [fixture.window.contentView addSubview:label]; [fixture.window center];
        fixture.manager = [[CBPeripheralManager alloc] initWithDelegate:fixture queue:nil options:nil];
        [NSApp run];
        [fixture.manager stopAdvertising]; [fixture.manager removeAllServices];
    }
}
