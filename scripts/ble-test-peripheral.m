// A temporary, public-CoreBluetooth GATT fixture for physical proxy tests.
// Kept outside the shipping app. Run only during the explicit BLE test session.
#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#define HABLEApplicationDelegate NSApplicationDelegate
#else
#import <UIKit/UIKit.h>
#define HABLEApplicationDelegate UIApplicationDelegate
#endif
#import <CoreBluetooth/CoreBluetooth.h>

@interface HABLETestPeripheral : NSObject <CBPeripheralManagerDelegate, HABLEApplicationDelegate>
@property (strong) CBPeripheralManager *manager;
@property (strong) CBMutableCharacteristic *characteristic;
@property (strong) CBUUID *serviceUUID;
@property (strong) NSData *value;
@property (copy) NSString *receiptPath;
@property (strong) NSMutableArray *events;
@property BOOL pendingNotification;
@property (strong) NSTimer *heartbeatTimer;
- (NSDictionary *)advertisingData;
#if TARGET_OS_OSX
@property (strong) NSWindow *window;
#else
@property (strong) UIWindow *window;
@property (strong) UILabel *statusLabel;
#endif
@end
@implementation HABLETestPeripheral
#if TARGET_OS_OSX
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (void)applicationDidFinishLaunching:(NSNotification *)notification { [self.window makeKeyAndOrderFront:nil]; }
#else
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.receiptPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"ble-fixture.json"];
    self.events = [NSMutableArray array]; self.serviceUUID = [CBUUID UUIDWithNSUUID:[NSUUID UUID]];
    self.value = [@"HA-BLE-FIXTURE" dataUsingEncoding:NSUTF8StringEncoding];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *controller = [[UIViewController alloc] init];
    controller.view.backgroundColor = UIColor.whiteColor;
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectInset(self.window.bounds, 24, 60)];
    self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.statusLabel.numberOfLines = 0; self.statusLabel.font = [UIFont systemFontOfSize:18];
    self.statusLabel.textColor = UIColor.blackColor;
    [controller.view addSubview:self.statusLabel]; self.window.rootViewController = controller;
    [self.window makeKeyAndVisible]; application.idleTimerDisabled = YES;
    [self record:@"starting" data:nil];
    self.manager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil options:nil];
    self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(heartbeat:) userInfo:nil repeats:YES];
    return YES;
}
- (void)applicationDidEnterBackground:(UIApplication *)application {
    [self.manager stopAdvertising]; [self record:@"paused_background" data:nil];
}
- (void)applicationWillEnterForeground:(UIApplication *)application {
    if (self.manager.state == CBPeripheralManagerStatePoweredOn && self.characteristic)
        [self.manager startAdvertising:[self advertisingData]];
}
#endif
- (void)record:(NSString *)kind data:(NSData *)data {
    NSMutableDictionary *event = [@{@"event":kind, @"time":@([[NSDate date] timeIntervalSince1970])} mutableCopy];
    if (data) event[@"data_hex"] = [data description];
    [self.events addObject:event];
    [self writeReceipt];
}
- (void)heartbeat:(NSTimer *)timer { [self writeReceipt]; }
- (NSDictionary *)advertisingData {
    NSMutableDictionary *data = [@{CBAdvertisementDataServiceUUIDsKey:@[self.serviceUUID]} mutableCopy];
    // Service-only advertising fits in the foreground payload. Adding a name
    // can move a 128-bit service to Apple's filter-only overflow area.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"HABLEReferenceIncludeName"]) data[CBAdvertisementDataLocalNameKey] = @"HA Proxy Test";
    return data;
}
- (void)writeReceipt {
    NSMutableDictionary *receipt = [@{@"fixture":@"HA Proxy Test", @"process_id":@([NSProcessInfo processInfo].processIdentifier), @"service_uuid":self.serviceUUID.UUIDString,
        @"characteristic_uuid":self.characteristic.UUID.UUIDString ?: @"", @"events":self.events,
        @"time":@([[NSDate date] timeIntervalSince1970]), @"advertising":@(self.manager.isAdvertising), @"peripheral_state":@(self.manager.state), @"includes_local_name":@([[NSUserDefaults standardUserDefaults] boolForKey:@"HABLEReferenceIncludeName"])} mutableCopy];
#if !TARGET_OS_OSX
    receipt[@"application_state"] = @([UIApplication sharedApplication].applicationState);
#endif
    NSData *json = [NSJSONSerialization dataWithJSONObject:receipt options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:self.receiptPath atomically:YES];
#if !TARGET_OS_OSX
    self.statusLabel.text = [NSString stringWithFormat:@"Bluetooth test reference\n\nKeep this app open during the proxy checks. It accepts only temporary test reads, writes and notifications.\n\nService:\n%@\n\nStatus: %@\nEvents: %lu\n\nReturn to HA Dashboard when testing is finished.", self.serviceUUID.UUIDString, self.events.lastObject[@"event"] ?: @"starting", (unsigned long)self.events.count];
#endif
}
- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    [self record:[NSString stringWithFormat:@"state_%ld", (long)peripheral.state] data:nil];
    if (peripheral.state != CBPeripheralManagerStatePoweredOn) return;
    self.characteristic = [[CBMutableCharacteristic alloc] initWithType:[CBUUID UUIDWithString:@"F2A80102-4F23-4D65-935E-11C071AFFE01"] properties:CBCharacteristicPropertyRead | CBCharacteristicPropertyWrite | CBCharacteristicPropertyNotify value:nil permissions:CBAttributePermissionsReadable | CBAttributePermissionsWriteable];
    CBMutableService *service = [[CBMutableService alloc] initWithType:self.serviceUUID primary:YES]; service.characteristics = @[self.characteristic];
    [peripheral addService:service];
}
- (void)peripheralManager:(CBPeripheralManager *)manager didAddService:(CBService *)service error:(NSError *)error {
    [self record:error ? @"service_error" : @"service_added" data:nil];
    if (!error) [manager startAdvertising:[self advertisingData]];
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
int main(int argc, char **argv) {
    @autoreleasepool {
#if TARGET_OS_OSX
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
        fixture.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:fixture selector:@selector(heartbeat:) userInfo:nil repeats:YES];
        [NSApp run];
        [fixture.manager stopAdvertising]; [fixture.manager removeAllServices];
#else
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([HABLETestPeripheral class]));
#endif
    }
}
