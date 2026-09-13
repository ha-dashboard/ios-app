// Public CoreBluetooth receiver control for legacy-device proxy diagnostics.
// The requested service is supplied by HABLEReferenceServiceUUID in Info.plist.
#import <UIKit/UIKit.h>
#import <CoreBluetooth/CoreBluetooth.h>

@interface HABLEReceiver : NSObject <UIApplicationDelegate, CBCentralManagerDelegate>
@property (strong) UIWindow *window;
@property (strong) UILabel *label;
@property (strong) CBCentralManager *central;
@property (strong) CBUUID *service;
@property (strong) NSMutableDictionary *counts;
@property (strong) NSMutableDictionary *matches;
@property (strong) NSMutableArray *events;
@property (copy) NSString *phase;
@property (copy) NSString *receiptPath;
@property NSUInteger generation;
@property BOOL complete;
- (void)runPhase:(NSUInteger)index generation:(NSUInteger)generation;
@end
@implementation HABLEReceiver
- (void)record:(NSString *)event {
    [self.events addObject:@{@"event":event, @"time":@([[NSDate date] timeIntervalSince1970])}];
    NSDictionary *receipt = @{@"service_uuid":self.service.UUIDString, @"phase":self.phase ?: @"starting",
        @"counts":self.counts, @"matches":self.matches, @"events":self.events, @"complete":@(self.complete),
        @"process_id":@([NSProcessInfo processInfo].processIdentifier), @"central_state":@(self.central.state),
        @"application_state":@([UIApplication sharedApplication].applicationState)};
    [[NSJSONSerialization dataWithJSONObject:receipt options:NSJSONWritingPrettyPrinted error:nil] writeToFile:self.receiptPath atomically:YES];
    self.label.text = [NSString stringWithFormat:@"Bluetooth receiver check\n\nKeep this app open for one minute.\n\nService:\n%@\n\nPhase: %@\nCallbacks: %@\nReference matches: %@\n\n%@", self.service.UUIDString, self.phase ?: @"starting", self.counts, self.matches, self.complete ? @"Finished" : @"Checking…"];
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSString *uuid = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"HABLEReferenceServiceUUID"];
    if (!uuid.length) return NO;
    self.service = [CBUUID UUIDWithString:uuid];
    self.counts = [@{@"unfiltered":@0, @"empty_services":@0, @"default_options":@0, @"filtered":@0} mutableCopy]; self.matches = [NSMutableDictionary dictionary]; self.events = [NSMutableArray array];
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    self.receiptPath = [documents stringByAppendingPathComponent:@"ble-receiver.json"];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *controller = [[UIViewController alloc] init]; controller.view.backgroundColor = UIColor.whiteColor;
    self.label = [[UILabel alloc] initWithFrame:CGRectInset(self.window.bounds, 24, 50)];
    self.label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.label.numberOfLines = 0; self.label.font = [UIFont systemFontOfSize:18]; self.label.textColor = UIColor.blackColor;
    [controller.view addSubview:self.label]; self.window.rootViewController = controller; [self.window makeKeyAndVisible]; application.idleTimerDisabled = YES;
    [self record:@"starting"];
    self.central = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:nil];
    return YES;
}
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    [self record:[NSString stringWithFormat:@"central_state_%ld", (long)central.state]];
    if (central.state != CBCentralManagerStatePoweredOn || self.phase) return;
    [self runPhase:0 generation:++self.generation];
}
- (void)runPhase:(NSUInteger)index generation:(NSUInteger)generation {
    NSArray *phases = @[@"unfiltered", @"empty_services", @"default_options", @"filtered"];
    if (index == phases.count) { self.complete = YES; [self record:@"finished"]; return; }
    self.phase = phases[index];
    NSArray *services = index == 1 ? @[] : index == 3 ? @[self.service] : nil;
    NSDictionary *options = index == 2 ? nil : @{CBCentralManagerScanOptionAllowDuplicatesKey:@YES};
    [self.central scanForPeripheralsWithServices:services options:options];
    [self record:[self.phase stringByAppendingString:@"_scan_started"]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (generation != self.generation || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
        [self.central stopScan];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (generation != self.generation || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
            [self runPhase:index + 1 generation:generation];
        });
    });
}
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisement RSSI:(NSNumber *)RSSI {
    self.counts[self.phase] = @([self.counts[self.phase] unsignedIntegerValue] + 1);
    NSArray *services = advertisement[CBAdvertisementDataServiceUUIDsKey];
    NSArray *overflow = advertisement[CBAdvertisementDataOverflowServiceUUIDsKey];
    if ([services containsObject:self.service] || [overflow containsObject:self.service]) {
        BOOL first = !self.matches[self.phase]; self.matches[self.phase] = RSSI;
        if (first) [self record:@"reference_seen"];
    }
}
- (void)applicationDidEnterBackground:(UIApplication *)application {
    self.generation++; [self.central stopScan]; [self record:@"backgrounded"];
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([HABLEReceiver class])); }
}
